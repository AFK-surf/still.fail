// How fast a view's frames go (docs/remote-screens.md, "Pace"): which may be sent now, and the bit rate its source is
// asked to encode at. Both from what the client's acknowledgements say of the link: how long a frame takes from sent to
// decoded (the round trip), and how much went through in the last second.
//
// Frames go while those on the way go through as fast as the link has gone lately: the oldest not acknowledged waiting
// no longer than the quickest round trip of the last RTT_WINDOW_MS and `queueMs` of it. A far link so carries as many
// frames a second as a near one. Once one waits longer a queue is building (a link slower than the frames, a packet lost
// and sent again): none goes until an acknowledgement, and once frames stay held back, the bit rate goes down to what
// went through (no lower than half of what it was at a time), so the frames that come next are as many and smaller
// rather than fewer and late. A screen that changes little holds nothing back, and an acknowledgement late alone (a
// large picture of a still screen) lowers nothing. It goes up again a step at a time while nothing
// is lowered, to the source's own. A view starts at START_RATE (its first frame, a whole picture, is its largest: on a
// narrow link one at the source's own rate held the view up for a second) and goes up by START_UP each step until it
// is first lowered.
import { wall } from "../ops/fibers.ts";

/// Frames sent and not acknowledged, at most: before the link's round trip is known, and however short it is.
export const START_UNACKED = 2;
export const MAX_UNACKED = 16;
/// How much longer than its quickest round trip the oldest frame not acknowledged may be waiting while the next goes:
/// the queue a view lets build in front of a link, no more: QUEUE_MS, or QUEUE_SHARE of the round trip where that is
/// more (a far link's round trip varies by more than a near one's).
export const QUEUE_MS = 30;
export const QUEUE_SHARE = 0.5;
export const queueMs = (rtt: number) => Math.max(QUEUE_MS, rtt * QUEUE_SHARE);
/// How long a round trip counts towards the quickest (the link changes: another way, a relay).
export const RTT_WINDOW_MS = 10_000;
/// What went through is counted over this long.
export const DELIVERY_WINDOW_MS = 1000;
/// The lowest bit rate asked; down to `DOWN` of what went through (and no lower than `CUT` of what it was) once frames
/// stayed held back for two round trips and `HOLD_MS` (a packet lost and sent again holds the frames behind it for
/// about a round trip, then they all come: that is not the link being too slow), and again each round trip and
/// `HOLD_MS` it stays; up by `UP` each `UP_EVERY_MS` once nothing queued for `UP_AFTER_MS`.
export const MIN_RATE = 300_000;
export const DOWN = 0.85;
export const CUT = 0.5;
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

/// The 画质 a view asks (the client's `quality`): none for 自动 or a client from before it.
export type Quality = "smooth" | "hd" | "original";
/// The most a view is asked at, whatever its 画质.
export const MAX_RATE = 60_000_000;
/// The most a picture of this size is asked at, by its 画质: 原画 its pixels × 8 a second, 高清 × 4 (at most MAX_RATE,
/// at least its own), else its own (`ownRate`). On a LAN a desktop's text at its own rate stays soft as it moves.
export function rateCeiling(width: number, height: number, quality?: Quality): number {
  const own = ownRate(width, height);
  const per = quality === "original" ? 8 : quality === "hd" ? 4 : 0;
  return per === 0 ? own : Math.max(own, Math.min(MAX_RATE, width * height * per));
}

/// The frame rates a view may ask (the client's `fps`, its 帧率): at most this many frames a second, fewer where the
/// link or the screen gives fewer. None asked (自动, or a client before it): as many as the source makes and the link
/// carries (still.fail Helper's 60 a second; stillfail-screen's as many as the display draws).
export const FPS_CHOICES = [120, 90, 60, 30, 15] as const;
export type Fps = (typeof FPS_CHOICES)[number];
export const isFps = (v: unknown): v is Fps => FPS_CHOICES.includes(v as Fps);

/// How long the station's own loop stood still (ms, in all, since it was first asked): a frame's round trip and the wait
/// of the oldest on the way are counted without it. A Mac host's loop stood still 40–140 ms every few seconds
/// (2026-10-29: busy with searches asked again and again) on a LAN of 4 ms and nothing lost: its frames' acknowledgements
/// were read that late, taken for frames held back by the link, and the rate went down to what the source made (a
/// screen changing little makes little), on to MIN_RATE and the picture to LOW_BOUNDS. A frame held at the client
/// (decoded slowly) or on the link (a queue, a packet lost) is held as before.
export const STALL_TICK_MS = 10;
export class LoopStall {
  #total = 0;
  #last = 0;
  #stop: (() => void) | null = null;
  #users = 0;
  readonly #now: () => number;
  constructor(now: () => number = () => hostNow()) {
    this.#now = now;
  }

  /// Counted while someone uses it (a view): the function says how long the loop stood still so far.
  use(): { stalled: () => number; done: () => void } {
    if (this.#users++ === 0) {
      this.#last = this.#now();
      this.#stop = wall.every(STALL_TICK_MS, () => this.#tick());
    }
    let done = false;
    return {
      stalled: () => this.stalled(),
      done: () => {
        if (done) return;
        done = true;
        if (--this.#users === 0 && this.#stop !== null) {
          this.#stop();
          this.#stop = null;
        }
      },
    };
  }

  /// How long it stood still so far, the stand it is in now (its tick not come yet) with it.
  stalled(): number {
    return this.#total + Math.max(0, this.#now() - this.#last - STALL_TICK_MS);
  }

  #tick() {
    const now = this.#now();
    this.#total += Math.max(0, now - this.#last - STALL_TICK_MS);
    this.#last = now;
  }
}
export const loopStall = new LoopStall();

export class Pacer {
  /// The frames sent and not acknowledged, oldest first: their timestamps, sizes, when they went and how long the
  /// loop had stood still by then.
  readonly #out: { ts: number; bytes: number; at: number; stall: number }[] = [];
  /// Round trips measured, oldest first.
  #trips: { at: number; ms: number }[] = [];
  /// The frames acknowledged lately: when, and their sizes.
  #through: { at: number; bytes: number }[] = [];
  /// The bit rate asked of the source, and the most it is asked (its own); null before its size is known.
  #rate: number | null = null;
  #ceiling: number | null = null;
  #down = -Infinity;
  #up = -Infinity;
  /// Since when frames have been held back (`may` said no, and again within UP_AFTER_MS and two round trips each time),
  /// or null; and when last.
  #since: number | null = null;
  #held = -Infinity;
  #first = Infinity;
  /// The 帧率 asked: ms between frames (none: as many as come), and when the next may go. Each frame takes the next
  /// slot of 1000/fps ms; one late by up to half a slot lets the next come that much sooner, so a source that makes
  /// frames at the same rate (still.fail Helper's capture, asked it) is not cut to fewer by the jitter of its frames,
  /// and no second carries more than fps + 1.
  readonly #gap: number | null;
  #due = -Infinity;
  readonly #now: () => number;
  readonly #stalled: () => number;
  /// `start`: the bit rate the source was opened at (none: its own); `fps`: the 帧率 asked (none: 自动); `stalled`: how
  /// long the station's loop stood still so far (LoopStall), left out of round trips and waits.
  constructor(now: () => number, start: number | null = null, fps?: number, stalled: () => number = () => 0) {
    this.#now = now;
    this.#stalled = stalled;
    this.#rate = start;
    this.#gap = fps !== undefined && fps > 0 ? 1000 / fps : null;
  }

  /// How long until the next frame may go by the 帧率 asked, in whole ms (0: now; none asked, always 0): a clock read in
  /// nanoseconds a hair short of the slot waits a ms, not 0 ms again and again.
  wait(): number {
    const left = this.#gap === null ? 0 : this.#due - this.#now();
    return left > 0 ? Math.ceil(left) : 0;
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
    const now = this.#now();
    this.#out.push({ ts, bytes, at: now, stall: this.#stalled() });
    if (this.#gap !== null) this.#due = Math.max(this.#due + this.#gap, now + this.#gap / 2);
  }

  /// The client decoded every frame up to `ts`; the newest of them gives a round trip.
  acked(ts: number) {
    const now = this.#now();
    let newest: { at: number; stall: number } | null = null;
    while (this.#out.length > 0 && this.#out[0]!.ts <= ts) {
      const f = this.#out.shift()!;
      this.#through.push({ at: now, bytes: f.bytes });
      newest = f;
    }
    if (newest === null) return;
    this.#first = Math.min(this.#first, now);
    while (this.#through.length > 0 && this.#through[0]!.at < now - DELIVERY_WINDOW_MS) this.#through.shift();
    const trip = Math.max(0, now - newest.at - (this.#stalled() - newest.stall));
    const base = this.rtt();
    this.#trips.push({ at: now, ms: trip });
    // The latest is kept however old: a still screen sends nothing for long.
    while (this.#trips.length > 1 && this.#trips[0]!.at < now - RTT_WINDOW_MS) this.#trips.shift();
    if (base !== null && trip > base + queueMs(base)) this.#queuing(now);
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
    const now = this.#now();
    const oldest = this.#out[0]!;
    const may = this.#out.length < MAX_UNACKED && now - oldest.at - (this.#stalled() - oldest.stall) <= rtt + queueMs(rtt);
    if (!may) {
      // A frame held back: the link carries less than the frames (an acknowledgement late alone, a screen still or
      // changing little, holds nothing back and lowers nothing).
      this.#since ??= now;
      this.#held = now;
      this.#queuing(now);
    }
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
    if (this.#since === null || this.#calm(now)) return;
    const rtt = this.rtt() ?? 0;
    if (this.#rate === null || now - this.#since < Math.max(HOLD_MS, 2 * rtt) || now - this.#down < rtt + HOLD_MS) return;
    // What went through is not known yet (the first frame, a whole picture, is most of it): nothing to go by.
    if (now - this.#first < MEASURED_MS) return;
    this.#down = now;
    const through = this.#delivered(now);
    if (through > 0) this.#rate = Math.max(MIN_RATE, Math.min(this.#rate, Math.max(this.#rate * CUT, through * DOWN)));
  }

  /// Nothing held back for UP_AFTER_MS and two round trips: the queue gone.
  #calm(now: number): boolean {
    if (now - this.#held <= Math.max(UP_AFTER_MS, 2 * (this.rtt() ?? 0))) return false;
    this.#since = null;
    return true;
  }

  #steady(now: number) {
    // Frames held back lately: as it is (the link carries no more than it goes at).
    if (this.#since !== null && !this.#calm(now)) return;
    if (this.#rate === null || this.#ceiling === null || this.#rate >= this.#ceiling) return;
    // Starting: never lowered yet. Up once it has not been lowered for UP_AFTER_MS (a frame held a moment by a packet
    // lost, which lowers nothing, holds nothing up).
    const starting = this.#down === -Infinity;
    if ((!starting && now - this.#down < UP_AFTER_MS) || now - this.#up < UP_EVERY_MS) return;
    this.#up = now;
    this.#rate = Math.min(this.#ceiling, this.#rate * (starting ? START_UP : UP));
  }
}

/// A still screen sends nothing (a source makes a picture only when the screen changed), so what is shown is the last
/// frame's picture, encoded at the rate asked then: a view's first at START_RATE, a whole screen in a few kilobytes,
/// stays a blur while nothing on it moves (on a Mac's desktop left alone, for minutes). Once no frame has gone for
/// STILL_MS and the rate the pace asks has gone up past SHARPER times the one the last frame was encoded at, the same
/// picture goes again as a key frame at it (the source's `keyframe`); its acknowledgement lets the rate go up again,
/// and so on to the source's own: the picture gets as sharp as the link carries a few steps after the screen stopped,
/// as a still image is refined. A screen that keeps changing never waits STILL_MS; a link that cannot carry it lowers
/// the rate, and nothing more is sent.
export const STILL_MS = 500;
export const SHARPER = 1.1;

/// When a still screen's picture is sent again sharper (STILL_MS, SHARPER).
export class Sharpener {
  #at = -Infinity;
  #rate: number | null = null;

  /// A frame went at `now`, encoded at `rate` (null: a source with no rate of its own, a JPEG's).
  sent(now: number, rate: number | null) {
    this.#at = now;
    this.#rate = rate;
  }

  /// How long until the screen has been still for STILL_MS (0: it has).
  left(now: number): number {
    return Math.max(0, this.#at + STILL_MS - now);
  }

  /// Whether the last frame's picture is to go again now, the pace asking `rate`.
  due(now: number, rate: number | null): boolean {
    return rate !== null && this.#rate !== null && this.left(now) === 0 && rate > this.#rate * SHARPER;
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
/// its own. Never smaller when the view asked 原画.
export class Sizer {
  readonly #now: () => number;
  #asked: { maxWidth: number; maxHeight: number };
  #low = false;
  #since: number | null = null;
  /// 原画 asked: the picture is never made smaller (a link that carries less gets fewer frames of it).
  readonly #whole: boolean;
  constructor(now: () => number, asked: { maxWidth: number; maxHeight: number }, quality?: Quality) {
    this.#now = now;
    this.#asked = asked;
    this.#whole = quality === "original";
  }

  get low(): boolean {
    return this.#low;
  }

  /// The bounds the view asks for now.
  get asked(): { maxWidth: number; maxHeight: number } {
    return { ...this.#asked };
  }

  /// The view asks for other bounds (a part of the screen, shown as large as the client has room for: a look): the
  /// bounds to ask of the source now, the smaller one's within them while the link carries little.
  ask(asked: { maxWidth: number; maxHeight: number }): { maxWidth: number; maxHeight: number } {
    this.#asked = { ...asked };
    this.#since = null;
    return this.bounds();
  }

  /// With the rate asked now, what went through, and the picture's size now: the bounds to ask for, when they change;
  /// else null.
  step(rate: number, through: number, size: { width: number; height: number }): { maxWidth: number; maxHeight: number } | null {
    // Asked no larger than the small one, or 原画: nothing to make smaller.
    if (this.#whole || (this.#asked.maxWidth <= LOW_BOUNDS.maxWidth && this.#asked.maxHeight <= LOW_BOUNDS.maxHeight)) return null;
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
    return this.bounds();
  }

  /// The bounds to ask of the source as things are: the view's, or the smaller one's within them.
  bounds(): { maxWidth: number; maxHeight: number } {
    const a = this.#asked;
    return this.#low ? { maxWidth: Math.min(a.maxWidth, LOW_BOUNDS.maxWidth), maxHeight: Math.min(a.maxHeight, LOW_BOUNDS.maxHeight) } : { ...a };
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
