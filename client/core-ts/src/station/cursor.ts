// Where this device is in a station's log of what it tells everyone (station/src/api/event-log.ts): the last id heard
// of it (`<run>.<n>`), which the next stream to that station goes on from (`since`), so what came after is told again
// rather than the station read again. Only what is of the log has an id; what a stream is given because it asked (a
// session's steps, a job's log, host samples) has none, and moves nothing here.
//
// The id is written down with what its events changed (`toKeep`), so a core started again goes on from it too
// (`restored`), as long as what it wrote down is still held. Not while the station is being read afresh (`reading`):
// the station tells a stream that is not resumed nothing of what came before it, so what the device holds stands on the
// id only once that reading is done; a core started again before then (a phone letting the app's process go while a
// slow link reads the lists) would go on from the id and never read what the lists missed.

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
  /// Readings of the station afresh not done yet; whether one could not read all of it.
  #reading = 0;
  #unread = false;

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

  /// The id to write down now, with what its events changed: null when it is as last written, or not to be yet.
  toKeep(): string | null {
    if (this.#reading > 0 || this.#unread || this.#at === null || this.#at === this.#kept) return null;
    this.#kept = this.#at;
    return this.since;
  }

  /// The station is read afresh: nothing is written down until it is (`read`), and what was is to be forgotten.
  reading(): void {
    this.#reading++;
    this.#unread = false;
    this.#kept = null;
  }

  /// A reading of the station could not read all of it: nothing is written down until another reads it all.
  unread(): void {
    this.#unread = true;
  }

  /// A reading of the station is done: the id to write down now, once none is still reading and all was read.
  read(): string | null {
    this.#reading = Math.max(this.#reading - 1, 0);
    return this.toKeep();
  }
}
