// How fast a view's frames go (docs/remote-screens.md, "Pace"): which may be sent now, and the bit rate its source is
// asked to encode at. Both from what the client's acknowledgements say of the link: how long a frame takes from sent to
// decoded (the round trip), and how much went through in the last second.
//
// Frames go while those on the way go through as fast as the link has gone lately: the oldest not acknowledged waiting
// no longer than the quickest round trip of the last RTT_WINDOW_MS and QUEUE_MS. A far link so carries as many frames
// a second as a near one. Once one waits longer a queue is building (a link slower than the frames, a packet lost and
// sent again): none goes until an acknowledgement, and the bit rate goes down to what went through, so the frames
// that come next are as many and smaller rather than fewer and late. It goes up again a step at a time while nothing
// queues, to the source's own.

/// Frames sent and not acknowledged, at most: before the link's round trip is known, and however short it is.
export const START_UNACKED = 2;
export const MAX_UNACKED = 16;
/// How much longer than its quickest round trip the oldest frame not acknowledged may be waiting while the next goes:
/// the queue a view lets build in front of a link, no more.
export const QUEUE_MS = 15;
/// How long a round trip counts towards the quickest (the link changes: another way, a relay).
export const RTT_WINDOW_MS = 10_000;
/// What went through is counted over this long.
export const DELIVERY_WINDOW_MS = 1000;
/// The lowest bit rate asked; down to `DOWN` of what went through once a queue stayed for two round trips and
/// `HOLD_MS` (a packet lost and sent again holds the frames behind it for about a round trip, then they all come: that
/// is not the link being too slow), and again each round trip and `HOLD_MS` it stays; up by `UP` each `UP_EVERY_MS` once
/// nothing queued for `UP_AFTER_MS`.
export const MIN_RATE = 300_000;
export const DOWN = 0.85;
export const HOLD_MS = 200;
export const UP = 1.15;
export const UP_EVERY_MS = 500;
export const UP_AFTER_MS = 1000;

/// The bit rate a source encodes a picture of this size at when not asked (still.fail Helper's, stillfail-screen's).
export const ownRate = (width: number, height: number) => Math.max(1_000_000, width * height * 3);

export class Pacer {
  /// The frames sent and not acknowledged, oldest first: their timestamps, sizes and when they went.
  readonly #out: { ts: number; bytes: number; at: number }[] = [];
  /// Round trips measured, oldest first.
  #trips: { at: number; ms: number }[] = [];
  /// The frames acknowledged lately: when, and their sizes.
  #through: { at: number; bytes: number }[] = [];
  /// The bit rate asked of the source, and the most it is asked (its own); null before its size is known.
  #rate: number | null = null;
  #ceiling: number | null = null;
  #down = -Infinity;
  #up = -Infinity;
  #queued = -Infinity;
  /// Since when the frames have been queuing (none acknowledged as soon as the link takes since), or null.
  #since: number | null = null;
  #first = Infinity;
  readonly #now: () => number;
  constructor(now: () => number) {
    this.#now = now;
  }

  get unacked(): number {
    return this.#out.length;
  }

  /// The source's own bit rate (its picture's size changed): what it is asked goes no higher.
  ceiling(rate: number) {
    this.#ceiling = rate;
    this.#rate = Math.min(this.#rate ?? rate, rate);
  }

  sent(ts: number, bytes: number) {
    this.#out.push({ ts, bytes, at: this.#now() });
  }

  /// The client decoded every frame up to `ts`; the newest of them gives a round trip.
  acked(ts: number) {
    const now = this.#now();
    let newest: { at: number } | null = null;
    while (this.#out.length > 0 && this.#out[0]!.ts <= ts) {
      const f = this.#out.shift()!;
      this.#through.push({ at: now, bytes: f.bytes });
      newest = f;
    }
    if (newest === null) return;
    this.#first = Math.min(this.#first, now);
    while (this.#through.length > 0 && this.#through[0]!.at < now - DELIVERY_WINDOW_MS) this.#through.shift();
    const trip = now - newest.at;
    const base = this.rtt();
    this.#trips.push({ at: now, ms: trip });
    // The latest is kept however old: a still screen sends nothing for long.
    while (this.#trips.length > 1 && this.#trips[0]!.at < now - RTT_WINDOW_MS) this.#trips.shift();
    if (base !== null && trip > base + QUEUE_MS) this.#queuing(now);
    else this.#steady(now);
  }

  /// The quickest round trip lately, or null before one.
  rtt(): number | null {
    return this.#trips.length === 0 ? null : Math.min(...this.#trips.map((t) => t.ms));
  }

  /// Whether the next frame may go now; when not, a queue is building.
  may(): boolean {
    if (this.#out.length === 0) return true;
    const rtt = this.rtt();
    if (rtt === null) return this.#out.length < START_UNACKED;
    const may = this.#out.length < MAX_UNACKED && this.#now() - this.#out[0]!.at <= rtt + QUEUE_MS;
    if (!may) this.#queuing(this.#now());
    return may;
  }

  /// The bit rate to ask of the source, or null while its own is not known.
  rate(): number | null {
    return this.#rate;
  }

  /// What went through in the last second, in bits a second.
  #delivered(now: number): number {
    if (this.#through.length === 0) return 0;
    // Over the window, or since the first acknowledgement when it came within it.
    const span = Math.max(100, Math.min(DELIVERY_WINDOW_MS, now - this.#first));
    return (this.#through.reduce((sum, f) => sum + f.bytes, 0) * 8 * 1000) / span;
  }

  #queuing(now: number) {
    this.#queued = now;
    this.#since ??= now;
    const rtt = this.rtt() ?? 0;
    if (this.#rate === null || now - this.#since < Math.max(HOLD_MS, 2 * rtt) || now - this.#down < rtt + HOLD_MS) return;
    this.#down = now;
    const through = this.#delivered(now);
    if (through > 0) this.#rate = Math.max(MIN_RATE, Math.min(this.#rate, through * DOWN));
  }

  #steady(now: number) {
    this.#since = null;
    if (this.#rate === null || this.#ceiling === null || this.#rate >= this.#ceiling) return;
    if (now - this.#queued < UP_AFTER_MS || now - this.#up < UP_EVERY_MS) return;
    this.#up = now;
    this.#rate = Math.min(this.#ceiling, this.#rate * UP);
  }
}
