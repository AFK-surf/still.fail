// What a station said that its pages show beyond the database's tables (a link's `memory`): its host's figures and its
// connection's, its screens, its logins, a job's log, what still.fail uses of its machine, the transfers into its
// drive. Kept in its account's database too, as the station's documents (`memory\n<key>`), and read back from there
// when a link asks for what this run has not heard: a page shows what was last said from the moment the app opens
// again, then what the station says now (2026-10-26: what a page showed once shows again after a restart or an update;
// only a new install waits). Before, all of it was in memory alone, and each page waited for its station again after
// every start.
//
// What is live only while it is watched (a login's terminal, what a search found) is `hold`: in memory alone. A key
// is written as it changes, at most once every KEEP_MS, its latest value once that wait is over (a host's figures, a
// running job's log as it grows, come every few seconds). `fresh`: what the station said since this core started, as
// against what was kept before it (a job's log is read once a run, whatever is kept of it).

/// How long a key waits after it was last written before it is written again.
export const KEEP_MS = 60_000;

/// Where a station's memory is kept: its account's database (data.ts `stationMemory`).
export interface Keeper {
  read(key: string): unknown;
  /// `undefined`: none any more.
  write(key: string, value: unknown): void;
  /// At most `most` of the keys that start with `prefix`, the latest written: the others go.
  bound(prefix: string, most: number): void;
  now(): number;
  /// Runs `run` in `ms`, unless the link is let go first.
  later(ms: number, run: () => void): void;
}

export class Memory {
  readonly #keeper: Keeper | null;
  /// Kinds of keys that grow without end (a log a job), each kept to its most: `[prefix, most]`.
  readonly #bounded: readonly [string, number][];
  readonly #values = new Map<string, unknown>();
  /// Keys read from the keeper this run (found or not).
  readonly #looked = new Set<string>();
  readonly #fresh = new Set<string>();
  readonly #held = new Set<string>();
  /// When each key was last written; those to be written once their wait is over.
  readonly #written = new Map<string, number>();
  readonly #due = new Set<string>();

  constructor(keeper: Keeper | null = null, bounded: readonly [string, number][] = []) {
    this.#keeper = keeper;
    this.#bounded = bounded;
  }

  get(key: string): unknown {
    if (!this.#values.has(key) && this.#keeper !== null && !this.#looked.has(key)) {
      this.#looked.add(key);
      const kept = this.#keeper.read(key);
      if (kept !== undefined) this.#values.set(key, kept);
    }
    return this.#values.get(key);
  }

  has(key: string): boolean {
    return this.get(key) !== undefined;
  }

  /// Said by the station since this core started.
  fresh(key: string): boolean {
    return this.#fresh.has(key);
  }

  /// What this run holds (what is only kept is not among them until it is asked for).
  keys(): IterableIterator<string> {
    return this.#values.keys();
  }

  /// What the station says now: held, and kept.
  set(key: string, value: unknown): void {
    this.#values.set(key, value);
    this.#looked.add(key);
    this.#fresh.add(key);
    this.#held.delete(key);
    this.#keep(key);
  }

  /// What the station says now, live only while it is watched: held in memory alone.
  hold(key: string, value: unknown): void {
    this.#values.set(key, value);
    this.#looked.add(key);
    this.#fresh.add(key);
    this.#held.add(key);
  }

  delete(key: string): void {
    const kept = !this.#held.has(key);
    this.#values.delete(key);
    this.#looked.add(key);
    this.#fresh.delete(key);
    this.#held.delete(key);
    this.#due.delete(key);
    if (kept) this.#keeper?.write(key, undefined);
  }

  #keep(key: string): void {
    const keeper = this.#keeper;
    if (keeper === null || this.#due.has(key)) return;
    const last = this.#written.get(key);
    const wait = last === undefined ? 0 : last + KEEP_MS - keeper.now();
    if (wait <= 0) return this.#write(key);
    this.#due.add(key);
    keeper.later(wait, () => {
      if (!this.#due.delete(key)) return;
      this.#write(key);
    });
  }

  #write(key: string): void {
    const keeper = this.#keeper!;
    if (!this.#values.has(key) || this.#held.has(key)) return;
    const first = !this.#written.has(key);
    this.#written.set(key, keeper.now());
    keeper.write(key, this.#values.get(key));
    if (!first) return;
    for (const [prefix, most] of this.#bounded) if (key.startsWith(prefix)) keeper.bound(prefix, most);
  }
}
