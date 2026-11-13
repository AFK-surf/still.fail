// This station's copies as the station keeps them going (replica/AGENTS.md), on its main thread: what the store says
// changed gathered and handed to the export's thread (runner.ts) a moment later, what it wrote brought to the stations
// that keep this one's copies, the copies this station keeps of others handed over where they are not its to keep any
// more, and a lost station's copy brought back into a new one (restore.ts). Nothing here reads stillfail.db; what it does
// on this thread is a few messages per change and the files' bytes passed to the mesh as they are read.
import { mkdir, open, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";
import type { Fibers } from "../ops/fibers.ts";
import type { StoreChange } from "../store/rows.ts";
import { type Places, type Told, nothingTold } from "./export.ts";
import { GEN, type Head, STATION, WORKSPACE, genMade } from "./format.ts";
import { FolderPlace, type Held, type Known, type Place, handOver, holdsAll, level } from "./places.ts";
import { type Ask, COPIES, PeerPlace, keepers, ranked, serve } from "./peers.ts";
import { Refused } from "../mesh/bus.ts";
import { NotEmpty, type Outcome, type Ready, copyDir, outcomeFile, readyFile } from "./restore.ts";
import type { Runner } from "./runner.ts";
import type { WorkPassed } from "./work.ts";

/// What the store says is gathered this long before the export's thread is told (a burst of changes, one pass).
export const GATHER_MS = 1_000;
/// A place that could not be brought level is tried again after this, twice as long each time, up to RETRY_MOST_MS.
export const RETRY_MS = 5_000;
export const RETRY_MOST_MS = 10 * 60_000;
/// How often at most the station's settings are told the copies went further (a pass a second while agents work);
/// what went wrong or came right, at once; a restore's progress, every second.
export const TELL_MS = 30_000;
export const TELL_RESTORE_MS = 1_000;

/// Where the stations this one keeps copies of are kept, and which station this one was (it took a lost one's place).
export const keptDir = (data: string) => join(data, "replicas");
export const formerlyFile = (data: string) => join(data, "replica", "formerly.json");

/// The stations this one took the place of, as `formerly.json` says (written before its store opens, never after: read
/// once as it starts).
export function formerlyOf(data: string): string[] {
  try {
    const list = JSON.parse(readFileSync(formerlyFile(data), "utf8")); // sync: read once, before the station serves
    return Array.isArray(list) ? list.filter((s) => typeof s === "string" && STATION.test(s)) : [];
  } catch {
    return [];
  }
}

export type CopiesDeps = {
  data: string;
  /// This station's id (null before it is enrolled).
  here: () => string | null;
  /// The workspaces it is in, its name in each.
  places: () => Places;
  /// The stations of `ws` (this one too) with their names, as its roster says now; null while the roster is not current.
  roster: (ws: string) => { id: string; name: string }[] | null;
  ask: Ask;
  runner: Runner;
  fibers: Fibers;
  /// What the station's settings show changed.
  changed: () => void;
  /// Asks the station's launcher to start it again (ops/restart.ts); null where there is none to ask.
  restart: () => Promise<(() => Promise<void>) | null>;
  /// The stations whose chats this one is taking (retire.ts): what it keeps of them is not handed over meanwhile.
  taking?: () => Set<string>;
};

/// How a place for this station's copies stands: how far it goes, when it was brought level last, what went wrong.
/// `known`: what it holds, as this station left it (null: to be asked); `head`: the head it was brought level with.
type Keeping = { to: number; at: number | null; error: string | null; reason: Reason | null; missing: number; busy: boolean; again: (() => void) | null; tries: number; asked: boolean; known: Known | null; head: string | null };

/// Why a station is not brought level, as the settings say it: it is not reached, it is from before copies (it answers
/// none of `replica.*`), or something else (its words in the log).
export type Reason = "offline" | "old" | "error";

/// A restore under way, as the station's settings show it; one that failed says why (`reason`; `error` the log's words).
export type Restoring = { origin: string; name: string; workspace: string; gen: string; from: string; done: number; total: number; error: string | null; reason: RestoreReason | null; restart: boolean };

/// Why a restore failed, as the settings say it: the station it came from not reached or from before copies, the copy
/// no longer kept there, this station got a chat of its own first, or something else.
export type RestoreReason = Reason | "gone" | "notEmpty";

/// A copy that the place asked for does not keep (any more).
class Gone extends Error {}

/// A retired station's copy put in beside this one's chats (restore.ts `Ready`).
type Merge = { merge: true; connects: Record<string, string>; ws: string | null };

/// The store's change put into `t`, what the next pass is to read again (a few keys, nothing read); false where it
/// says nothing of what is copied.
export function tell(t: Told, change: StoreChange): boolean {
  switch (change.type) {
    case "session":
    case "conversation":
      t.sessions.push(change.key);
      return true;
    case "sessionRemoved":
      t.removedSessions.push({ key: change.key, ws: change.ws ?? null });
      return true;
    case "thread":
      // (its entries are found by their rowid; only what else of it changed is read by its id)
      if (change.entries.length === 0 || change.closed !== undefined) t.threads.push(change.id);
      return true;
    case "letters":
      return true;
    case "threadRemoved":
      t.removedThreads.push({ id: change.id, ws: change.ws ?? null });
      return true;
    case "read":
      t.marks.push({ table: "reads", key: { viewer: change.viewer, thread: change.thread } });
      return true;
    case "hidden":
      t.marks.push({ table: "hidden_chats", key: { viewer: change.viewer, thread: change.thread } });
      return true;
    case "muted":
      t.marks.push({ table: "muted_chats", key: { viewer: change.viewer, thread: change.thread } });
      return true;
    case "pins":
      if (change.session !== undefined) t.marks.push({ table: "pins", key: { viewer: change.viewer, session: change.session } });
      return true;
    case "dismissed":
      if (change.card !== undefined) t.marks.push({ table: "dismissed", key: { viewer: change.viewer, thread: change.card.thread, n: change.card.n } });
      if (change.kept !== undefined) t.marks.push({ table: "kept_chats", key: { viewer: change.viewer, thread: change.kept.thread } });
      return true;
    case "chatMark":
      if (change.opened !== undefined) t.sessions.push(change.session);
      if (change.thread !== null) t.threads.push(change.thread);
      return true;
    default:
      return false;
  }
}

export class Copies {
  readonly #d: CopiesDeps;
  readonly kept: FolderPlace;
  #told: Told = nothingTold();
  #gathering: (() => void) | null = null;
  #passing: Promise<void> | null = null;
  #again = false;
  #closed = false;
  #passed: WorkPassed | null = null;
  readonly #keeping = new Map<string, Keeping>();
  /// What other stations said they once were, by workspace: the lost station's id, the one that took its place.
  readonly #formerly = new Map<string, Map<string, string>>();
  #handing: Promise<void> | null = null;
  #handAgain: (() => void) | null = null;
  #handTries = 0;
  #restoring: Restoring | null = null;
  /// Why the export is not going (its thread ended, a pass failing), and how many times in a row.
  #exportError: string | null = null;
  #exportTries = 0;
  /// The stations found to be from before copies: they answered `replica.hello` with a refusal.
  readonly #old = new Set<string>();
  #telling: (() => void) | null = null;

  /// What came of the restore this station was started again for (null: none): written before its store opened and
  /// never after, so read once.
  readonly #restored: Outcome | null;
  /// The stations this one took the place of (formerlyOf, read once).
  readonly #was: string[];

  constructor(d: CopiesDeps) {
    this.#d = d;
    this.kept = new FolderPlace(keptDir(d.data));
    let restored: Outcome | null = null;
    try {
      restored = JSON.parse(readFileSync(outcomeFile(d.data), "utf8")) as Outcome; // sync: read once, before the station serves
    } catch {}
    this.#restored = restored;
    this.#was = formerlyOf(d.data);
  }

  /// Begun: the export told where it is, a first pass (the small tables read whole), the other stations told it is up.
  async start(): Promise<void> {
    // (what each place holds asked of it again as this station starts)
    for (const k of this.#keeping.values()) k.known = null;
    await this.placesChanged();
  }

  async close(): Promise<void> {
    this.#closed = true;
    this.#gathering?.();
    this.#telling?.();
    for (const k of this.#keeping.values()) k.again?.();
    this.#handAgain?.();
    await this.#passing?.catch(() => {});
    await this.#handing?.catch(() => {});
  }

  /// The station's settings told the copies changed: within `ms` (0: now).
  #changed(ms: number): void {
    if (ms === 0) {
      this.#telling?.();
      this.#telling = null;
      this.#d.changed();
      return;
    }
    if (this.#telling !== null || this.#closed) return;
    this.#telling = this.#d.fibers.after(ms, () => { // timer: a debounce of a burst (a pass a second while agents work)
      this.#telling = null;
      this.#d.changed();
    });
  }

  // ── what changed ──

  /// The store's change, put with what is to be exported: a few keys, nothing read.
  told(change: StoreChange): void {
    if (tell(this.#told, change)) this.#gather();
  }

  /// A pass a moment from now (what else changes meanwhile goes with it).
  #gather(): void {
    if (this.#gathering !== null || this.#closed) return;
    this.#gathering = this.#d.fibers.after(GATHER_MS, () => { // timer: a debounce of a burst of the store's changes
      this.#gathering = null;
      void this.#pass();
    });
  }

  /// One pass at a time; what is told meanwhile goes in the next.
  async #pass(): Promise<void> {
    if (this.#passing !== null) {
      this.#again = true;
      return;
    }
    const told = this.#told;
    this.#told = nothingTold();
    this.#again = false;
    this.#passing = (async () => {
      try {
        const passed = await this.#d.runner.pass(told);
        this.#passed = passed;
        if (this.#exportError !== null) {
          this.#exportError = null;
          this.#exportTries = 0;
          this.#changed(0);
        } else if (passed.wrote > 0) this.#changed(TELL_MS);
        for (const [ws, head] of Object.entries(passed.heads)) if (head.batches.length > 0) this.#levelAll(ws);
        if (passed.more) this.#again = true;
      } catch (e) {
        log.warn("copies", "an export failed", { error: (e as Error).message });
        // (what was told goes with the next one, a while from now: its thread started again where it ended)
        this.#merge(told);
        if (this.#exportError === null) this.#changed(0);
        this.#exportError = (e as Error).message;
        const wait = Math.min(RETRY_MS * 2 ** this.#exportTries, RETRY_MOST_MS);
        this.#exportTries++;
        if (!this.#closed) this.#d.fibers.after(wait, () => void this.#pass()); // timer: a retry after a failure
      }
    })();
    await this.#passing;
    this.#passing = null;
    if (this.#again && !this.#closed) void this.#pass();
  }

  #merge(told: Told): void {
    const t = this.#told;
    t.sessions.push(...told.sessions);
    t.threads.push(...told.threads);
    t.removedSessions.push(...told.removedSessions);
    t.removedThreads.push(...told.removedThreads);
    t.marks.push(...told.marks);
  }

  /// The export done now, and the places levelled: what a test waits for (it does not wait on a timer).
  async settle(): Promise<void> {
    this.#gathering?.();
    this.#gathering = null;
    do {
      await this.#pass();
      while (this.#passing !== null) await this.#passing;
    } while (this.#again);
    for (;;) {
      const busy = [...this.#keeping.values()].some((k) => k.busy);
      if (!busy && this.#handing === null) break;
      await Promise.all([...this.#levelling.values(), this.#handing]);
    }
  }

  // ── the workspaces and their stations ──

  /// The workspaces or their stations changed (or the station started): the export told, what is no longer this
  /// station's to keep let go, the stations told this one is up, the places brought level.
  async placesChanged(): Promise<void> {
    const places = this.#d.places();
    await this.#d.runner.places(places);
    const ins = new Set(places.workspaces.map((w) => w.workspace));
    // (a workspace this station is not in any more: nothing of it kept here)
    for (const root of [keptDir(this.#d.data), join(this.#d.data, "replica", "own")]) {
      for (const ws of await readdir(root).catch(() => [] as string[])) {
        if (WORKSPACE.test(ws) && !ins.has(ws)) await rm(join(root, ws), { recursive: true, force: true });
      }
    }
    for (const k of [...this.#keeping.keys()]) if (!ins.has(k.split("\n")[0]!)) this.#keeping.delete(k);
    for (const ws of ins) {
      for (const k of [...this.#keeping.keys()]) {
        const [w, station] = k.split("\n");
        if (w === ws && !this.#targets(ws).includes(station!)) this.#keeping.delete(k);
      }
    }
    void this.#pass().then(() => {
      if (this.#passed?.empty === true) for (const ws of ins) void this.look(ws).catch(() => {});
    });
    this.#hello();
    this.#handOverSoon();
  }

  #keepersOf(ws: string): string[] {
    const here = this.#d.here();
    const roster = this.#d.roster(ws);
    return here === null || roster === null ? [] : keepers(ws, here, roster.map((s) => s.id));
  }

  /// Each other station of each workspace told this one is up (and what it once was): one that keeps this station's
  /// copies is brought level as it answers, one whose copies this one keeps knows to bring them.
  #hello(): void {
    const here = this.#d.here();
    if (here === null) return;
    const formerly = this.#was;
    for (const { workspace: ws } of this.#d.places().workspaces) {
      for (const s of this.#d.roster(ws) ?? []) {
        if (s.id === here) continue;
        void this.#d.ask(s.id, { method: "replica.hello", workspace: ws, formerly }).then(
          (answer) => {
            this.#old.delete(s.id);
            this.#heardFormerly(ws, s.id, Array.isArray(answer?.formerly) ? answer.formerly : []);
          },
          (e) => {
            // (one that answers with a refusal is up but knows no `replica.*`: from before copies)
            if (e instanceof Refused) this.#old.add(s.id);
          },
        );
      }
    }
  }

  #heardFormerly(ws: string, station: string, formerly: string[]): void {
    let m = this.#formerly.get(ws);
    if (m === undefined) this.#formerly.set(ws, (m = new Map()));
    for (const f of formerly) if (STATION.test(f)) m.set(f, station);
  }

  /// The station that took the place of `station` (a lost one) in `ws`, as it said; `station` itself where none did.
  now(ws: string | null, station: string): string {
    if (this.#was.includes(station)) return this.#d.here() ?? station;
    for (const [w, m] of this.#formerly) if (ws === null || w === ws) {
      const s = m.get(station);
      if (s !== undefined) return s;
    }
    return station;
  }

  /// Another station is up (`replica.hello`): it is brought what it keeps of this one; what this station keeps and
  /// should hand over may go to it now. What this station once was, said back.
  heard(peer: string, ws: string, formerly: string[]): string[] {
    this.#heardFormerly(ws, peer, formerly);
    this.#old.delete(peer);
    // (it is up: what it holds asked of it again, and brought level where it is one of those that keep this one's)
    const k = this.#keeping.get(`${ws}\n${peer}`);
    if (k !== undefined) k.known = null;
    if (this.#targets(ws).includes(peer) || this.#keepersOf(ws).includes(peer)) this.#level(ws, peer, { now: true, fresh: true });
    this.#handOverSoon();
    return this.#was;
  }

  inWorkspace(peer: string, ws: string): boolean {
    return this.#d.places().workspaces.some((w) => w.workspace === ws) && (this.#d.roster(ws) ?? []).some((s) => s.id === peer);
  }

  /// What this station answers of the copies it keeps (`replica.*`).
  answers() {
    return serve({ place: this.kept, inWorkspace: (peer, ws) => this.inWorkspace(peer, ws), hello: (peer, ws, formerly) => this.heard(peer, ws, formerly) });
  }

  // ── this station's copies, at the stations that keep them ──

  readonly #levelling = new Map<string, Promise<void>>();
  /// A new generation begun for a workspace, from the one found behind: the places that find it so wait on the one.
  readonly #begun = new Map<string, { from: string; done: Promise<void> }>();

  #levelAll(ws: string): void {
    for (const peer of this.#targets(ws)) this.#level(ws, peer, {});
  }

  /// The stations that should hold this station's copies in `ws` now: those it falls to (`keepers`) and, while one of
  /// them is not reached, the next in the same order (`ranked`), so that COPIES reached ones hold it. One that holds it
  /// only meanwhile hands it to the one it is for once that one is back, and lets it go (`#handOver`).
  #targets(ws: string): string[] {
    const here = this.#d.here();
    const roster = this.#d.roster(ws);
    if (here === null || roster === null) return [];
    const out: string[] = [];
    let reached = 0;
    for (const s of ranked(ws, here, roster.map((r) => r.id))) {
      out.push(s);
      if (this.#keeping.get(`${ws}\n${s}`)?.error == null) reached++;
      if (reached >= COPIES) break;
    }
    return out;
  }

  /// Why `error` kept a place from being brought level, as the settings say it.
  #reason(peer: string, error: unknown): Reason {
    if (this.#old.has(peer)) return "old";
    if (error instanceof Refused) return /no such replica request|is required|unknown/.test(error.message) ? "old" : "error";
    return "offline";
  }

  /// `now`: not waiting for a retry already set; `fresh`: what the place holds asked of it, not taken as known.
  #level(ws: string, peer: string, o: { now?: boolean; fresh?: boolean }): void {
    const now = o.now === true;
    const key = `${ws}\n${peer}`;
    let k = this.#keeping.get(key);
    if (k === undefined) this.#keeping.set(key, (k = { to: 0, at: null, error: null, reason: null, missing: 0, busy: false, again: null, tries: 0, asked: false, known: null, head: null }));
    if (k.busy) {
      k.asked = true;
      return;
    }
    if (k.again !== null && !now) return;
    k.again?.();
    k.again = null;
    const head = this.#passed?.heads[ws];
    if (head === undefined || head.batches.length === 0) return;
    if (o.fresh === true) k.known = null;
    // (a place level with this head already: nothing to send)
    const said = `${head.gen}:${head.to}:${head.made}`;
    if (k.known !== null && k.head === said && k.error === null) return;
    k.busy = true;
    const keeping = k;
    const wasError = k.error;
    const run = (async () => {
      try {
        const place = new PeerPlace(peer, this.#d.ask);
        let done = await level(place, ws, this.#own(head), keeping.known);
        if (done.behind) {
          // This station's own copy is behind what that station keeps of it: its data was rolled back. A new
          // generation (one for all the places that find it so), written there beside what it keeps.
          let begun = this.#begun.get(ws);
          if (begun === undefined || begun.from !== head.gen) {
            begun = { from: head.gen, done: (async () => {
              const held = await place.held(ws, head.origin);
              await this.#d.runner.newGenerations(Math.max(0, ...held.gens.map((g) => genMade(g.gen))));
              await this.settleExport();
            })() };
            this.#begun.set(ws, begun);
          }
          await begun.done;
          const next = this.#passed?.heads[ws];
          if (next === undefined) throw new Error("no copy of this workspace's");
          done = await level(place, ws, this.#own(next));
          if (done.behind) throw new Error("that station keeps more of this station's than it has");
        }
        keeping.known = done.known;
        keeping.head = said;
        keeping.reason = null;
        keeping.to = done.to;
        keeping.missing = done.missing;
        keeping.at = this.#d.fibers.now();
        keeping.error = null;
        keeping.tries = 0;
      } catch (e) {
        if (keeping.error === null) log.warn("copies", "a place not brought level", { ws, place: peer, error: (e as Error).message });
        keeping.error = (e as Error).message;
        keeping.reason = this.#reason(peer, e);
        keeping.known = null;
        const wait = Math.min(RETRY_MS * 2 ** keeping.tries, RETRY_MOST_MS);
        keeping.tries++;
        if (!this.#closed) keeping.again = this.#d.fibers.after(wait, () => { // timer: a retry after a failure
          keeping.again = null;
          this.#level(ws, peer, { now: true, fresh: true });
        });
        // (one not reached: the next station after those this one's copies fall to holds them meanwhile)
        if (wasError === null) this.#levelAll(ws);
      } finally {
        keeping.busy = false;
        this.#changed(keeping.error === wasError ? TELL_MS : 0);
      }
    })();
    this.#levelling.set(key, run);
    void run.then(() => {
      if (this.#levelling.get(key) === run) this.#levelling.delete(key);
      if (keeping.asked && !this.#closed) {
        keeping.asked = false;
        this.#level(ws, peer, { now: keeping.error === null });
      }
    });
  }

  /// The export brought to rest (no pass under way, nothing more waiting).
  async settleExport(): Promise<void> {
    do {
      await this.#pass();
      while (this.#passing !== null) await this.#passing;
    } while (this.#again);
  }

  #own(head: Head) {
    const dir = join(this.#d.data, "replica", "own", head.workspace, head.gen);
    return {
      head,
      batch: (name: string) => readFile(join(dir, "log", name)),
      sources: async (hashes: string[]) => new Map(Object.entries(await this.#d.runner.sources(hashes))),
    };
  }

  // ── what this station keeps of others ──

  #handOverSoon(): void {
    if (this.#handing !== null || this.#closed) return;
    this.#handAgain?.();
    this.#handAgain = null;
    this.#handing = this.#handOver()
      .then((left) => {
        this.#handTries = 0;
        if (left && !this.#closed) this.#retryHand();
      }, (e) => {
        log.warn("copies", "copies not handed over", { error: (e as Error).message });
        this.#retryHand();
      })
      .finally(() => (this.#handing = null));
  }

  #retryHand(): void {
    const wait = Math.min(RETRY_MS * 2 ** this.#handTries, RETRY_MOST_MS);
    this.#handTries++;
    this.#handAgain = this.#d.fibers.after(wait, () => this.#handOverSoon()); // timer: a retry after a failure
  }

  /// The copies this station keeps that are not its to keep now (the stations that keep each are worked out again as
  /// stations come and go): handed to those that should keep them, and let go once each of them says it holds as much.
  /// Whether some are left to hand over (one of those stations not reached).
  async #handOver(): Promise<boolean> {
    const here = this.#d.here();
    if (here === null) return false;
    let left = false;
    for (const { workspace: ws } of this.#d.places().workspaces) {
      const roster = this.#d.roster(ws);
      if (roster === null) continue;
      const taking = this.#d.taking?.() ?? new Set<string>();
      for (const origin of await readdir(join(keptDir(this.#d.data), ws)).catch(() => [] as string[])) {
        if (!STATION.test(origin) || origin === here || taking.has(origin)) continue;
        const should = keepers(ws, origin, roster.map((s) => s.id));
        if (should.includes(here)) continue;
        const mine = await this.kept.held(ws, origin);
        let all = should.length > 0;
        for (const peer of should) {
          try {
            if (!(await handOver(this.kept, new PeerPlace(peer, this.#d.ask), ws, origin))) all = false;
          } catch {
            all = false;
          }
        }
        if (all) {
          // (each of them holds as much as this one did: asked again just before it goes)
          const still = await Promise.all(should.map((p) => new PeerPlace(p, this.#d.ask).held(ws, origin).then((h) => holdsAll(mine, h), () => false)));
          if (still.every((x) => x)) {
            await rm(join(keptDir(this.#d.data), ws, origin), { recursive: true, force: true });
            log.info("copies", "a station's copies handed over", { ws, origin, to: should });
            continue;
          }
        }
        left = true;
      }
    }
    return left;
  }

  // ── what the station's settings show ──

  /// The copies of this station's chats in `ws`, as its settings show them: the stations that keep them and how far
  /// each goes; on a station with no chat of its own, the backups of stations no longer there it could restore.
  overview(ws: string, manage = false): unknown {
    const here = this.#d.here();
    const head = this.#passed?.heads[ws] ?? null;
    const names = new Map((this.#d.roster(ws) ?? []).map((s) => [s.id, s.name]));
    return {
      to: head?.to ?? 0,
      chats: head?.chats ?? 0,
      keepers: (here === null ? [] : this.#targets(ws)).map((station) => {
        const k = this.#keeping.get(`${ws}\n${station}`);
        return { station, name: names.get(station) ?? "", to: k?.to ?? 0, at: k?.at ?? null, error: k?.error ?? null, reason: k?.reason ?? null };
      }),
      // (the export not going: why, and since how many tries)
      stopped: this.#exportError === null ? null : { error: this.#exportError, tries: this.#exportTries, reason: /ENOSPC|disk is full|database or disk is full/i.test(this.#exportError) ? "full" : "error" },
      // (what came of the restore this station started again for: kept after the restart)
      restored: this.#restored,
      empty: this.#passed?.empty ?? false,
      restoring: this.#restoring !== null && this.#restoring.workspace === ws ? this.#restoring : null,
      // (on a station with no chat of its own: the lost stations' copies it could take back, as last looked for)
      restorable: this.#passed?.empty === true ? (this.#looked.get(ws) ?? null) : null,
      manage,
      formerly: this.#was,
    };
  }

  /// The copies a station with no chat of its own could take back, looked for again as it starts and as the
  /// workspace's stations change.
  readonly #looked = new Map<string, { copies: unknown[]; at: number; looking: boolean }>();

  async look(ws: string): Promise<void> {
    if (this.#passed?.empty !== true) return;
    const was = this.#looked.get(ws);
    this.#looked.set(ws, { copies: was?.copies ?? [], at: was?.at ?? 0, looking: true });
    this.#changed(0);
    let copies: unknown[] = [];
    try {
      copies = await this.restorable(ws);
    } finally {
      this.#looked.set(ws, { copies, at: this.#d.fibers.now(), looking: false });
      this.#changed(0);
    }
  }

  // ── a lost station's copy, brought back into this one ──

  /// The copies of stations of `ws` no longer there (none answers for it) that could be brought back here: each one's
  /// latest generation, as far as the furthest of the stations that keep it.
  async restorable(ws: string): Promise<unknown[]> {
    const here = this.#d.here();
    const found = new Map<string, { head: Head; from: string[] }>();
    const add = (head: Head, from: string) => {
      if (head.origin === here) return;
      const was = found.get(head.origin);
      const newer = was === undefined || genMade(head.gen) > genMade(was.head.gen) || (head.gen === was.head.gen && head.to > was.head.to);
      if (newer) found.set(head.origin, { head, from: [from] });
      else if (head.gen === was!.head.gen && head.to === was!.head.to && !was!.from.includes(from)) was!.from.push(from);
    };
    const roster = this.#d.roster(ws) ?? [];
    // (a lost station another already took the place of is not offered: two machines would both take it)
    const taken = new Set(this.#was);
    // (nor a station that is there: it answers, and its chats are its own to keep)
    const there = new Set<string>();
    await Promise.all(roster.filter((s) => s.id !== here).map(async (s) => {
      try {
        const answer = await this.#d.ask(s.id, { method: "replica.hello", workspace: ws, formerly: this.#was });
        there.add(s.id);
        const said = Array.isArray(answer?.formerly) ? answer.formerly.filter((f: unknown): f is string => typeof f === "string") : [];
        this.#heardFormerly(ws, s.id, said);
        for (const f of said) taken.add(f);
        for (const o of await new PeerPlace(s.id, this.#d.ask).origins(ws)) for (const h of o.heads as Head[]) add(h, s.id);
      } catch {}
    }));
    for (const m of this.#formerly.values()) for (const f of m.keys()) taken.add(f);
    for (const f of taken) found.delete(f);
    if (here !== null) for (const o of await this.kept.origins(ws)) for (const h of o.heads) add(h, here);
    for (const f of taken) found.delete(f);
    for (const f of there) found.delete(f);
    const names = new Map(roster.map((s) => [s.id, s.name]));
    return [...found.values()].map(({ head, from }) => ({
      station: head.origin, name: head.name || names.get(head.origin) || "", gen: head.gen, made: head.made, to: head.to,
      chats: head.chats, messages: head.messages, bytes: head.bytes, from: from.map((f) => ({ station: f, name: names.get(f) ?? "" })),
    }));
  }

  /// The stations this one took the place of.
  formerly(): string[] {
    return this.#was;
  }

  /// What came of the restore this station was started again for (null: none).
  restored(): Outcome | null {
    return this.#restored;
  }

  /// This station's copy of `ws` as it is now, brought to `peer` (a station this one's chats go to as it is retired,
  /// retire.ts): its generation.
  async bringTo(ws: string, peer: string): Promise<string> {
    await this.settleExport();
    const head = this.#passed?.heads[ws];
    if (head === undefined) throw new Error("no copy of this workspace's chats");
    const done = await level(new PeerPlace(peer, this.#d.ask), ws, this.#own(head));
    if (done.behind) throw new Error("that station keeps more of this station's chats than it has");
    return head.gen;
  }

  /// A retired station's copy (`gen`), brought here before (retire.ts), put in beside this station's own chats as it
  /// starts again: `connects`, how the ids of that station's connects go here; `ws`, its sessions' `ws` here.
  takeOver(ws: string, origin: string, gen: string, extra: { connects: Record<string, string>; ws: string | null }): Promise<void> {
    return this.restore(ws, origin, gen, { station: this.#d.here() ?? "" }, { merge: true, connects: extra.connects, ws: extra.ws });
  }

  /// Brings `origin`'s copy (`gen`) here from `from`, a station that keeps it, then has the station start again to put
  /// it in before its store opens. Only into a station with no chat of its own, unless `merge` (takeOver).
  restore(ws: string, origin: string, gen: string, from: { station: string }, merge: Merge | null = null): Promise<void> {
    if (!STATION.test(origin) || !GEN.test(gen) || !WORKSPACE.test(ws)) throw new Error("not a copy's name");
    if (merge === null && this.#passed?.empty !== true) throw new NotEmpty();
    if (this.#restoring !== null && this.#restoring.error === null) throw new Error("a restore is under way");
    const r: Restoring = { origin, name: "", workspace: ws, gen, from: from.station, done: 0, total: 0, error: null, reason: null, restart: false };
    this.#restoring = r;
    this.#changed(0);
    return this.#bring(r, from, merge).catch((e) => {
      r.error = (e as Error).message;
      r.reason = e instanceof NotEmpty ? "notEmpty" : e instanceof Gone ? "gone" : this.#reason(from.station, e);
      log.warn("copies", "a copy not brought", { origin, from: r.from, error: r.error });
      this.#changed(0);
      throw e;
    });
  }

  async #bring(r: Restoring, from: { station: string }, merge: Merge | null): Promise<void> {
    const { workspace: ws, origin, gen } = r;
    // (each batch and file written to disk as it comes, a piece at a time)
    let stream: (gen: string | null, name: string) => Promise<AsyncIterable<Buffer>>;
    let held: Held;
    if (from.station === this.#d.here()) {
      const place = this.kept;
      held = await place.held(ws, origin);
      stream = async (g, name) => place.stream(ws, origin, g, name);
    } else {
      const place = new PeerPlace(from.station, this.#d.ask);
      held = await place.held(ws, origin);
      stream = (g, name) => place.read(ws, origin, g, name);
    }
    const save = async (path: string, g: string | null, name: string) => {
      const f = await open(`${path}.part`, "w");
      try {
        for await (const piece of await stream(g, name)) await f.write(piece);
        await f.sync();
      } finally {
        await f.close();
      }
      await rename(`${path}.part`, path);
    };
    const holding = held.gens.find((g) => g.gen === gen);
    if (holding?.head == null) throw new Gone("that copy is not kept there");
    const head = holding.head;
    const names = Object.keys(head.files);
    r.name = head.name;
    r.total = head.batches.length + names.length;
    this.#changed(0);
    const dir = copyDir(this.#d.data);
    await rm(dir, { recursive: true, force: true });
    await mkdir(join(dir, gen, "log"), { recursive: true });
    await mkdir(join(dir, "files"), { recursive: true });
    for (const b of head.batches) {
      await save(join(dir, gen, "log", b), gen, b);
      r.done++;
      this.#changed(TELL_RESTORE_MS);
    }
    for (const hash of names) {
      await save(join(dir, "files", hash), null, hash);
      r.done++;
      this.#changed(TELL_RESTORE_MS);
    }
    await writeFile(join(dir, gen, "head.json"), JSON.stringify(head, null, 1));
    // (still no chat of its own, as it is about to be put in: one made meanwhile, and it is not)
    await this.settleExport();
    if (merge === null && this.#passed?.empty !== true) throw new NotEmpty();
    const ready: Ready = { origin, workspace: ws, gen, name: head.name, from: r.from, ...(merge ?? {}) };
    await writeFile(readyFile(this.#d.data), JSON.stringify(ready));
    const go = await this.#d.restart();
    r.restart = go === null;
    this.#changed(0);
    if (go !== null) await go();
  }
}

export type { Place };
