// Serial indexing and directory watches shared by the photo and video libraries.
import { MediaError } from "./errors.ts";
import { type StationLink, watch } from "./station.ts";

/// The most folders watched at once (the station keeps 256 watches for everyone).
export const WATCHES = 32;
/// How often the library is gone over whole.
export const HOURLY = 60 * 60 * 1000;
type Directory = { root: string; dir: string; mtime: number };
const keyOf = (root: string, dir: string) => root + "\n" + dir;

export abstract class LibraryIndex<D extends Directory> {
  readonly #link: StationLink;
  readonly #watchId: string;
  readonly #kind: string;
  protected closed = false;
  protected dirs = new Map<string, D>();
  protected filling: Promise<void> | null = null;
  #chain: Promise<unknown> = Promise.resolve();
  #pending = 0;
  #passQueued = false;
  #hourly: NodeJS.Timeout | null = null;
  #watching = new Map<string, AbortController>();

  constructor(link: StationLink, kind: "photo" | "video", watchId: string) {
    this.#link = link;
    this.#kind = kind;
    this.#watchId = watchId;
  }

  protected abstract actor(): string | null;
  protected abstract topFolders(): { root: string; path: string }[];
  protected abstract runPass(): Promise<void>;
  protected abstract scan(d: D): Promise<void>;

  /// Starts hourly passes and the first pass once a reader is known.
  start() {
    this.#hourly = setInterval(() => this.pass(), HOURLY);
    this.#hourly.unref();
    if (this.actor()) this.pass();
  }

  async close() {
    this.closed = true;
    if (this.#hourly) clearInterval(this.#hourly);
    for (const c of this.#watching.values()) c.abort();
    this.#watching.clear();
    await this.settled();
  }

  /// Waits for queued scans and the current background fill.
  async settled() {
    for (;;) {
      const chain = this.#chain;
      const filling = this.filling;
      await chain.catch(() => {});
      await filling?.catch(() => {});
      if (chain === this.#chain && filling === this.filling && this.#pending === 0) return;
    }
  }

  /// Index changes run one at a time, including after a failed change.
  protected queue<T>(f: () => Promise<T>): Promise<T> {
    this.#pending++;
    const next = this.#chain.catch(() => {}).then(f);
    this.#chain = next.finally(() => this.#pending--);
    return next;
  }

  /// At most one additional whole pass is queued while another runs.
  pass(): Promise<void> {
    if (this.#passQueued) return Promise.resolve();
    this.#passQueued = true;
    return this.queue(async () => {
      this.#passQueued = false;
      await this.runPass();
    }).catch((e) => console.error(`media: ${this.#kind} pass failed`, e));
  }

  /// Watch the library roots first, then recently changed folders.
  protected rewatch() {
    if (this.closed) return;
    const tops = new Set(this.topFolders().map((a) => keyOf(a.root, a.path)));
    const ranked = [...this.dirs.entries()].sort((a, b) => Number(tops.has(b[0])) - Number(tops.has(a[0])) || b[1].mtime - a[1].mtime).slice(0, WATCHES);
    const want = new Map(ranked);
    for (const [k, c] of this.#watching) {
      if (!want.has(k)) {
        c.abort();
        this.#watching.delete(k);
      }
    }
    for (const [k, d] of want) {
      if (this.#watching.has(k)) continue;
      const c = new AbortController();
      this.#watching.set(k, c);
      void this.#follow(k, d, c.signal);
    }
  }

  async #follow(key: string, d: D, signal: AbortSignal) {
    while (!signal.aborted && !this.closed) {
      const actor = this.actor();
      if (!actor) return;
      try {
        if (await watch(this.#link, actor, d.root, d.dir, this.#watchId, signal)) await this.scan(this.dirs.get(key) ?? d);
      } catch (e) {
        if (signal.aborted) return;
        // A folder the station does not watch (through still.fail Helper): the hourly pass reads it.
        if (e instanceof MediaError && (e.code === "forbidden" || e.code === "not_found")) {
          if (this.#watching.get(key)?.signal === signal) this.#watching.delete(key);
          return;
        }
        await new Promise((r) => setTimeout(r, 60_000).unref());
      }
    }
  }
}
