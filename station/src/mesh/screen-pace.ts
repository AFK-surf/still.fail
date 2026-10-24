// How fast a view's frames go (docs/remote-screens.md, "Pace"): which may be sent now, and the bit rate its source is
// asked to encode at. Both from what the client's acknowledgements say of the link: how long a frame takes from sent to
// decoded (the round trip), and how much went through in the last second.
//
// Frames go while those on the way go through as fast as the link has gone lately: the oldest not acknowledged waiting
// no longer than the quickest round trip of the last RTT_WINDOW_MS and QUEUE_MS. A far link so carries as many frames
// a second as a near one. Once one waits longer a queue is building (a link slower than the frames, a packet lost and
// sent again): none goes until an acknowledgement, and the bit rate goes down to what went through, so the frames
// that come next are as many and smaller rather than fewer and late. It goes up again a step at a time while nothing
// is lowered, to the source's own. A view starts at START_RATE (its first frame, a whole picture, is its largest: on a
// narrow link one at the source's own rate held the view up for a second) and goes up by START_UP each step until it
// is first lowered.

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
export const START_RATE = 1_500_000;
/// What went through is counted only once acknowledgements have come for this long.
export const MEASURED_MS = 500;
export const START_UP = 1.5;

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
  /// Since when the frames have been queuing (none acknowledged as soon as the link takes since), or null.
  #since: number | null = null;
  #first = Infinity;
  readonly #now: () => number;
  /// `start`: the bit rate the source was opened at (none: its own).
  constructor(now: () => number, start: number | null = null) {
    this.#now = now;
    this.#rate = start;
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
  through(): number {
    return this.#delivered(this.#now());
  }

  /// What went through in the last second, in bits a second.
  #delivered(now: number): number {
    if (this.#through.length === 0) return 0;
    // Over the window, or since the first acknowledgement when it came within it.
    const span = Math.max(100, Math.min(DELIVERY_WINDOW_MS, now - this.#first));
    return (this.#through.reduce((sum, f) => sum + f.bytes, 0) * 8 * 1000) / span;
  }

  #queuing(now: number) {
    this.#since ??= now;
    const rtt = this.rtt() ?? 0;
    if (this.#rate === null || now - this.#since < Math.max(HOLD_MS, 2 * rtt) || now - this.#down < rtt + HOLD_MS) return;
    // What went through is not known yet (the first frame, a whole picture, is most of it): nothing to go by.
    if (now - this.#first < MEASURED_MS) return;
    this.#down = now;
    const through = this.#delivered(now);
    if (through > 0) this.#rate = Math.max(MIN_RATE, Math.min(this.#rate, through * DOWN));
  }

  #steady(now: number) {
    this.#since = null;
    if (this.#rate === null || this.#ceiling === null || this.#rate >= this.#ceiling) return;
    // Starting: never lowered yet. Up once it has not been lowered for UP_AFTER_MS (a frame held a moment by a packet
    // lost, which lowers nothing, holds nothing up).
    const starting = this.#down === -Infinity;
    if ((!starting && now - this.#down < UP_AFTER_MS) || now - this.#up < UP_EVERY_MS) return;
    this.#up = now;
    this.#rate = Math.min(this.#ceiling, this.#rate * (starting ? START_UP : UP));
  }
}

/// A picture fitted into 1280×720 while the link carries little.
export const LOW_BOUNDS = { maxWidth: 1280, maxHeight: 720 };
/// The rate at most this share of what a picture of its size is encoded at, for DOWNSIZE_MS, and the source using it
/// (what went through at least USED of it: a screen that changes little needs little, and is not made smaller for
/// it): the smaller picture.
export const DOWNSIZE_SHARE = 0.25;
export const USED = 0.6;
export const DOWNSIZE_MS = 3000;
/// The smaller picture's rate at its own (the link carries all of it) for UPSIZE_MS: the view's own size again.
export const UPSIZE_MS = 3000;

/// How large a picture a view asks of its source by the rate the pace asks: as the view asked it, or LOW_BOUNDS while
/// the link carries a quarter or less of what a picture that size is encoded at (fewer pixels, each sharper: text that
/// a 1080p picture at a few hundred kbit/s blurs stays readable at 720p). Back once the smaller picture's rate stays at
/// its own.
export class Sizer {
  readonly #now: () => number;
  readonly #asked: { maxWidth: number; maxHeight: number };
  #low = false;
  #since: number | null = null;
  constructor(now: () => number, asked: { maxWidth: number; maxHeight: number }) {
    this.#now = now;
    this.#asked = asked;
  }

  get low(): boolean {
    return this.#low;
  }

  /// With the rate asked now, what went through, and the picture's size now: the bounds to ask for, when they change;
  /// else null.
  step(rate: number, through: number, size: { width: number; height: number }): { maxWidth: number; maxHeight: number } | null {
    // Asked no larger than the small one: nothing to make smaller.
    if (this.#asked.maxWidth <= LOW_BOUNDS.maxWidth && this.#asked.maxHeight <= LOW_BOUNDS.maxHeight) return null;
    const own = ownRate(size.width, size.height);
    const now = this.#now();
    const holds = this.#low ? rate >= own * 0.98 : rate <= own * DOWNSIZE_SHARE && through >= rate * USED;
    if (!holds) {
      this.#since = null;
      return null;
    }
    this.#since ??= now;
    if (now - this.#since < (this.#low ? UPSIZE_MS : DOWNSIZE_MS)) return null;
    this.#since = null;
    this.#low = !this.#low;
    return this.#low ? { ...LOW_BOUNDS } : { ...this.#asked };
  }
}

/// How late a view's frames are, said every LATENCY_EVERY_MS while frames go: from a picture's capture to its drawing on
/// the device (`frame`; the acknowledgement's arrival less half the link's quickest round trip, the way back), and from
/// its capture to its going out (`before`: waiting to be asked for, encoded; an encoder that holds a picture back until
/// the next comes shows here). Medians of the last LATENCY_WINDOW_MS. A frame's timestamp is its capture time on the
/// host's own clock (still.fail Helper's mach time, stillfail-screen's QPC: what `now` reads here); one off it by more
/// than 10 s (a source with a clock of its own) is not counted.
export const LATENCY_EVERY_MS = 1000;
export const LATENCY_WINDOW_MS = 2000;

/// The host's clock in ms, as the helpers stamp frames (process.hrtime: mach_absolute_time, QueryPerformanceCounter).
export const hostNow = () => Number(process.hrtime.bigint()) / 1e6;

export class FrameLatency {
  readonly #now: () => number;
  readonly #out = new Map<number, { capture: number; sent: number }>();
  #samples: { at: number; frame: number; before: number }[] = [];
  #said = -Infinity;
  constructor(now: () => number = hostNow) {
    this.#now = now;
  }

  /// A frame of capture time `ts` (µs) went out now.
  sent(ts: number) {
    const now = this.#now();
    const capture = ts / 1000;
    if (now - capture < 0 || now - capture > 10_000) return;
    this.#out.set(ts, { capture, sent: now });
  }

  /// The client drew every frame up to `ts`; `rtt`: the link's quickest round trip (ms), the way back its half.
  acked(ts: number, rtt: number) {
    const now = this.#now();
    let newest: { capture: number; sent: number } | null = null;
    for (const [t, f] of this.#out) {
      if (t > ts) continue;
      if (t === ts) newest = f;
      this.#out.delete(t);
    }
    if (newest === null) return;
    this.#samples.push({ at: now, frame: Math.max(0, now - rtt / 2 - newest.capture), before: newest.sent - newest.capture });
    while (this.#samples.length > 0 && this.#samples[0]!.at < now - LATENCY_WINDOW_MS) this.#samples.shift();
  }

  /// What to say now (once each LATENCY_EVERY_MS, when there are frames to say it of): the medians, in whole ms.
  take(): { frame: number; before: number } | null {
    const now = this.#now();
    // A still screen sends nothing: what is older than the window is not said again.
    while (this.#samples.length > 0 && this.#samples[0]!.at < now - LATENCY_WINDOW_MS) this.#samples.shift();
    if (this.#samples.length === 0 || now - this.#said < LATENCY_EVERY_MS) return null;
    this.#said = now;
    const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]!;
    return { frame: Math.round(median(this.#samples.map((s) => s.frame))), before: Math.round(median(this.#samples.map((s) => s.before))) };
  }
}
