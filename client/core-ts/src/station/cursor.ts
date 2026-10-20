// Where this device is in a station's log of what it tells everyone (station/src/api/event-log.ts): the last id heard
// of it (`<run>.<n>`), which the next stream to that station goes on from (`since`), so what came after is told again
// rather than the station read again. Only what is of the log has an id; what a stream is given because it asked (a
// session's steps, a job's log, host samples) has none, and moves nothing here.
//
// The id is written down with what its events changed (`toKeep`), so a core started again goes on from it too
// (`restored`), as long as what it wrote down is still held.

type At = { run: string; n: number };

function parse(id: string): At | null {
  const m = /^([0-9a-f]+)\.(\d+)$/.exec(id);
  return m ? { run: m[1]!, n: Number(m[2]) } : null;
}

export class Cursor {
  #at: At | null = null;
  /// As last written down.
  #kept: At | null = null;
  /// Whether where it is was written down by a core before this one, and no stream has opened since.
  restored = false;

  /// `kept`: the id a core before this one wrote down, where what it wrote down with it is still held.
  constructor(kept: string | null = null) {
    this.#at = kept === null ? null : parse(kept);
    this.#kept = this.#at;
    this.restored = this.#at !== null;
  }

  /// An id heard on a stream. Streams overlap as one takes over from another, each the log in order from where it was
  /// asked: the furthest heard of a run is where the device is. Another run's is a station started anew.
  heard(id: string): void {
    const at = parse(id);
    if (at === null) return;
    if (this.#at === null || this.#at.run !== at.run || at.n > this.#at.n) this.#at = at;
  }

  /// What the next stream asks to go on from; null: nothing heard yet (it reads the station).
  get since(): string | null {
    return this.#at === null ? null : `${this.#at.run}.${this.#at.n}`;
  }

  /// The id to write down now, with what its events changed: null when it is as last written.
  toKeep(): string | null {
    if (this.#at === null || this.#at === this.#kept) return null;
    this.#kept = this.#at;
    return this.since;
  }
}
