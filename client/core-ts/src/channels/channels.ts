// Channels: what a station holds that is only ever added to, each a run of numbered items, held on the device in part
// (a thread's entries, a session's transcript: station/channel-kinds.ts). Where the device is in a channel is the
// numbers it holds of it, kept with them; nothing else says it. Three things happen to a channel:
//
// - it is told (the push: the station says items as they are added): they are put, and it goes that far;
// - something else says how far it goes (its station's summary of it, the answer to a read of it or to a message sent
//   into it): `goesTo`;
// - it is read (the pull), by number: what came after what is held, a hole in it, the page before it, its latest page.
//
// One rule joins them, whatever said so: a channel the device holds some of and is behind on (it goes further than what
// is held, or what is held has a hole) is read (`settle`). Nothing here keeps a channel current by trusting that a
// stream told all there was: a stream that opens again says nothing of what its channels missed, so those a UI shows
// are asked what came after what is held (`catchUp`), and the rest are behind once their station's summaries say so.
//
// A part of its own: it knows no station's API, database, stream, chat or window. Who uses it says what a channel is of
// (a `Kind`), where its items are held (`Held`), how its station is asked (`Reach`), and how urgent each asking is.
// Which read comes next is fill.ts, from the numbers held and how far the channel goes alone.
import { Deferred, Effect } from "effect";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import * as fill from "./fill.ts";
import { timed } from "../spent.ts";

export type { Read } from "./fill.ts";

/// What a channel is of, and how its station is asked for it.
export type Kind = {
  /// Its name: with a station and an id, a channel (and where its items are held).
  readonly name: string;
  /// Its first item's number, and items a page.
  readonly first: number;
  readonly page: number;
  /// Whether all of it is brought onto the device and kept so (how far it goes is known, and it is read when behind);
  /// else its latest page is, and what is before as asked.
  readonly whole: boolean;
  /// Of one not brought whole: whether it is kept whole from the lowest item held up to how far it goes (read when
  /// behind there: what came after what is held, a hole a stream left), what is before that still as asked.
  readonly holes?: boolean;
  /// How much of a batch of reads one of it takes.
  readonly cost: number;
  /// The task that reads a channel, as its station's lane names it (what a UI makes urgent goes by this name).
  task(id: string): string;
  /// A read as the station takes it, and what its answer holds: the items by number, and how far the channel goes
  /// where it says.
  path(id: string, read: fill.Read): string;
  items(answer: unknown, read: fill.Read): [number, unknown][];
  last(answer: unknown): number | null;
};

export type Channel = { readonly kind: Kind; readonly station: string; readonly id: string };

/// Where channels' items are held, and how far each is known to go.
export type Held = {
  /// The numbers held of a channel, in order; the lowest and highest of them (null: none); how many of `from ..= to`.
  numbers(channel: Channel): readonly number[];
  span(channel: Channel): { min: number; max: number } | null;
  count(channel: Channel, from: number, to: number): number;
  /// Items into a channel, by number, in place of those held under the same numbers. `cutAfter`: nothing past it is
  /// kept.
  put(channel: Channel, items: [number, unknown][], cutAfter: number | null): void;
  /// Whether a channel is left as it is: let go for room, and not shown since.
  letGo(channel: Channel): boolean;
  /// How far a channel goes as far as is known (0: nothing says), and that it goes at least to `n`.
  head(channel: Channel): number;
  raise(channel: Channel, n: number): void;
  /// Of a kind kept whole from its lowest item held (`Kind.holes`): whether this one is, as its station can say how far
  /// it goes and gives what a read asks in brief (one from before does neither: its latest page alone). None: it is.
  holes?(channel: Channel): boolean;
  /// Of those: whether this one is brought whole for now, down to its first item (a session used lately).
  whole?(channel: Channel): boolean;
};

export type Answered = { _tag: "Success"; success: unknown } | { _tag: "Failure"; failure: CoreError };

/// How channels reach their stations.
export type Reach = {
  /// A read of a station.
  read(station: string, path: string, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<unknown, CoreError>;
  /// Whether a station is worth asking in the background: linked, and not found down.
  reached(station: string): boolean;
  /// A task of the station's lane: one a name, the one asked for again while it waits being the same task.
  enqueue(station: string, task: string, priority: number, work: Effect.Effect<void, CoreError>): Deferred.Deferred<void, CoreError>;
  /// Runs `work` once the burst of what the station is saying is over.
  later(station: string, work: () => void): void;
  /// A read made in the background answered, well (`error` null) or not; `nothing`: none of the channel is held.
  answered(channel: Channel, error: CoreError | null, nothing: boolean): void;
};

const keyOf = (c: Channel) => `${c.kind.name}\u0001${c.station}\u0001${c.id}`;

export class Channels {
  readonly #held: Held;
  readonly #reach: Reach;
  /// Channels whose station's stream was away: how far they go is as old as what is held, so they are asked.
  readonly #unsure = new Set<string>();
  /// Channels said to go further by something other than their items, looked at once the burst is over.
  readonly #raised = new Map<string, Map<string, Channel>>();

  constructor(held: Held, reach: Reach) {
    this.#held = held;
    this.#reach = reach;
  }

  #put(c: Channel, items: [number, unknown][], cutAfter: number | null = null): void {
    if (items.length > 0 || cutAfter !== null) timed(`put.${c.kind.name}`, () => this.#held.put(c, items, cutAfter));
  }

  // ── what says how far a channel goes ──

  /// Items told as they were added (the push): the channel goes that far, and they are put; a hole they leave in what
  /// is held is read at once. `cutAfter`: the channel was written anew up to there, and nothing past it is kept. One
  /// left as it is stays so.
  told(c: Channel, items: [number, unknown][], cutAfter: number | null = null): void {
    const newest = Math.max(-1, ...items.map(([n]) => n));
    if (newest >= 0) this.#held.raise(c, newest);
    if (this.#held.letGo(c)) return;
    this.#put(c, items, cutAfter);
    this.settle(c);
  }

  /// Something else says the channel goes at least to `n` (its station's summary of it): looked at once the burst is
  /// over, as the items it speaks of are mostly on their way.
  goesTo(c: Channel, n: number): void {
    this.#held.raise(c, n);
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

  /// Whether a channel not brought whole is kept whole from its lowest item held (Kind.holes, Held.holes).
  #holes(c: Channel): boolean {
    return c.kind.holes === true && this.#held.holes?.(c) !== false;
  }

  /// Whether the device is behind on a channel it holds some of: it goes further than what is held, or what is held has
  /// a hole. What is before all that is held is not that (brought in the background, or as asked), nor is a channel
  /// none of which is held (brought when a UI shows it, or in the background).
  behind(c: Channel): boolean {
    return (c.kind.whole || this.#holes(c)) && !this.#held.letGo(c) && fill.behind(this.#held.numbers(c), this.#held.head(c));
  }

  /// A channel the device is behind on is read until it is not: the one rule, for whatever said how far it goes.
  settle(c: Channel): void {
    // A thread's behind what is shown; another's in the background (what a UI shows of it is made urgent by its task).
    if (this.behind(c)) this.bring(c, c.kind.whole ? Priority.shown : Priority.background, "latest");
  }

  /// Whether a channel's latest items are not on the device: none held, or it goes further.
  latestMissing(c: Channel): boolean {
    return fill.latestMissing(this.#held.span(c)?.max ?? null, this.#held.head(c));
  }

  // ── reading ──

  /// The read that brings a channel's next items onto the device; null when it has all it is to have, or is left as it
  /// is. One brought whole: what came after what is held, then the highest hole, down to its first item. Else its
  /// latest page, while none is held.
  next(c: Channel): fill.Read | null {
    if (this.#held.letGo(c)) return null;
    const held = this.#held.numbers(c);
    if (!c.kind.whole) {
      if (held.length === 0) return { latest: true };
      if (!this.#holes(c)) return null;
      // What came after what is held, a hole in it; what is before all that is held only while it is brought whole
      // (else gone back to as asked): the page before it, down to its first.
      const read = fill.next(held, this.#held.head(c), c.kind.page);
      if (read !== null && !("to" in read && read.to < held[0]!)) return read;
      return held[0]! > c.kind.first && this.#held.whole?.(c) === true ? { before: held[0]! } : null;
    }
    return fill.next(held, this.#held.head(c), c.kind.page);
  }

  /// Brings a channel onto the device, a read a run (the task asks itself again while there is more and the last read
  /// brought some, so what is more urgent goes between). `whole`: all of it, down to its first item. `latest`: no more
  /// than the device is behind on (what came after what is held, and the holes in it), or the latest page of one none
  /// of which is held; what is before that is left to be brought whole, or asked for.
  bring(c: Channel, priority: number, how: "whole" | "latest" = "whole"): Deferred.Deferred<void, CoreError> | null {
    if (this.#held.letGo(c)) return null;
    return this.#reach.enqueue(c.station, c.kind.task(c.id), priority, this.#page(c, priority, how));
  }

  /// A channel's station's stream was away, so nothing says whether it goes further than what is held: asked what came
  /// after that, whatever its summary says (it is as old). One none of which is held is not asked: it is brought.
  catchUp(c: Channel, priority: number): void {
    if (!c.kind.whole || this.#held.letGo(c) || this.#held.span(c) === null) return;
    this.#unsure.add(keyOf(c));
    this.#reach.enqueue(c.station, c.kind.task(c.id), priority, this.#page(c, priority, "latest"));
  }

  #page(c: Channel, priority: number, how: "whole" | "latest"): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.#reach.reached(c.station)) return;
      const top = this.#unsure.delete(keyOf(c)) && !this.#held.letGo(c) ? (this.#held.span(c)?.max ?? null) : null;
      const read: fill.Read | null = top !== null ? { after: top } : this.next(c);
      if (read === null) return;
      const before = this.#held.numbers(c).length;
      this.#took(c, read, yield* Effect.result(this.#reach.read(c.station, c.kind.path(c.id, read), { quiet: true })));
      // More to bring: asked again, behind what is more urgent. Not after a read that brought nothing new (its station
      // does not have what is asked: asked again, it would answer the same), but for the asking of what came after.
      const brought = top !== null || this.#held.numbers(c).length > before;
      if (brought && (how === "whole" ? this.next(c) !== null : this.behind(c))) this.bring(c, priority, how);
    });
  }

  /// A read made in the background, as the station answered it: its items put, and the channel going as far as it
  /// says. How many items came.
  #took(c: Channel, read: fill.Read, answer: Answered): number {
    const nothing = this.#held.span(c) === null;
    if (answer._tag === "Failure") {
      this.#reach.answered(c, answer.failure, nothing);
      return 0;
    }
    this.#reach.answered(c, null, nothing);
    const items = c.kind.items(answer.success, read);
    this.#put(c, items);
    const last = c.kind.last(answer.success);
    if (last !== null && last > this.#held.head(c)) this.goesTo(c, last);
    return items.length;
  }

  /// A channel's next read as one of a batch of reads (a station's history swept in the background): its path, and what
  /// its answer does (how many items came). Null when there is nothing to read of it.
  batched(c: Channel): { path: string; took(answer: Answered): number } | null {
    const read = this.next(c);
    return read === null ? null : { path: c.kind.path(c.id, read), took: (answer) => this.#took(c, read, answer) };
  }

  /// A push says the channel goes to `n` (its station's notice, through still.fail cloud, while the station's stream may
  /// be away): unless `n` is held, what came after what is held is read now, and waited on. With no `n` (an older
  /// station's notice), what came after what is held is asked, as after a stream that was away.
  pushed(c: Channel, n: number | null, priority: number): Effect.Effect<void> {
    return Effect.suspend(() => {
      if (n !== null) {
        this.#held.raise(c, n);
        if (this.#held.count(c, n, n) > 0) return Effect.void;
      } else if (c.kind.whole && this.#held.span(c) !== null) this.#unsure.add(keyOf(c));
      const asked = this.bring(c, priority, "latest");
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
      if (before <= c.kind.first || this.#held.count(c, from, before - 1) === before - from) return Effect.void;
      return Effect.flatMap(this.read(c, { before }, options), () =>
        this.#held.count(c, before - 1, before - 1) === 1 ? Effect.void : this.#incomplete());
    });
  }

  #incomplete(): Effect.Effect<never, CoreError> {
    return Effect.fail(new CoreError("bad_response", t("station.core.incompleteReply")));
  }

  /// Items `from ..= to` onto the device (a window moved there): read now, unless they are all held.
  range(c: Channel, from: number, to: number, options: { quiet: boolean; ctx?: SpanContext | null }): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      if (to < from || this.#held.count(c, from, to) === to - from + 1) return Effect.void;
      return Effect.flatMap(this.read(c, { from, to }, options), () =>
        this.#held.count(c, from, to) === to - from + 1 ? Effect.void : this.#incomplete());
    });
  }
}
