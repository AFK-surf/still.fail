// The places that keep a station's copies (replica/AGENTS.md), and how a copy is brought level with one: the other
// stations of its workspace, each keeping what it is sent under <data>/replicas/, without reading inside it:
//
//   <root>/<workspace>/<origin>/files/<sha256>           the attached files, shared by its generations
//   <root>/<workspace>/<origin>/<gen>/log/<batch>         a generation's batches
//   <root>/<workspace>/<origin>/<gen>/head.json           written after its batches and files, before anything goes
//
// A place keeps every generation it was given: what goes is only a generation's batches its head no longer names
// (folded into another) and files no head it holds names any more (their chat deleted).
import { open } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { dirname, join } from "node:path";
import { type Fs, direct } from "../drive/fs.ts";
import { BATCH, GEN, HASH, STATION, WORKSPACE, type Head, asHead, genMade } from "./format.ts";

/// What a place holds of one station's copies in a workspace: each generation (its head, its batches) and the files.
export type Holding = { gen: string; head: Head | null; batches: string[] };
export type Held = { gens: Holding[]; files: string[] };
export const nothingHeld = (): Held => ({ gens: [], files: [] });

export interface Place {
  held(ws: string, origin: string): Promise<Held>;
  /// A batch or the head of a generation.
  put(ws: string, origin: string, gen: string, kind: "batch" | "head", name: string, bytes: Buffer): Promise<void>;
  /// A file, by its hash, read from `source` (a path on this station) or given whole.
  putFile(ws: string, origin: string, hash: string, source: string | Buffer): Promise<void>;
  drop(ws: string, origin: string, gen: string, batches: string[], files: string[]): Promise<void>;
}

function check(ws: string, origin: string, gen?: string): void {
  if (!WORKSPACE.test(ws) || !STATION.test(origin) || (gen !== undefined && !GEN.test(gen))) throw new Error("not a copy's name");
}

/// What a file is written in at a time.
const PIECE = 1 << 20;

/// The bytes of a file of this station's, a piece at a time.
async function* fileOf(path: string): AsyncIterable<Buffer> {
  const f = await open(path, "r");
  try {
    for (;;) {
      const piece = Buffer.allocUnsafe(PIECE);
      const { bytesRead } = await f.read(piece, 0, PIECE, null);
      if (bytesRead === 0) return;
      yield piece.subarray(0, bytesRead);
    }
  } finally {
    await f.close();
  }
}

async function* oneOf(bytes: Buffer): AsyncIterable<Buffer> {
  yield bytes;
}

/// Where a station keeps what other stations send it (`<data>/replicas`), on its own disk.
export class FolderPlace implements Place {
  readonly root: string;
  readonly fs: Fs = direct;
  constructor(root: string) {
    this.root = root;
  }

  dir(ws: string, origin: string): string {
    return join(this.root, ws, origin);
  }

  #exists(path: string): Promise<boolean> {
    return this.fs.stat(path).then(() => true, () => false);
  }

  #list(dir: string): Promise<string[]> {
    return this.fs.names(dir).catch(() => [] as string[]);
  }

  /// Written beside and renamed into place, synced: whole or not at all.
  async #whole(path: string, bytes: AsyncIterable<Buffer>): Promise<void> {
    await this.fs.mkdir(dirname(path), true);
    const tmp = `${path}.${randomBytes(4).toString("hex")}.tmp`;
    let at = 0;
    try {
      for await (const piece of bytes) {
        await this.fs.write(tmp, { create: at === 0, offset: at, data: piece });
        at += piece.length;
      }
      if (at === 0) await this.fs.write(tmp, { create: true, offset: 0, data: Buffer.alloc(0) });
      await this.fs.write(tmp, { create: false, offset: at, data: Buffer.alloc(0), truncate: at, sync: true });
    } catch (e) {
      await this.fs.unlink(tmp).catch(() => {});
      throw e;
    }
    await this.fs.rename(tmp, path);
  }

  async #head(path: string): Promise<Head | null> {
    try {
      return asHead(JSON.parse((await this.fs.readAll(path)).toString("utf8")));
    } catch {
      return null;
    }
  }

  async held(ws: string, origin: string): Promise<Held> {
    check(ws, origin);
    const dir = this.dir(ws, origin);
    const gens: Holding[] = [];
    for (const gen of await this.#list(dir)) {
      if (!GEN.test(gen)) continue;
      gens.push({ gen, head: await this.#head(join(dir, gen, "head.json")), batches: (await this.#list(join(dir, gen, "log"))).filter((b) => BATCH.test(b)).sort() });
    }
    gens.sort((a, b) => genMade(a.gen) - genMade(b.gen) || (a.gen < b.gen ? -1 : 1));
    return { gens, files: (await this.#list(join(dir, "files"))).filter((f) => HASH.test(f)) };
  }

  async put(ws: string, origin: string, gen: string, kind: "batch" | "head", name: string, bytes: Buffer): Promise<void> {
    check(ws, origin, gen);
    const dir = join(this.dir(ws, origin), gen);
    if (kind === "batch") {
      if (!BATCH.test(name)) throw new Error("not a batch's name");
      // (a batch is never written over: what it holds is what its name says)
      if (await this.#exists(join(dir, "log", name))) return;
      await this.#whole(join(dir, "log", name), oneOf(bytes));
    } else {
      const head = asHead(JSON.parse(bytes.toString("utf8")));
      if (head === null || head.gen !== gen || head.origin !== origin || head.workspace !== ws) throw new Error("not a head of this copy");
      // A head never goes back: one older than what is held (another station's sending what it holds) is not taken.
      const was = await this.#head(join(dir, "head.json"));
      if (was !== null && was.to > head.to) return;
      for (const b of head.batches) if (!(await this.#exists(join(dir, "log", b)))) throw new Error(`batch ${b} is not here yet`);
      await this.#whole(join(dir, "head.json"), oneOf(bytes));
    }
  }

  async putFile(ws: string, origin: string, hash: string, source: string | Buffer): Promise<void> {
    await this.putFileFrom(ws, origin, hash, Buffer.isBuffer(source) ? oneOf(source) : fileOf(source));
  }

  /// Takes a file sent as it comes.
  async putFileFrom(ws: string, origin: string, hash: string, bytes: AsyncIterable<Buffer>): Promise<void> {
    check(ws, origin);
    if (!HASH.test(hash)) throw new Error("not a file's hash");
    const path = join(this.dir(ws, origin), "files", hash);
    if (await this.#exists(path)) {
      for await (const _ of bytes) void _;
      return;
    }
    await this.#whole(path, bytes);
  }

  async drop(ws: string, origin: string, gen: string, batches: string[], files: string[]): Promise<void> {
    check(ws, origin, gen);
    const dir = this.dir(ws, origin);
    const head = await this.#head(join(dir, gen, "head.json"));
    for (const b of batches) if (BATCH.test(b) && !(head?.batches ?? []).includes(b)) await this.fs.unlink(join(dir, gen, "log", b)).catch(() => {});
    if (files.length === 0) return;
    // (a file stays while any generation held names it)
    const named = new Set<string>();
    for (const g of (await this.held(ws, origin)).gens) for (const h of Object.keys(g.head?.files ?? {})) named.add(h);
    for (const f of files) if (HASH.test(f) && !named.has(f)) await this.fs.unlink(join(dir, "files", f)).catch(() => {});
  }

  /// Where a batch, a head or a file held here is, by its name; null where it is not.
  async pathOf(ws: string, origin: string, gen: string | null, name: string): Promise<string | null> {
    check(ws, origin, gen ?? undefined);
    const path = gen === null ? (HASH.test(name) ? join(this.dir(ws, origin), "files", name) : null)
      : name === "head.json" ? join(this.dir(ws, origin), gen, "head.json")
      : BATCH.test(name) ? join(this.dir(ws, origin), gen, "log", name) : null;
    return path !== null && (await this.#exists(path)) ? path : null;
  }

  /// A batch, a head or a file held here, whole; null where it is not.
  async read(ws: string, origin: string, gen: string | null, name: string): Promise<Buffer | null> {
    const path = await this.pathOf(ws, origin, gen, name);
    return path === null ? null : this.fs.readAll(path);
  }

  /// A batch, a head or a file held here, a piece at a time.
  async *stream(ws: string, origin: string, gen: string | null, name: string): AsyncIterable<Buffer> {
    const path = await this.pathOf(ws, origin, gen, name);
    if (path === null) throw new Error(`${name} is not there`);
    for (let at = 0; ; ) {
      const { bytes, size } = await this.fs.read(path, at, PIECE);
      if (bytes.length > 0) yield bytes;
      at += bytes.length;
      if (bytes.length === 0 || at >= size) return;
    }
  }

  /// Every station whose copies are held here in `ws`, with each generation's head.
  async origins(ws: string): Promise<{ origin: string; heads: Head[] }[]> {
    if (!WORKSPACE.test(ws)) return [];
    const out: { origin: string; heads: Head[] }[] = [];
    for (const origin of await this.#list(join(this.root, ws))) {
      if (!STATION.test(origin)) continue;
      const heads = (await this.held(ws, origin)).gens.flatMap((g) => (g.head === null ? [] : [g.head]));
      if (heads.length > 0) out.push({ origin, heads });
    }
    return out;
  }

  /// All it holds of a workspace (a station that left it), or of one station's copies there, let go.
  async remove(ws: string, origin?: string): Promise<void> {
    await this.fs.remove(origin === undefined ? join(this.root, ws) : this.dir(ws, origin)).catch(() => {});
  }
}

/// The generation of this station's own copy being brought to a place: its head, its batches' bytes, where its files
/// are now.
export type Own = { head: Head; batch(name: string): Promise<Buffer>; sources(hashes: string[]): Promise<Map<string, string>> };

/// What a place holds of this station's generation, as this station last left it there (it alone writes that
/// generation there): the batches, the files, the files the place's other generations name, how far its head went. Kept
/// between levellings, so that one after a batch sends that batch and the head alone; the place is asked what it holds
/// only as this station starts, as the place comes back, after a failure and on a handover.
export type Known = { gen: string; batches: Set<string>; files: Set<string>; others: Set<string>; to: number; made: number };

/// What bringing a place level found: `behind` where the place holds what this station's own copy does not (this
/// station's data was rolled back: a new generation is begun, and the place keeps both), else how far the place goes
/// now, the files that could not be sent (not on this station any more), and what it holds now.
export type Levelled = { behind: true } | { behind: false; to: number; missing: number; known: Known };

/// Whether what `place` holds of a generation was written by runs this station's own head does not account for.
export function behind(own: Head, held: Held): boolean {
  for (const g of held.gens) {
    const h = g.head;
    if (h === null || h.origin !== own.origin) continue;
    if (g.gen !== own.gen) {
      // (a generation begun after this station's own: written by this station before it was rolled back)
      if (genMade(g.gen) > genMade(own.gen)) return true;
      continue;
    }
    const last = h.runs[h.runs.length - 1];
    if (last === undefined) continue;
    const i = own.runs.findIndex((r) => r.run === last.run);
    if (i < 0) {
      // (a run this station does not know: one rolled back, unless it is one so far back that its head let it go)
      if (h.to > 0 && !(own.runs.length > 0 && h.to < own.runs[0]!.from)) return true;
      continue;
    }
    const end = i + 1 < own.runs.length ? own.runs[i + 1]!.from - 1 : own.to;
    if (h.to > end) return true;
  }
  return false;
}

/// Brings `place` level with this station's own copy of `ws`: its batches and files first, its head, then what is not
/// named any more goes. `known`: what the place held after it was levelled last (null: asked of it now).
export async function level(place: Place, ws: string, own: Own, known: Known | null = null): Promise<Levelled> {
  const origin = own.head.origin;
  let k = known;
  if (k === null || k.gen !== own.head.gen) {
    const held = await place.held(ws, origin);
    if (behind(own.head, held)) return { behind: true };
    const holding = held.gens.find((g) => g.gen === own.head.gen);
    const others = new Set<string>();
    for (const g of held.gens) if (g.gen !== own.head.gen) for (const h of Object.keys(g.head?.files ?? {})) others.add(h);
    k = { gen: own.head.gen, batches: new Set(holding?.batches ?? []), files: new Set(held.files), others, to: holding?.head?.to ?? -1, made: holding?.head?.made ?? -1 };
  }
  for (const b of own.head.batches) {
    if (k.batches.has(b)) continue;
    await place.put(ws, origin, own.head.gen, "batch", b, await own.batch(b));
    k.batches.add(b);
  }
  const lacking = Object.keys(own.head.files).filter((h) => !k.files.has(h));
  const sources = lacking.length === 0 ? new Map<string, string>() : await own.sources(lacking);
  let missing = 0;
  for (const hash of lacking) {
    const source = sources.get(hash);
    if (source === undefined) {
      missing++;
      continue;
    }
    await place.putFile(ws, origin, hash, source);
    k.files.add(hash);
  }
  if (k.to !== own.head.to || k.made !== own.head.made) {
    await place.put(ws, origin, own.head.gen, "head", "head.json", Buffer.from(JSON.stringify(own.head, null, 1)));
    k.to = own.head.to;
    k.made = own.head.made;
  }
  const named = new Set(Object.keys(own.head.files));
  const oldBatches = [...k.batches].filter((b) => !own.head.batches.includes(b));
  const oldFiles = [...k.files].filter((f) => !named.has(f) && !k.others.has(f));
  if (oldBatches.length > 0 || oldFiles.length > 0) {
    await place.drop(ws, origin, own.head.gen, oldBatches, oldFiles);
    for (const b of oldBatches) k.batches.delete(b);
    for (const f of oldFiles) k.files.delete(f);
  }
  return { behind: false, to: own.head.to, missing, known: k };
}

/// Brings `to` level with what `from` holds of another station's copies (a station that holds them and is not one of
/// those that should, handing them over): every generation, nothing dropped. Whether `to` holds all of it now.
export async function handOver(from: FolderPlace, to: Place, ws: string, origin: string): Promise<boolean> {
  const mine = await from.held(ws, origin);
  const theirs = await to.held(ws, origin);
  const files = new Set(theirs.files);
  for (const hash of mine.files) {
    if (files.has(hash)) continue;
    const path = await from.pathOf(ws, origin, null, hash);
    if (path !== null) await to.putFile(ws, origin, hash, path);
  }
  for (const g of mine.gens) {
    if (g.head === null) continue;
    const t = theirs.gens.find((x) => x.gen === g.gen);
    if ((t?.head?.to ?? -1) >= g.head.to) continue;
    const has = new Set(t?.batches ?? []);
    for (const b of g.head.batches) {
      if (has.has(b)) continue;
      const bytes = await from.read(ws, origin, g.gen, b);
      if (bytes !== null) await to.put(ws, origin, g.gen, "batch", b, bytes);
    }
    await to.put(ws, origin, g.gen, "head", "head.json", Buffer.from(JSON.stringify(g.head, null, 1)));
  }
  return holdsAll(mine, await to.held(ws, origin));
}

/// Whether `theirs` holds as much as `mine`: each generation as far, and every file.
export function holdsAll(mine: Held, theirs: Held): boolean {
  const files = new Set(theirs.files);
  if (mine.files.some((f) => !files.has(f))) return false;
  return mine.gens.every((g) => g.head === null || (theirs.gens.find((t) => t.gen === g.gen)?.head?.to ?? -1) >= g.head.to);
}
