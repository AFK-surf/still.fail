// Folders of the drive shown in a client, watched while they are: a client follows `GET /drive/watch` as events, told
// `changed` each time something in the folder changes (an agent wrote a file there, one was renamed on the machine),
// for as long as it keeps the stream open (`follow`). A client from before asks it again and again instead, answered
// as soon as something changes, else after a while with nothing (`changed`): each such asking has its own watch
// (`id`), kept a minute past its last asking, so a change between two askings is told at the next one, not lost.
import { type FSWatcher, watch } from "node:fs";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";

/// How long one asking is held, nothing having changed.
export const HELD_MS = 25_000;
/// How long a watch is kept with nobody asking.
const KEPT_MS = 60_000;
/// The most watches at once (each is a file handle): past it, the one asked least lately goes.
const MOST = 256;
/// A burst of writes is one change.
const SETTLE_MS = 250;

type Watched = { watcher: FSWatcher; changed: boolean; waiting: Set<() => void>; drop: (() => void) | null; settle: (() => void) | null; asked: number };

export class FolderWatches {
  readonly #by = new Map<string, Watched>();
  readonly #held: number;
  readonly #kept: number;
  readonly #time: Fibers;
  readonly #open: (dir: string) => FSWatcher;
  #followers = 0;

  constructor(held = HELD_MS, kept = KEPT_MS, clock?: Clock.Clock, open: (dir: string) => FSWatcher = (dir) => watch(dir, { persistent: false })) {
    this.#held = held;
    this.#kept = kept;
    this.#time = new Fibers("drive watches", clock);
    this.#open = open;
  }

  /// Whether the folder at `dir` changed since `id` last asked (at once if it did), else as soon as it does, `held` at
  /// most. A folder that cannot be watched answers false once held (the client reads it again at its own pace).
  async changed(dir: string, id: string): Promise<boolean> {
    const key = `${id}\0${dir}`;
    let w = this.#by.get(key);
    if (!w) {
      const made = this.#watch(key, dir);
      if (!made) {
        await this.#time.sleep(this.#held);
        return false;
      }
      w = made;
    }
    w.drop?.();
    w.drop = null;
    w.asked = this.#time.now();
    if (w.changed) {
      w.changed = false;
      this.#letGo(key, w);
      return true;
    }
    const watched = w;
    const told = await new Promise<boolean>((resolve) => {
      const timer = this.#time.after(this.#held, () => { watched.waiting.delete(wake); resolve(false); });
      const wake = () => { timer(); watched.waiting.delete(wake); resolve(true); };
      watched.waiting.add(wake);
    });
    if (told) watched.changed = false;
    this.#letGo(key, watched);
    return told;
  }

  /// Tells `told` each time the folder at `dir` changes (a burst of writes once), and once more if it goes, until the
  /// returned function is called; null when it cannot be watched (none left, or no such folder).
  follow(dir: string, told: () => void): (() => void) | null {
    const key = `\u0001${++this.#followers}\u0000${dir}`;
    const w = this.#watch(key, dir);
    if (!w) return null;
    w.drop?.();
    w.drop = null;
    const wake = () => told();
    w.waiting.add(wake);
    return () => {
      w.waiting.delete(wake);
      this.#close(key, w);
    };
  }

  /// Every watch closed (the station stopping).
  close(): void {
    for (const [key, w] of this.#by) this.#close(key, w);
    void this.#time.close();
  }

  #watch(key: string, dir: string): Watched | null {
    if (this.#by.size >= MOST) {
      const oldest = [...this.#by].filter(([, w]) => w.waiting.size === 0).sort((a, b) => a[1].asked - b[1].asked)[0];
      if (oldest) this.#close(oldest[0], oldest[1]);
      else return null;
    }
    let watcher: FSWatcher;
    try {
      watcher = this.#open(dir);
    } catch {
      return null;
    }
    const w: Watched = { watcher, changed: false, waiting: new Set(), drop: null, settle: null, asked: this.#time.now() };
    watcher.on("change", () => {
      if (w.settle) return;
      w.settle = this.#time.after(SETTLE_MS, () => {
        w.settle = null;
        if (w.waiting.size > 0) for (const wake of [...w.waiting]) wake();
        else w.changed = true;
      });
    });
    // Gone (the folder removed, renamed): told as a change, for the client to read it and be told so.
    watcher.on("error", () => {
      this.#close(key, w);
      for (const wake of [...w.waiting]) wake();
    });
    this.#by.set(key, w);
    return w;
  }

  /// Kept a while with nobody asking, for the next asking to be told what changed meanwhile.
  #letGo(key: string, w: Watched): void {
    if (w.waiting.size > 0 || this.#by.get(key) !== w) return;
    w.drop?.();
    w.drop = this.#time.after(this.#kept, () => this.#close(key, w));
  }

  #close(key: string, w: Watched): void {
    if (this.#by.get(key) === w) this.#by.delete(key);
    w.drop?.();
    w.settle?.();
    w.watcher.close();
  }
}
