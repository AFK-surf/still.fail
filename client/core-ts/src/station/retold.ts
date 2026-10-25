// What a station's stream told of what its reads bring too (a session's summary, a chat's row, a thread, a job, a
// document), kept in order while a read is out. A read answers the station as it was at some moment after it was asked,
// and what the stream told after it was asked is no older than that: once what the read brought is held, what was told
// since goes on top of it again, as it came (sync.ts `#retell`). Without it, a slow read put what had changed since in
// the past again: a new chat's lists, read as its first message went, came after its agent was told at work and had it
// at rest again, its activity and its mark gone for the whole of that turn.
//
// What was told is kept only while some read asked before it is out.

type Told = { n: number; station: string; name: string; data: unknown };

export class Retold {
  /// How many things were told.
  #n = 0;
  readonly #told: Told[] = [];
  /// The reads out, each by what had been told when it was asked.
  readonly #out = new Map<number, number>();
  #reads = 0;

  /// A read asked now: what it is known by from here.
  asked(): number {
    const read = ++this.#reads;
    this.#out.set(read, this.#n);
    return read;
  }

  /// Something a station's stream told (`name`, its data), kept for the reads out.
  told(station: string, name: string, data: unknown): void {
    this.#n++;
    if (this.#out.size > 0) this.#told.push({ n: this.#n, station, name, data });
  }

  /// What `station`'s stream told after `read` was asked, in order.
  since(read: number, station: string): { name: string; data: unknown }[] {
    const asked = this.#out.get(read);
    if (asked === undefined) return [];
    return this.#told.filter((t) => t.n > asked && t.station === station);
  }

  /// A read answered or given up: what no read out needs any more goes.
  over(read: number): void {
    this.#out.delete(read);
    const first = Math.min(...this.#out.values());
    let gone = 0;
    while (gone < this.#told.length && this.#told[gone]!.n <= first) gone++;
    this.#told.splice(0, gone);
  }
}
