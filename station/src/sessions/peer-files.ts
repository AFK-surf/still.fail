// Files between sessions on different stations of the workspace: an agent reading a chat there (chat_read) gets its
// attachments here, and one writing to a session there (session_send) takes its files along. Both go over the station
// transport in chunks, as task files do (jobs/remote.ts), with no more trust than the chats' pages need: a chat's
// attachments are what any member of the workspace sees on its page.
import { randomUUID } from "node:crypto";
import { closeSync, constants, copyFileSync, existsSync, fstatSync, mkdirSync, openSync, readdirSync, readSync, renameSync, rmSync, statSync, writeFileSync, writeSync } from "node:fs";
import { basename, dirname, isAbsolute, join } from "node:path";
import { anyBaseName, clean, samePath } from "../ops/paths.ts";
import { iso } from "../read/transcript.ts";
import type { Attachment } from "../store/store.ts";
import { CHUNK, hash } from "../jobs/remote.ts";
import { withLock, workspaceFile } from "./archive.ts";
import { roomOf } from "./footprint.ts";
import type { Hub } from "./hub.ts";
import { imageSize } from "./image-size.ts";
import { Refused } from "./neighbours.ts";
import { fromBefore, named } from "./others.ts";

type Json = any;
type Call = (station: string, request: Json) => Promise<Json>;

/// The method a chat's attachment is read by, a chunk at a time (`fileForPeer`).
export const FILE = "session.file";
/// The method a file sent along with a message comes by, a chunk at a time, before the message (`putForPeer`).
export const PUT = "session.put";

/// Attachments up to this size come with a read of their chat by themselves; larger ones when asked for.
export const FETCHED = 16 * 1024 * 1024;
/// At most this much comes by itself with one read.
const FETCHED_IN_ALL = 64 * 1024 * 1024;
/// As chat_post: at most this many files of at most this size with one message.
const MAX_FILES = 10;
const MAX_SENT = 50 * 1024 * 1024;
/// A file sent along that its message never claimed is removed after this long.
const STAGED_MS = 24 * 3600 * 1000;

const IMAGES = [".png", ".jpg", ".jpeg", ".gif", ".webp"];

/// A name as a file in uploads is named: stamped, nothing that leaves the directory.
function uploadName(hub: Hub, name: string): string {
  const stamp = iso(hub.now()).slice(0, 19).replace(/[:.]/g, "-");
  const safe = Array.from(name)
    .map((c) => (c === "\\" || c === "/" || c.codePointAt(0)! < 0x20 ? "_" : c))
    .join("");
  return `${stamp}-${safe}`;
}

/// An attachment as messages keep it: images measured, so pages hold their place.
function attachment(name: string, path: string, size: number): Attachment {
  const found: Attachment = { name, path, size };
  const measured = IMAGES.some((e) => name.toLowerCase().endsWith(e)) ? imageSize(path) : null;
  if (measured) [found.width, found.height] = measured;
  return found;
}

// ── a chat's attachments, read from another station ──────────────────────────────────────────────────────────────

/// What another station's session reads of a chat's attachment here (`fetchAttachments` there): a chunk of a file in
/// the uploads of one of its sessions, the files its page shows (GET /sessions/:key/files), maybe packed with its
/// archived workspace.
export async function fileForPeer(hub: Hub, request: Json): Promise<Json> {
  const chat = typeof request?.chat === "string" ? request.chat : "";
  const given = typeof request?.path === "string" ? request.path : "";
  const offset = typeof request?.offset === "number" && Number.isSafeInteger(request.offset) && request.offset >= 0 ? request.offset : 0;
  if (chat.trim() === "" || given === "") throw new Error("chat and path are required");
  const what = named(hub, chat);
  const sessions = what.type === "session" ? [what.key] : hub.store.threadSessions(what.thread.id).map((m) => m.session);
  const path = clean(given);
  const base = basename(path);
  const row = sessions.map((k) => hub.store.getSession(k)).find((s) => s !== null && samePath(clean(join(s.workspace, "uploads")), dirname(path)));
  if (!row || base === "" || base === "." || base === "..") throw new Error(`${given} is not a file of that chat`);
  if (existsSync(path)) {
    const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    try {
      const stat = fstatSync(fd);
      if (!stat.isFile()) throw new Error(`${given} is not a file of that chat`);
      if (offset > stat.size) throw new Error("offset past end");
      const buffer = Buffer.alloc(CHUNK);
      const n = readSync(fd, buffer, 0, CHUNK, offset);
      return { data: buffer.subarray(0, n).toString("base64"), size: stat.size, eof: offset + n >= stat.size };
    } finally {
      closeSync(fd);
    }
  }
  // Packed with its archived workspace: read out of the archive once, under its lock (as the pages read it), and kept
  // a while for the chunks after the first, which would each go through the archive again.
  const dir = join(hub.config().dataDir, "remote", "served");
  const kept = join(dir, hash([path]));
  if (offset === 0 || !existsSync(kept)) {
    const room = roomOf(hub.config().dataDir, row.workspace);
    const bytes = room === null ? null : await withLock(room, async () => workspaceFile(room, `uploads/${base}`));
    if (bytes === null) throw new Error(`${given} is gone from that chat`);
    mkdirSync(dir, { recursive: true });
    sweep(hub, dir);
    const part = `${kept}.part-${randomUUID().slice(0, 8)}`;
    writeFileSync(part, bytes);
    renameSync(part, kept);
  }
  const fd = openSync(kept, constants.O_RDONLY);
  try {
    const size = fstatSync(fd).size;
    if (offset > size) throw new Error("offset past end");
    const buffer = Buffer.alloc(CHUNK);
    const n = readSync(fd, buffer, 0, CHUNK, offset);
    return { data: buffer.subarray(0, n).toString("base64"), size, eof: offset + n >= size };
  } finally {
    closeSync(fd);
  }
}

/// A chat's attachment as another station lists it (chat_read's answer there).
export type Listed = { path: string; name: string; size: number };

/// Reads `files` of a chat on station `station` into session `key`'s uploads (uploads/<station>/), each once: the ones
/// up to FETCHED by themselves, the ones in `wanted` whatever their size. Where each landed by its path there, and what
/// was not fetched and why.
export async function fetchAttachments(hub: Hub, key: string, call: Call, station: string, chat: string, files: Listed[], wanted: string[]): Promise<{ here: Map<string, string>; left: string[] }> {
  const row = hub.store.getSession(key);
  if (!row) throw new Error("unknown session");
  const dir = join(row.workspace, "uploads", station.slice(0, 12));
  const here = new Map<string, string>();
  const left: string[] = [];
  let budget = FETCHED_IN_ALL;
  const seen = new Set<string>();
  for (const file of files) {
    if (seen.has(file.path)) continue;
    seen.add(file.path);
    const asked = wanted.includes(file.path);
    // Another station's path, Unix's or Windows'.
    const local = join(dir, anyBaseName(file.path));
    if (existsSync(local) && statSync(local).size === file.size) {
      here.set(file.path, local);
      continue;
    }
    if (!asked && (file.size > FETCHED || file.size > budget)) {
      left.push(`${file.path} (${file.size} bytes)`);
      continue;
    }
    try {
      await download(call, station, chat, file.path, local);
      here.set(file.path, local);
      if (!asked) budget -= file.size;
    } catch (error) {
      left.push(`${file.path} (${why(error)})`);
    }
  }
  // Asked for by its path, from messages read before.
  for (const path of wanted) {
    if (seen.has(path)) continue;
    seen.add(path);
    const local = join(dir, anyBaseName(path));
    try {
      if (!existsSync(local)) await download(call, station, chat, path, local);
      here.set(path, local);
    } catch (error) {
      left.push(`${path} (${why(error)})`);
    }
  }
  return { here, left };
}

/// Why a file did not come: a station from before files are read takes the request for a task.
const why = (error: unknown) => (error instanceof Refused && fromBefore((error as Error).message) ? "that station is not updated yet to give files" : (error as Error).message);

/// One file of a chat there into `local`, which appears only once all of it came.
async function download(call: Call, station: string, chat: string, path: string, local: string): Promise<void> {
  mkdirSync(dirname(local), { recursive: true });
  const part = `${local}.part-${randomUUID().slice(0, 8)}`;
  const fd = openSync(part, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o644);
  try {
    let offset = 0;
    for (;;) {
      const got = await call(station, { method: FILE, chat, path, offset });
      const data = Buffer.from(typeof got?.data === "string" ? got.data : "", "base64");
      for (let at = 0; at < data.length; ) at += writeSync(fd, data, at, data.length - at, offset + at);
      offset += data.length;
      if (got?.eof === true) break;
      if (data.length === 0) throw new Error("the file stopped coming");
    }
    closeSync(fd);
    renameSync(part, local);
  } catch (error) {
    try {
      closeSync(fd);
    } catch {}
    rmSync(part, { force: true });
    throw error;
  }
}

// ── files sent along with a message to another station ──────────────────────────────────────────────────────────

/// Files a message takes along, checked as chat_post checks them: absolute or in session `key`'s workspace.
export function sendable(hub: Hub, key: string, given: string[]): { path: string; name: string; size: number }[] {
  const row = hub.store.getSession(key);
  if (!row) throw new Error("unknown session");
  if (given.length > MAX_FILES) throw new Error(`at most ${MAX_FILES} files per message`);
  return given.map((g) => {
    const path = isAbsolute(g) ? g : join(row.workspace, g);
    let meta;
    try {
      meta = statSync(path);
    } catch {
      throw new Error(`no such file: ${g}`);
    }
    if (!meta.isFile()) throw new Error(`not a file: ${g}`);
    if (meta.size > MAX_SENT) throw new Error(`too large (over 50 MB): ${g}`);
    return { path, name: basename(path), size: meta.size };
  });
}

/// Sends `files` ahead of a message from session `key` to session `to` on station `station`: what the message names
/// them by.
export async function sendAlong(call: Call, station: string, key: string, to: string, files: { path: string; name: string }[]): Promise<{ id: string; name: string }[]> {
  const sent: { id: string; name: string }[] = [];
  for (const file of files) {
    const id = randomUUID();
    const fd = openSync(file.path, constants.O_RDONLY);
    try {
      const size = fstatSync(fd).size;
      const buffer = Buffer.alloc(CHUNK);
      for (let offset = 0; ; ) {
        const n = readSync(fd, buffer, 0, CHUNK, offset);
        const final = n === 0 || offset + n >= size;
        await call(station, { method: PUT, session: key, to, id, name: file.name, offset, data: buffer.subarray(0, n).toString("base64"), final });
        offset += n;
        if (final) break;
      }
    } finally {
      closeSync(fd);
    }
    sent.push({ id, name: file.name });
  }
  return sent;
}

/// Where files sent along wait for their message.
const stagedDir = (hub: Hub) => join(hub.config().dataDir, "remote", "staged");
const staged = (hub: Hub, peer: string, from: string, id: string) => join(stagedDir(hub), hash([peer, from, id]));

/// A chunk of a file another station's session sends along with a message to a session here (`sendAlong` there).
export function putForPeer(hub: Hub, peer: string, request: Json): Json {
  const from = typeof request?.session === "string" ? request.session : "";
  const to = typeof request?.to === "string" ? request.to : "";
  const id = typeof request?.id === "string" ? request.id : "";
  const offset = typeof request?.offset === "number" && Number.isSafeInteger(request.offset) && request.offset >= 0 ? request.offset : null;
  if (from === "" || id === "" || id.length > 64 || offset === null) throw new Error("a file needs session, id and offset");
  if (hub.store.getSession(to) === null) throw new Error(`no session ${to} on this station (it may have been deleted)`);
  const data = Buffer.from(typeof request?.data === "string" ? request.data : "", "base64");
  if (data.length > CHUNK || offset + data.length > MAX_SENT) throw new Error("too large (over 50 MB)");
  const dir = stagedDir(hub);
  mkdirSync(dir, { recursive: true });
  if (offset === 0) sweep(hub, dir);
  const path = staged(hub, peer, from, id);
  const fd = openSync(`${path}.part`, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW, 0o644);
  try {
    if (offset > fstatSync(fd).size) throw new Error("file offset leaves a gap");
    for (let at = 0; at < data.length; ) at += writeSync(fd, data, at, data.length - at, offset + at);
  } finally {
    closeSync(fd);
  }
  if (request?.final === true) renameSync(`${path}.part`, path);
  return { bytes: data.length };
}

/// Files sent along that no message claimed in a day; archived attachments read out a day ago.
function sweep(hub: Hub, dir: string) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    try {
      if (hub.now() - statSync(path).mtimeMs > STAGED_MS) rmSync(path, { force: true });
    } catch {}
  }
}

/// The files a message from another station's session `from` names (`sendAlong` there), moved into session `to`'s
/// uploads.
export function claim(hub: Hub, peer: string, from: string, to: string, given: Json): Attachment[] {
  if (given === undefined || given === null) return [];
  if (!Array.isArray(given) || given.length > MAX_FILES) throw new Error(`files: at most ${MAX_FILES}, each {id, name}`);
  const row = hub.store.getSession(to);
  if (!row) throw new Error(`no session ${to} on this station (it may have been deleted)`);
  const found = given.map((f: Json) => {
    const id = typeof f?.id === "string" ? f.id : "";
    const name = typeof f?.name === "string" && f.name.trim() !== "" ? f.name : "file";
    const path = staged(hub, peer, from, id);
    if (id === "" || !existsSync(path)) throw new Error(`file ${name} did not all arrive: send it again`);
    return { path, name };
  });
  const dir = join(row.workspace, "uploads");
  mkdirSync(dir, { recursive: true });
  return found.map(({ path, name }) => {
    const into = join(dir, uploadName(hub, name));
    // Copied, not moved: a workspace may be on another disk than the station's data.
    copyFileSync(path, into);
    rmSync(path, { force: true });
    return attachment(name, into, statSync(into).size);
  });
}
