// Channels: what a station holds that is only ever added to, each a run of numbered items (a thread's entries, a
// session's transcript: channel-kinds.ts), held on the device in part. Where the device is in a channel is the numbers
// it holds of it, kept with them; nothing else says it. Three things happen to a channel:
//
// - it is told (the station's stream says items as they are added): they are put, and it goes that far;
// - something else says how far it goes (its station's summary of it, the answer to a read of it or to a message sent
//   into it): `goesTo`;
// - it is read: what came after what is held, a hole in it, the page before it, its latest page.
//
// One rule joins them, whatever said so: a channel the device holds some of and is behind on (it goes further than what
// is held, or what is held has a hole) is read (`settle`). Nothing here keeps a channel current by trusting that a
// stream told all there was: a stream that opens again says nothing of what its channels missed, so those a UI shows
// are asked what came after what is held (`catchUp`), and the rest are behind once their station's summaries say so.
//
// What a channel is of, which of them a UI shows and how urgent one is are not known here: who uses this says so (a
// `Kind`, a priority with each asking).
import { Deferred, Effect } from "effect";
import type { Data } from "../data.ts";
import type { CoreError } from "../error.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import * as fill from "./channel-fill.ts";

/// What a channel is of: where its items are held and how its station is asked for them.
export type Kind = {
  /// The log its items are held in (data.ts).
  readonly table: "entry" | "transcript";
  /// Its first item's number, and items a page.
  readonly first: number;
  readonly page: number;
  /// Whether all of it is brought onto the device and kept so (how far it goes is known, and it is read when behind);
  /// else its latest page is, and what is before as asked.
  readonly whole: boolean;
  /// How much of a batch of reads one of it takes (sync.ts HISTORY_BATCH).
  readonly cost: number;
  /// The task that reads a channel, as its station's lane names it (what a UI makes urgent goes by this name).
  task(id: string): string;
  /// A read as the station takes it, and what its answer holds: the items by number, and how far the channel goes
  /// where it says.
  path(id: string, read: fill.Read): string;
  items(answer: unknown, read: fill.Read): [number, unknown][];
  last(answer: unknown): number | null;
  /// How far a channel goes as far as is known, and that it goes at least to `n`.
  head(data: Data, station: string, id: string): number;
  raise(data: Data, station: string, id: string, n: number): void;
};

export type Channel = { readonly kind: Kind; readonly station: string; readonly id: string };

type Answered = { _tag: "Success"; success: unknown } | { _tag: "Failure"; failure: CoreError };

/// How channels reach their stations, as their user gives it.
export type Reach = {
  /// A read of a station.
  read(station: string, path: string, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<unknown, CoreError>;
  /// Whether a station is worth asking in the background: linked, and not found down.
  reached(station: string): boolean;
  /// A task of the station's lane.
  enqueue(station: string, task: string, priority: number, work: Effect.Effect<void, CoreError>): Deferred.Deferred<void, CoreError>;
  /// Runs `work` once the burst of what the station is saying is over.
  later(station: string, work: () => void): void;
  /// A read made in the background answered, well (`error` null) or not; `nothing`: none of the channel is held.
  answered(channel: Channel, error: CoreError | null, nothing: boolean): void;
};

const keyOf = (c: Channel) => `${c.kind.table}\u0001${c.station}\u0001${c.id}`;

export class Channels {
  readonly #data: Data;
  readonly #reach: Reach;
  /// Channels whose station's stream was away: how far they go is as old as what is held, so they are asked.
  readonly #unsure = new Set<string>();
  /// Channels said to go further by something other than their items, looked at once the burst is over.
  readonly #raised = new Map<string, Map<string, Channel>>();

  constructor(data: Data, reach: Reach) {
    this.#data = data;
    this.#reach = reach;
  }

  /// Whether a channel is left as it is: let go for room, and not shown since (data.ts KEPT).
  #letGo(c: Channel): boolean {
    return this.#data.evicted(c.kind.table, c.station, c.id);
  }

  #numbers(c: Channel): number[] {
    return this.#data.logNumbers(c.kind.table, c.station, c.id);
  }

  #put(c: Channel, items: [number, unknown][], cutAfter: number | null = null): void {
    if (items.length > 0 || cutAfter !== null) this.#data.putItems(c.kind.table, c.station, c.id, items, cutAfter);
  }

  // ── what says how far a channel goes ──

  /// Items told as they were added (the push): the channel goes that far, and they are put; a hole they leave in what
  /// is held is read at once. `cutAfter`: the channel was written anew up to there, and nothing past it is kept. One
  /// left as it is stays so.
  told(c: Channel, items: [number, unknown][], cutAfter: number | null = null): void {
    const newest = Math.max(-1, ...items.map(([n]) => n));
    if (newest >= 0) c.kind.raise(this.#data, c.station, c.id, newest);
    if (this.#letGo(c)) return;
    this.#put(c, items, cutAfter);
    this.settle(c);
  }

  /// Something else says the channel goes at least to `n` (its station's summary of it): looked at once the burst is
  /// over, as the items it speaks of are mostly on their way.
  goesTo(c: Channel, n: number): void {
    c.kind.raise(this.#data, c.station, c.id, n);
    this.#settleLater(c);
  }

  #settleLater(c: Channel): void {
    let waiting = this.#raised.get(c.station);
    if (waiting) return void waiting.set(keyOf(c), c);
    waiting = new Map([[keyOf(c), c]]);
    this.#raised.set(c.station, waiting);
    this.#reach.later(c.station, () => {
      this.#raised.delete(c.station);
      for (const channel of waiting.values()) this.settle(channel);
    });
  }

  /// A station is let go of: what waited on its burst to be over waits no more.
  forget(station: string): void {
    this.#raised.delete(station);
  }

  // ── the rule ──

  /// Whether the device is behind on a channel it holds some of: it goes further than what is held, or what is held has
  /// a hole. What is before all that is held is not that (brought in the background, or as asked), nor is a channel
  /// none of which is held (brought when a UI shows it, or in the background).
  behind(c: Channel): boolean {
    return c.kind.whole && !this.#letGo(c) && fill.behind(this.#numbers(c), c.kind.head(this.#data, c.station, c.id));
  }

  /// A channel the device is behind on is read: the one rule, for whatever said how far it goes.
  settle(c: Channel): void {
    if (this.behind(c)) this.bring(c, Priority.shown, true);
  }

  /// Whether a channel's latest items are not on the device: none held, or it goes further.
  latestMissing(c: Channel): boolean {
    return fill.latestMissing(this.#data.logSpan(c.kind.table, c.station, c.id)?.max ?? null, c.kind.head(this.#data, c.station, c.id));
  }

  // ── reading ──

  /// The read that brings a channel's next items onto the device; null when it has all it is to have, or is left as it
  /// is. One brought whole: what came after what is held, then the highest hole, down to its first item. Else its
  /// latest page, while none is held.
  next(c: Channel): fill.Read | null {
    if (this.#letGo(c)) return null;
    const held = this.#numbers(c);
    if (!c.kind.whole) return held.length === 0 ? { latest: true } : null;
    return fill.next(held, c.kind.head(this.#data, c.station, c.id), c.kind.page);
  }

  /// Brings a channel onto the device, a page a run (the task asks itself again while there is more, so what is more
  /// urgent goes between); `once`: the next page only.
  bring(c: Channel, priority: number, once = false): Deferred.Deferred<void, CoreError> | null {
    if (this.#letGo(c)) return null;
    return this.#reach.enqueue(c.station, c.kind.task(c.id), priority, this.#page(c, priority, once));
  }

  /// A channel's station's stream was away, so nothing says whether it goes further than what is held: asked what came
  /// after that, whatever its summary says (it is as old). One none of which is held is not asked: it is brought.
  catchUp(c: Channel, priority: number): void {
    if (!c.kind.whole || this.#letGo(c) || this.#data.logSpan(c.kind.table, c.station, c.id) === null) return;
    this.#unsure.add(keyOf(c));
    this.#reach.enqueue(c.station, c.kind.task(c.id), priority, this.#page(c, priority, true));
  }

  #page(c: Channel, priority: number, once: boolean): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.#reach.reached(c.station)) return;
      const top = this.#unsure.delete(keyOf(c)) && !this.#letGo(c) ? (this.#data.logSpan(c.kind.table, c.station, c.id)?.max ?? null) : null;
      const read: fill.Read | null = top !== null ? { after: top } : this.next(c);
      if (read === null) return;
      const came = this.#took(c, read, yield* Effect.result(this.#reach.read(c.station, c.kind.path(c.id, read), { quiet: true })));
      // More to bring: asked again, behind what is more urgent.
      if (!once && came > 0 && this.next(c) !== null) this.bring(c, priority);
    });
  }

  /// A read made in the background, as the station answered it: its items put, and the channel going as far as it
  /// says. How many items came.
  #took(c: Channel, read: fill.Read, answer: Answered): number {
    const nothing = this.#data.logSpan(c.kind.table, c.station, c.id) === null;
    if (answer._tag === "Failure") {
      this.#reach.answered(c, answer.failure, nothing);
      return 0;
    }
    this.#reach.answered(c, null, nothing);
    const items = c.kind.items(answer.success, read);
    this.#put(c, items);
    const last = c.kind.last(answer.success);
    if (last !== null && last > c.kind.head(this.#data, c.station, c.id)) this.goesTo(c, last);
    return items.length;
  }

  /// A channel's next read as one of a batch of reads (a station's history swept in the background): its path, and what
  /// its answer does (how many items came). Null when there is nothing to read of it.
  batched(c: Channel): { path: string; took(answer: Answered): number } | null {
    const read = this.next(c);
    return read === null ? null : { path: c.kind.path(c.id, read), took: (answer) => this.#took(c, read, answer) };
  }

  /// A message sent into the channel was given number `n`: it goes that far, and unless `n` is held what came after
  /// what is held is read now, and waited on.
  sent(c: Channel, n: number): Effect.Effect<void> {
    return Effect.suspend(() => {
      c.kind.raise(this.#data, c.station, c.id, n);
      if (this.#data.logCount(c.kind.table, c.station, c.id, n, n) > 0) return Effect.void;
      const asked = this.bring(c, Priority.asked, true);
      return asked === null ? Effect.void : Effect.ignore(Deferred.await(asked));
    });
  }

  /// One read of a channel, now, for someone who waits on it (it fails as the read does): what came of it that the
  /// read asked for is put, in place of what is held of it. How many items.
  read(c: Channel, read: fill.Read, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<number, CoreError> {
    return Effect.map(this.#reach.read(c.station, c.kind.path(c.id, read), options), (answer) => {
      const items = c.kind.items(answer, read).filter(([n]) => ("before" in read ? n < read.before : "from" in read ? n >= read.from && n <= read.to : true));
      this.#put(c, items);
      return items.length;
    });
  }

  /// The page before item `before` onto the device (someone went back to it): read now, unless it is all held.
  older(c: Channel, before: number, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const from = Math.max(c.kind.first, before - c.kind.page);
      if (before <= c.kind.first || this.#data.logCount(c.kind.table, c.station, c.id, from, before - 1) === before - from) return Effect.void;
      return Effect.asVoid(this.read(c, { before }, options));
    });
  }

  /// Items `from ..= to` onto the device (a window moved there): read now, unless they are all held.
  range(c: Channel, from: number, to: number, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      if (to < from || this.#data.logCount(c.kind.table, c.station, c.id, from, to) === to - from + 1) return Effect.void;
      return Effect.asVoid(this.read(c, { from, to }, options));
    });
  }
}
