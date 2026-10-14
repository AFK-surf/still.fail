// Reading a published chat from its station (docs/public-share.md, station/src/publish/guest.ts): over ALPN
// `stillfail/guest/1`, a bidirectional stream a request. The request is a JSON line, `{get, key}` for the snapshot or
// `{get, key, file}` for one of its attachments; the answer a JSON line, `{ok: true, size, type}` and then exactly
// `size` bytes, or `{error, code: "gone" | "busy"}`. The relays carrying it are everyone's (the cloud's limits.ts), so
// a visit reads the snapshot and what shows at once, its images, and goes (iroh.ts closes it); any other file is read
// when asked for, on a visit of its own. Over any stream that reads and writes: the tests' are in memory.
import { isImage, placeFiles } from "../../../client/core-ts/src/placed.ts";
import type { ShareLink } from "./link.ts";

export type GuestStream = { read(): Promise<Uint8Array | null>; write(bytes: Uint8Array): Promise<void>; finish(): Promise<void> };
export type GuestConnection = { openBi(): Promise<GuestStream> };

/** An attachment of the snapshot, by its number in it (`k`: f0, f1…). */
export type SharedFile = { k: string; name: string; size: number; type: string; width?: number; height?: number; thumbhash?: string };
export type SharedEntry = { n: number; at: number; authorKind: string; author: string; text: string; files: SharedFile[] };
/** snapshot.json (station/src/publish/snapshot.ts). */
export type Snapshot = { v: number; title: string; station: string; at: number; by: string; entries: SharedEntry[]; redacted: number };
/** What a request was answered: the bytes, and what they are. */
export type Got = { type: string; bytes: Uint8Array };

/** The snapshot's format this page reads. */
export const SNAPSHOT_VERSION = 1;
/** The most a station hands out (station/src/publish/index.ts): a snapshot, an attachment. */
export const MOST_SNAPSHOT = 20 * 1024 * 1024;
export const MOST_FILE = 10 * 1024 * 1024;
/** Streams read at once on one connection: as many as the station answers at once (its LIMITS.streams). */
export const STREAMS = 4;
/** An answer's head is a short line: longer, it is not one. */
const MOST_HEAD = 16 * 1024;

/** Why reading failed: the link is gone (or its key wrong: the station says the same), the station is busy, or what it
 * said is not what this page reads (`broken`). */
export class GuestError extends Error {
  readonly kind: "gone" | "busy" | "broken";
  constructor(kind: "gone" | "busy" | "broken", message: string) {
    super(message);
    this.kind = kind;
  }
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function joined(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

/** One request on a stream of its own: its answer, whole. `most`: the most bytes taken for it. */
export async function ask(conn: GuestConnection, request: { get: string; key: string; file?: string }, most: number): Promise<Got> {
  const stream = await conn.openBi();
  await stream.write(encoder.encode(`${JSON.stringify(request)}\n`));
  await stream.finish();
  let carry: Uint8Array = new Uint8Array(0);
  let end = -1;
  while ((end = carry.indexOf(10)) < 0) {
    if (carry.length > MOST_HEAD) throw new GuestError("broken", "the answer's head is too long");
    const more = await stream.read();
    if (more === null) throw new GuestError("broken", "the station said nothing");
    carry = joined(carry, more);
  }
  let head: { ok?: unknown; size?: unknown; type?: unknown; code?: unknown; error?: unknown };
  try {
    head = JSON.parse(decoder.decode(carry.subarray(0, end)));
  } catch {
    throw new GuestError("broken", "the answer's head is not JSON");
  }
  if (head === null || typeof head !== "object") throw new GuestError("broken", "the answer's head is not an object");
  if (head.ok !== true) {
    const said = typeof head.error === "string" ? head.error : "refused";
    throw new GuestError(head.code === "gone" || head.code === "busy" ? head.code : "broken", said);
  }
  const size = head.size;
  if (typeof size !== "number" || !Number.isSafeInteger(size) || size < 0) throw new GuestError("broken", "the answer has no size");
  if (size > most) throw new GuestError("broken", `the answer is ${size} bytes, more than ${most}`);
  // Exactly `size` bytes: what comes after them is not this answer's, and the stream is not waited on past them.
  const bytes = new Uint8Array(size);
  const rest = carry.subarray(end + 1, end + 1 + size);
  bytes.set(rest);
  let got = rest.length;
  while (got < size) {
    const more = await stream.read();
    if (more === null) throw new GuestError("broken", `the answer ended after ${got} of its ${size} bytes`);
    const part = more.subarray(0, size - got);
    bytes.set(part, got);
    got += part.length;
  }
  return { type: typeof head.type === "string" ? head.type : "application/octet-stream", bytes };
}

const text = (v: unknown, or = "") => (typeof v === "string" ? v : or);
const count = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);

function fileOf(f: unknown): SharedFile[] {
  if (f === null || typeof f !== "object") return [];
  const o = f as Record<string, unknown>;
  if (typeof o.k !== "string" || typeof o.name !== "string") return [];
  const file: SharedFile = { k: o.k, name: o.name, size: count(o.size), type: text(o.type, "application/octet-stream") };
  if (typeof o.width === "number" && typeof o.height === "number") Object.assign(file, { width: o.width, height: o.height });
  if (typeof o.thumbhash === "string") file.thumbhash = o.thumbhash;
  return [file];
}

/** snapshot.json read: what it lacks is taken as nothing (a station newer than the page may add fields), but one of a
 * format the page does not know is `broken`. */
export function parseSnapshot(bytes: Uint8Array): Snapshot {
  let raw: unknown;
  try {
    raw = JSON.parse(decoder.decode(bytes));
  } catch {
    throw new GuestError("broken", "the snapshot is not JSON");
  }
  if (raw === null || typeof raw !== "object") throw new GuestError("broken", "the snapshot is not an object");
  const o = raw as Record<string, unknown>;
  if (o.v !== SNAPSHOT_VERSION) throw new GuestError("broken", `a snapshot of format ${String(o.v)}`);
  const entries = (Array.isArray(o.entries) ? o.entries : []).flatMap((e): SharedEntry[] => {
    if (e === null || typeof e !== "object") return [];
    const x = e as Record<string, unknown>;
    return [{ n: count(x.n), at: count(x.at), authorKind: text(x.authorKind, "person"), author: text(x.author), text: text(x.text), files: (Array.isArray(x.files) ? x.files : []).flatMap(fileOf) }];
  });
  return { v: SNAPSHOT_VERSION, title: text(o.title), station: text(o.station), at: count(o.at), by: text(o.by), entries, redacted: count(o.redacted) };
}

/** Whether an entry's words are Markdown drawn as the chat draws an agent's (a person's are plain words there). */
export const isAgent = (e: SharedEntry) => e.authorKind !== "person";
/** An attachment shown as an image: by its name, as the chat does (placed.ts). Never opened as a page of its own. */
export const isShownImage = (f: SharedFile) => isImage(f.name);
/** An HTML attachment: drawn as a visualization where an agent's words place it (web/src/Viz.tsx), in a sandbox. */
export const isHtml = (f: SharedFile) => /\.html?$/i.test(f.name);

/** What a page shows of a snapshot at once, and so reads on its first visit: every image, and the HTML its agents'
 * words place. */
export function shownAtOnce(snapshot: Snapshot): SharedFile[] {
  return snapshot.entries.flatMap((e) => {
    const placed = isAgent(e) ? new Set(placeFiles(e.text, e.files).placed.values()) : new Set<SharedFile>();
    return e.files.filter((f) => isShownImage(f) || (isHtml(f) && placed.has(f)));
  });
}

/** Runs `each` over `items`, `at` of them at a time. */
async function inTurn<T>(items: T[], at: number, each: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const one = async () => {
    while (next < items.length) await each(items[next++]!);
  };
  await Promise.all(Array.from({ length: Math.min(at, items.length) }, one));
}

/**
 * A visit: the snapshot (`snapshot` hears it as soon as it is read), then what shows at once, a few at a time (`file`
 * hears each, or null for one that could not be read: the rest go on). Settles once all were read; the snapshot's
 * failure fails it.
 */
export async function readShared(conn: GuestConnection, link: ShareLink, on: { snapshot(s: Snapshot): void; file(k: string, got: Got | null): void }): Promise<Snapshot> {
  const snapshot = parseSnapshot((await ask(conn, { get: link.id, key: link.key }, MOST_SNAPSHOT)).bytes);
  on.snapshot(snapshot);
  await inTurn(shownAtOnce(snapshot), STREAMS, async (f) => {
    on.file(f.k, await ask(conn, { get: link.id, key: link.key, file: f.k }, MOST_FILE).catch(() => null));
  });
  return snapshot;
}
