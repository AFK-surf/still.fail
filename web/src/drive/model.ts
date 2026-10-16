// A station's drive as its pages use it (docs/drive.md): a folder and where a file was left are the core's topics; a
// file is read a part at a time (`drive.read`), put up a part at a time (`drive.upload.part`), and the uploads under
// way are kept here, beside the folder they go into, for its list to show while they last. What the core changes
// (a folder made, renamed, removed) is an operation by its name: the core reads the folder again before it answers.
import { useMemo, useSyncExternalStore } from "react";
import { core, topicNow, useTopic, type TopicState } from "../core/react.ts";
import { CoreError } from "../core/client.ts";
import type { DriveEntry, DriveFolder, DriveKind, DrivePlace, DriveRoot } from "../core/shapes.ts";
import { fromBase64, toBase64 } from "../api.ts";
import { t } from "../i18n.ts";

/** A place in a station's drive: one of its roots (by its path on the station) and a path under it ("" the root). */
export interface At { station: string; root: string; path: string }

export const joinPath = (folder: string, name: string) => (folder ? `${folder}/${name}` : name);
export const parentOf = (path: string) => path.split("/").filter(Boolean).slice(0, -1).join("/");
export const nameOf = (path: string) => path.split("/").filter(Boolean).at(-1) ?? "";
/** A root's name as its list shows it (the station names it by its last component). */
export const rootLabel = (roots: readonly DriveRoot[] | undefined, root: string) => roots?.find((r) => r.path === root)?.name ?? (root.split(/[/\\]/).filter(Boolean).at(-1) || root);

/** A folder of the drive, read again each time it is shown (what is held shows meanwhile; a refusal is its error). */
export function useFolder(station: string, root: string | null, path: string): TopicState<DriveFolder> {
  return useTopic<DriveFolder>(root === null ? null : { topic: "drive", station, root, path });
}

/** Where a file was left on this device: undefined while not known yet, null before it was opened. */
export function usePlace(at: At | null): DrivePlace | null | undefined {
  const state = useTopic<DrivePlace | null>(at ? { topic: "drivePlace", station: at.station, root: at.root, path: at.path } : null);
  if (!at) return null;
  return state.loading ? undefined : state.value ?? null;
}

/** Where a file is left now (`at`: a text's offset, a video's time in ms; `of`: of how much). */
export function placeAt(at: At, where: number, of?: number): void {
  core().call("drive.place", { station: at.station, root: at.root, path: at.path, at: Math.max(0, Math.round(where)), ...(of !== undefined && Number.isFinite(of) ? { of: Math.round(of) } : {}) }).catch(() => undefined);
}

/** The folder read again for a person who asked; answers once it is. */
export function refresh(at: { station: string; root: string; path: string }): Promise<unknown> {
  return core().call("drive.refresh", { station: at.station, root: at.root, path: at.path });
}

// ── reading ────────────────────────────────────────────────────────────

/** The most one `drive.read` asks for (the station gives 8 MB at most). */
export const READ_PART = 4 * 1024 * 1024;

export interface Part { type: string; total: number; bytes: Uint8Array<ArrayBuffer> }

/** `length` bytes of a file from `offset` (fewer at its end); `heard`: how many of them have come, as they come. */
export async function readPart(at: At, offset: number, length: number, signal?: AbortSignal, heard?: (loaded: number) => void): Promise<Part> {
  const got = await core().call("drive.read", { station: at.station, root: at.root, path: at.path, offset, length, ...(heard ? { progress: true } : {}) },
    heard && ((p) => heard((p as { loaded: number }).loaded)), signal) as { type: string; total: number; bytes: string };
  return { type: got.type, total: got.total, bytes: fromBase64(got.bytes) };
}

/** How much of a whole file has come. */
export interface Got { loaded: number; total: number }

/**
 * A file whole, a part at a time, each a blob of its own (the browser keeps big ones on its disk): `max`, at most that
 * much of it (its front). `type`: what the blob is said to be (the station says what it thinks by its name otherwise).
 */
export async function readWhole(at: At, size: number, opts: { type?: string; max?: number; onProgress?: (got: Got) => void; signal?: AbortSignal } = {}): Promise<Blob> {
  const parts: Blob[] = [];
  let type = opts.type ?? "";
  let total = size;
  const end = () => Math.min(total, opts.max ?? Infinity);
  // Said at once (nothing yet, out of how much), then as each part comes.
  opts.onProgress?.({ loaded: 0, total: end() });
  for (let offset = 0; offset < end();) {
    const from = offset;
    const got = await readPart(at, offset, Math.min(READ_PART, end() - offset), opts.signal, opts.onProgress && ((n) => opts.onProgress!({ loaded: from + n, total: end() })));
    if (got.bytes.length === 0) break;
    parts.push(new Blob([got.bytes]));
    if (!opts.type) type = got.type;
    total = got.total;
    offset += got.bytes.length;
    opts.onProgress?.({ loaded: offset, total: end() });
  }
  return new Blob(parts, { type });
}

// Files read whole for a viewer, the latest few kept: going back to one just seen (an image stepped past) is at once.
const wholes = new Map<string, Promise<Blob>>();
const KEEP_WHOLES = 24;

/** A file read whole once while it is the same (its size and time), shared by whoever shows it. */
export function readKept(at: At, entry: Pick<DriveEntry, "size" | "mtime">, type: string, onProgress?: (got: Got) => void): Promise<Blob> {
  const key = `${at.station}\n${at.root}\n${at.path}\n${entry.size}\n${entry.mtime}`;
  let kept = wholes.get(key);
  if (!kept) {
    kept = readWhole(at, entry.size, { type, ...(onProgress ? { onProgress } : {}) });
    kept.catch(() => wholes.delete(key));
    wholes.set(key, kept);
    if (wholes.size > KEEP_WHOLES) wholes.delete(wholes.keys().next().value!);
  }
  return kept;
}

/** Saves a file of the drive to this device (the browser's download), read whole first; `onProgress` as it comes. */
export async function download(at: At, entry: Pick<DriveEntry, "size" | "name" | "type">, onProgress?: (got: Got) => void): Promise<void> {
  const blob = await readWhole(at, entry.size, { type: entry.type || "application/octet-stream", ...(onProgress ? { onProgress } : {}) });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = entry.name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 60_000);
}

// ── what opens an entry ────────────────────────────────────────────────

/** How an entry is opened: entered, read in the reader, played, previewed as a chat's file is, or saved. */
export type Opener = "folder" | "read" | "play" | "preview" | "save";

export function openerOf(kind: DriveKind): Opener {
  switch (kind) {
    case "folder": return "folder";
    case "text": case "markdown": return "read";
    case "video": case "audio": return "play";
    case "image": case "pdf": case "code": case "csv": case "html": case "subtitle": return "preview";
    default: return "save";
  }
}

// A folder's names as the viewers read them (@stillfail/ui viewer/names.ts).
export { compareNatural, sideSubtitle } from "@stillfail/ui/viewer/names.ts";

// ── writing ────────────────────────────────────────────────────────────

/** A name not among `taken`: `name (1).ext`, `name (2).ext`… */
export function freeName(name: string, taken: ReadonlySet<string>): string {
  if (!taken.has(name)) return name;
  const dot = name.lastIndexOf(".");
  const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  for (let n = 1; ; n++) {
    const next = `${stem} (${n})${ext}`;
    if (!taken.has(next)) return next;
  }
}

/** The names a folder has now, as the page holds it (and those on their way into it). */
export function namesIn(station: string, root: string, folder: string): Set<string> {
  const held = topicNow<DriveFolder>({ topic: "drive", station, root, path: folder });
  const names = new Set(held?.entries.map((e) => e.name) ?? []);
  for (const u of uploads) if (u.station === station && u.root === root && u.folder === folder) names.add(u.name);
  return names;
}

/** An upload under way, or stopped: `taken` when its name is a file there already (replace it, or keep both). */
export interface Upload {
  key: string;
  station: string;
  root: string;
  folder: string;
  name: string;
  size: number;
  /** How much the station has. */
  sent: number;
  state: "sending" | "taken" | "failed";
  error?: string;
  file: File;
}

/** The bytes of a file in one `drive.upload.part`. */
const UPLOAD_PART = 4 * 1024 * 1024;

let uploads: readonly Upload[] = [];
const heard = new Set<() => void>();
const stopped = new Set<string>();
function put(next: readonly Upload[]): void {
  uploads = next;
  for (const h of heard) h();
}
const change = (key: string, f: (u: Upload) => Upload | null) => put(uploads.flatMap((u) => (u.key === key ? (f(u) ?? []) : [u])));

/** The uploads into a folder, oldest first: the same list while none of them changes. */
export function useUploads(station: string, root: string | null, folder: string): readonly Upload[] {
  const all = useSyncExternalStore((h) => { heard.add(h); return () => { heard.delete(h); }; }, () => uploads, () => uploads);
  return useMemo(() => all.filter((u) => u.station === station && u.root === root && u.folder === folder), [all, station, root, folder]);
}

/** Starts putting files into a folder: each its own row while it goes, gone from them once the folder has it. */
export function upload(station: string, root: string, folder: string, files: Iterable<File>): void {
  for (const file of files) {
    const key = crypto.randomUUID();
    put([...uploads, { key, station, root, folder, name: file.name, size: file.size, sent: 0, state: "sending", file }]);
    void send(key, false);
  }
}

/** The one whose name was taken: over what is there (`replace`), or beside it under a free name. */
export function settle(key: string, replace: boolean): void {
  const u = uploads.find((x) => x.key === key);
  if (!u) return;
  if (!replace) {
    const taken = namesIn(u.station, u.root, u.folder);
    taken.delete(u.name);
    change(key, (x) => ({ ...x, name: freeName(x.name, new Set([...taken, x.name])) }));
  }
  change(key, (x) => ({ ...x, state: "sending", sent: 0 }));
  void send(key, replace);
}

/** Tried again from the start (one that failed). */
export function retry(key: string): void {
  change(key, (x) => ({ ...x, state: "sending", sent: 0 }));
  void send(key, false);
}

/** Given up: its row goes (what the station had of it is cleared there in a day). */
export function cancel(key: string): void {
  stopped.add(key);
  change(key, () => null);
}

async function send(key: string, replace: boolean): Promise<void> {
  const first = uploads.find((x) => x.key === key);
  if (!first) return;
  const { station, root, folder, file } = first;
  // A fresh id each try: a part of an earlier one is not taken for this one's.
  const id = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
  let have = 0;
  try {
    for (;;) {
      if (stopped.has(key)) return;
      const name = uploads.find((x) => x.key === key)?.name ?? first.name;
      const bytes = await toBase64(file.slice(have, have + UPLOAD_PART));
      const told = await core().call("drive.upload.part", { station, root, path: joinPath(folder, name), id, offset: have, total: file.size, replace, bytes }) as { have: number; entry: unknown };
      if (told.entry) {
        // The folder has it now (the core read it again before answering): its row goes.
        change(key, () => null);
        return;
      }
      // The station goes on from what it has (less, after it lost a part); nothing more is a part it could not take.
      if (told.have === have && file.size > 0) throw new Error(t("web-pages.drive.uploadStuck"));
      have = told.have;
      change(key, (x) => ({ ...x, sent: have }));
    }
  } catch (e) {
    if (stopped.has(key)) return;
    // Its name taken there (409 `exists`, said at its first part): replace it or keep both is asked on its row.
    if (e instanceof CoreError && e.status === 409 && have === 0 && !replace) {
      const held = topicNow<DriveFolder>({ topic: "drive", station, root, path: folder });
      const name = uploads.find((x) => x.key === key)?.name ?? first.name;
      // A folder by that name cannot be replaced: kept beside it at once.
      if (held?.entries.some((x) => x.name === name && x.dir)) return settle(key, false);
      change(key, (x) => ({ ...x, state: "taken" }));
      return;
    }
    change(key, (x) => ({ ...x, state: "failed", error: e instanceof Error ? e.message : String(e) }));
  }
}

/** A row's size: "12.3 MB / 40 MB". */
export function sizeOf(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
