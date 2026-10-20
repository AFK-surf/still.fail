// Chats published as snapshots anyone with the link reads (docs/public-share.md). A snapshot is written out here once,
// frozen: published/<id>/snapshot.json, and a copy of each attachment ticked in published/<id>/f/<k>. Visitors read it
// over the guest ALPN (guest.ts), never through the members' admin API.
import { randomBytes } from "node:crypto";
import { closeSync, constants, copyFileSync, existsSync, fstatSync, mkdirSync, openSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { clean, samePath } from "../ops/paths.ts";
import type { Published, Store } from "../store/store.ts";
import type { Hub } from "../sessions/hub.ts";
import { roomOf } from "../sessions/footprint.ts";
import { withLock, workspaceFile } from "../sessions/archive.ts";
import { type Draft, snapshotOf } from "./snapshot.ts";

/// Why a snapshot was not written: said to the person publishing.
export class NotPublished extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const random = (bytes: number) => randomBytes(bytes).toString("base64url");

/// Where a snapshot's files are: its directory, its snapshot.json, an attachment of it.
export const snapshotDir = (store: Store, id: string) => join(store.publishedDir, id);
export const snapshotFile = (store: Store, id: string) => join(snapshotDir(store, id), "snapshot.json");
export const attachmentFile = (store: Store, id: string, k: string) => join(snapshotDir(store, id), "f", k);

/// Copies an attachment of a chat into `to`: from the uploads of one of the chat's sessions (the files its page shows),
/// or out of a session's archived workspace. Whether it was there.
async function copyAttachment(hub: Hub, thread: number, given: string, to: string): Promise<boolean> {
  const path = clean(given);
  const base = basename(path);
  const sessions = hub.store.threadSessions(thread).map((m) => m.session);
  const row = sessions.map((k) => hub.store.getSession(k)).find((s) => s !== null && samePath(clean(join(s.workspace, "uploads")), dirname(path)));
  if (!row || base === "" || base === "." || base === "..") return false;
  if (existsSync(path)) {
    // Not through a link: what is copied is the file in uploads itself.
    const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    try {
      if (!fstatSync(fd).isFile()) return false;
    } finally {
      closeSync(fd);
    }
    copyFileSync(path, to);
    return true;
  }
  const room = roomOf(hub.config().dataDir, row.workspace);
  const bytes = room === null ? null : await withLock(room, async () => workspaceFile(room, `uploads/${base}`));
  if (bytes === null) return false;
  writeFileSync(to, bytes);
  return true;
}

/// Writes out a chat's snapshot as `draft` has it, with the attachments `ticked`, and records it. `station`: this
/// station's name; `by`: who publishes it (email and name). Words for refusals come from `say`.
export async function publish(
  hub: Hub,
  store: Store,
  draft: Draft,
  a: { thread: number; ticked: string[]; station: string; by: { email: string; name: string } },
  say: { fileGone: (name: string) => string },
): Promise<Published> {
  const ticked = new Set(a.ticked.filter((k) => draft.files.some((f) => f.k === k)));
  const files = draft.files.filter((f) => ticked.has(f.k));
  const at = store.now();
  const snapshot = Buffer.from(JSON.stringify(snapshotOf(draft, a.station, a.by.name, at, ticked)));
  const size = snapshot.length + files.reduce((sum, f) => sum + f.size, 0);
  const id = random(12);
  const dir = snapshotDir(store, id);
  // Written aside and moved into place whole: a snapshot is there with all its files, or not at all.
  const part = `${dir}.part`;
  mkdirSync(join(part, "f"), { recursive: true });
  try {
    for (const f of files) {
      if (!(await copyAttachment(hub, a.thread, f.path, join(part, "f", f.k)))) throw new NotPublished(410, say.fileGone(f.name));
    }
    writeFileSync(join(part, "snapshot.json"), snapshot);
    renameSync(part, dir);
  } catch (e) {
    rmSync(part, { recursive: true, force: true });
    throw e;
  }
  const published: Published = { id, thread: a.thread, key: random(32), title: draft.title, by: a.by.email, byName: a.by.name, at, upto: draft.upto, size };
  store.addPublished(published);
  return published;
}
