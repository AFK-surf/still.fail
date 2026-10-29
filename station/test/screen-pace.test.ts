// A view's pace (mesh/screen-pace.ts, docs/remote-screens.md "Pace"): which frames may go, and the bit rate its source
// is asked for, from the acknowledgements alone, on a clock the test moves.
import assert from "node:assert/strict";
import { test } from "node:test";
import { CUT, DOWN, DOWNSIZE_MS, FPS_CHOICES, FrameLatency, LoopStall, DOWNSIZE_SHARE, LOW_BOUNDS, MAX_RATE, MAX_UNACKED, MIN_RATE, Pacer, QUEUE_MS, START_RATE, START_UNACKED, START_UP, Sizer, UPSIZE_MS, UP_AFTER_MS, UP_EVERY_MS, ownRate, queueMs, rateCeiling } from "../src/mesh/screen-pace.ts";

function paced() {
  let now = 0;
  const pacer = new Pacer(() => now);
  let ts = 0;
  return {
    pacer,
    at: (ms: number) => void (now = ms),
    /// Frames sent while the pacer lets them (at most `n`), each `bytes` long: their timestamps.
    send(n: number, bytes = 10_000): number[] {
      const sent: number[] = [];
      for (let i = 0; i < n && pacer.may(); i++) {
        ts += 1000;
        pacer.sent(ts, bytes);
        sent.push(ts);
      }
      return sent;
    },
  };
}

/// Frames offered each 16 ms for `ms` over a link that decodes each `trip` ms after it went: how many went.
function over(trip: number, ms: number): number {
  const p = paced();
  const due: { at: number; ts: number }[] = [];
  let went = 0;
  for (let t = 0; t < ms; t++) {
    p.at(t);
    while (due.length > 0 && due[0]!.at <= t) p.pacer.acked(due.shift()!.ts);
    if (t % 16 === 0) for (const ts of p.send(1)) (went++, due.push({ at: t + trip, ts }));
  }
  return went;
}

test("a far link carries as many frames as a near one: they go while the oldest waits no longer than the round trip", () => {
  const near = over(20, 2000);
  const far = over(150, 2000);
  assert.ok(near >= 120, `near: ${near}`);
  assert.ok(far >= near - 12, `far: ${far} of ${near}`);
  // Two before the round trip is known, then as many as the link holds.
  const p = paced();
  assert.equal(p.send(10).length, START_UNACKED);
});

test("a queue building stops the frames until an acknowledgement", () => {
  const p = paced();
  p.send(1);
  p.at(20);
  p.pacer.acked(1000);
  assert.equal(p.pacer.rtt(), 20);
  p.send(3);
  assert.equal(p.pacer.unacked, 3);
  // The oldest has waited the round trip and QUEUE_MS: none more.
  p.at(20 + 20 + QUEUE_MS);
  assert.equal(p.pacer.may(), true);
  p.at(20 + 20 + QUEUE_MS + 1);
  assert.equal(p.pacer.may(), false);
  p.pacer.acked(4000);
  assert.equal(p.pacer.may(), true);
  // A far link's round trip varies more: half of it, where that is more than QUEUE_MS.
  assert.equal(queueMs(20), QUEUE_MS);
  assert.equal(queueMs(150), 75);
});

/// A source at 60 frames a second over a link that carries `capacity()` bits a second (each frame decoded once it is
/// through, after `base` ms more), each frame as large as the rate the pacer asks makes it: the pacer's rate each ms.
function bottleneck(capacity: (t: number) => number, ms: number, base = 10, start: number | null = null, own = ownRate(1920, 1080)) {
  let now = 0;
  const pacer = new Pacer(() => now, start);
  pacer.ceiling(own);
  const due: { at: number; ts: number }[] = [];
  let free = 0;
  let ts = 0;
  const rates: number[] = [];
  for (let t = 0; t < ms; t++) {
    now = t;
    while (due.length > 0 && due[0]!.at <= t) pacer.acked(due.shift()!.ts);
    if (t % 16 === 0 && pacer.may()) {
      const bytes = Math.round(pacer.rate()! / 60 / 8);
      ts += 1000;
      pacer.sent(ts, bytes);
      free = Math.max(free, t) + (bytes * 8 * 1000) / capacity(t);
      due.push({ at: Math.ceil(free) + base, ts });
    }
    rates.push(pacer.rate()!);
  }
  return rates;
}

test("the bit rate: down towards what went through once frames stay held back, never below half at a time; up again a step at a time", () => {
  const own = ownRate(1920, 1080);
  // A link that carries 5 Mbit/s for 4 s, then 100.
  const rates = bottleneck((t) => (t < 4000 ? 5_000_000 : 100_000_000), 20_000);
  const low = Math.min(...rates.slice(0, 4000));
  assert.ok(low < 5_000_000, `lowered to under the link: ${low}`);
  assert.ok(low >= 5_000_000 * DOWN * 0.5, `about what went through: ${low}`);
  // Each cut at most halves it.
  for (let t = 1; t < rates.length; t++) assert.ok(rates[t]! >= rates[t - 1]! * CUT - 1, `at ${t}: ${rates[t - 1]} to ${rates[t]}`);
  // The link wide again: up by UP each UP_EVERY_MS once nothing queued for UP_AFTER_MS, to its own.
  assert.equal(rates.at(-1), own);
  const rising = rates.slice(4000).findIndex((r, i, a) => i > 0 && r > a[i - 1]!);
  assert.ok(rising >= 0 && rising <= UP_AFTER_MS + 2 * UP_EVERY_MS, `up again after ${rising} ms`);
});

test("a late acknowledgement alone lowers nothing: a still or idle screen's frames, held back by none", () => {
  let now = 0;
  const pacer = new Pacer(() => now);
  const own = ownRate(1920, 1080);
  pacer.ceiling(own);
  let ts = 1000;
  pacer.sent(ts, 10_000);
  now = 20;
  pacer.acked(ts);
  // A frame now and then (a sharper picture of a still screen, a cursor's blink), each large and a while on the way.
  for (let i = 0; i < 20; i++) {
    now += 1000;
    assert.equal(pacer.may(), true);
    pacer.sent((ts += 1000), 300_000);
    now += 400;
    pacer.acked(ts);
  }
  assert.equal(pacer.rate(), own);
  // A frame held a round trip (a packet lost and sent again) while the next waits: not slower either.
  pacer.sent((ts += 1000), 10_000);
  now += pacer.rtt()! + queueMs(pacer.rtt()!) + 1;
  assert.equal(pacer.may(), false);
  pacer.acked(ts);
  assert.equal(pacer.rate(), own);
});

test("a view starting at START_RATE goes up by START_UP a step until a queue first builds, then by UP", () => {
  let now = 0;
  const pacer = new Pacer(() => now, START_RATE);
  pacer.ceiling(ownRate(1920, 1080));
  assert.equal(pacer.rate(), START_RATE);
  let ts = 0;
  const frame = (trip: number) => {
    ts += 1000;
    pacer.sent(ts, 10_000);
    now += trip;
    pacer.acked(ts);
  };
  frame(20);
  assert.equal(pacer.rate(), START_RATE * START_UP, "the first round trip: up at once");
  now += UP_EVERY_MS;
  frame(20);
  assert.equal(pacer.rate(), Math.min(ownRate(1920, 1080), START_RATE * START_UP * START_UP));
  // Smaller than the own: as the picture's size has it.
  const small = new Pacer(() => now, START_RATE);
  small.ceiling(ownRate(640, 360));
  assert.equal(small.rate(), 1_000_000);
});

test("a picture's size sets the most it is asked; none before it is known", () => {
  const p = paced();
  assert.equal(p.pacer.rate(), null);
  p.pacer.ceiling(ownRate(1280, 720));
  assert.equal(p.pacer.rate(), Math.max(1_000_000, 1280 * 720 * 3));
  p.pacer.ceiling(ownRate(640, 360));
  assert.equal(p.pacer.rate(), 1_000_000);
});

test("the picture made smaller while the link carries a quarter of its own rate and the source uses it; back once the smaller one's own goes through", () => {
  let now = 0;
  const sizer = new Sizer(() => now, { maxWidth: 1920, maxHeight: 1080 });
  const big = { width: 1920, height: 1080 }, small = { width: 1280, height: 720 };
  const low = ownRate(1920, 1080) * DOWNSIZE_SHARE - 1;
  // Low, but the screen changes little (a tenth of it used): not made smaller.
  for (; now <= DOWNSIZE_MS * 2; now += 100) assert.equal(sizer.step(low, low / 10, big), null);
  // Low and used: smaller once it stays so for DOWNSIZE_MS.
  let asked = null;
  for (const start = now; now <= start + DOWNSIZE_MS && asked === null; now += 100) asked = sizer.step(low, low, big);
  assert.deepEqual(asked, LOW_BOUNDS);
  assert.equal(sizer.low, true);
  // The small one's own goes through for UPSIZE_MS: its own size again.
  asked = null;
  for (const start = now; now <= start + UPSIZE_MS + 100 && asked === null; now += 100) asked = sizer.step(ownRate(1280, 720), ownRate(1280, 720), small);
  assert.deepEqual(asked, { maxWidth: 1920, maxHeight: 1080 });
  // 原画 is never made smaller.
  const whole = new Sizer(() => now, { maxWidth: 7680, maxHeight: 4320 }, "original");
  for (let i = 0; i < 100; i++, now += 100) assert.equal(whole.step(low, low, big), null);
  // A view asked no larger than the small bounds is never made smaller.
  const phone = new Sizer(() => now, { maxWidth: 1280, maxHeight: 720 });
  for (let i = 0; i < 100; i++, now += 100) assert.equal(phone.step(MIN_RATE, MIN_RATE, small), null);
});

test("frame latency: capture to drawn (the acknowledgement less half the round trip) and capture to sent, as medians, once a second", () => {
  let now = 10_000;
  const latency = new FrameLatency(() => now);
  // Captured at 9 990 ms, sent at 10 000 ms, acknowledged at 10 060 with a 40 ms round trip: drawn at about 10 040.
  latency.sent(9_990_000);
  now = 10_060;
  latency.acked(9_990_000, 40);
  assert.deepEqual(latency.take(), { frame: 50, before: 10 });
  // Said once a second at most.
  latency.sent(10_050_000);
  now = 10_100;
  latency.acked(10_050_000, 40);
  assert.equal(latency.take(), null);
  now = 11_100;
  assert.deepEqual(latency.take(), { frame: 50, before: 10 }, "the median of the two");
  // A timestamp not on this clock (10 s off) is not counted.
  latency.sent(1_000);
  now = 12_200;
  latency.acked(1_000, 40);
  assert.equal(latency.take(), null);
});

test("the most a view is asked at goes by its 画质: 原画 × 8 a pixel, 高清 × 4, at most MAX_RATE; else the source's own", () => {
  assert.equal(rateCeiling(1920, 1080), ownRate(1920, 1080));
  assert.equal(rateCeiling(1920, 1080, "smooth"), ownRate(1920, 1080));
  assert.equal(rateCeiling(1920, 1080, "hd"), 1920 * 1080 * 4);
  assert.equal(rateCeiling(1920, 1080, "original"), 1920 * 1080 * 8);
  assert.equal(rateCeiling(3840, 2160, "original"), MAX_RATE);
  // A small picture's own (at least 1 Mbit/s) is never lowered.
  assert.equal(rateCeiling(320, 200, "original"), 1_000_000);
});

/// Frames offered every `every` ms (each acknowledged `trip` ms after it went) for `ms`, to a pacer asked `fps`: when
/// each went.
function capped(fps: number | undefined, every: number, ms: number, trip = 5): number[] {
  let now = 0;
  const pacer = new Pacer(() => now, null, fps);
  const due: { at: number; ts: number }[] = [];
  const went: number[] = [];
  let ts = 0;
  for (let t = 0; t < ms; t += 0.25) {
    now = t;
    while (due.length > 0 && due[0]!.at <= t) pacer.acked(due.shift()!.ts);
    if (t % every < 0.25 && pacer.may() && pacer.wait() === 0) {
      pacer.sent((ts += 1000), 10_000);
      went.push(t);
      due.push({ at: t + trip, ts });
    }
  }
  return went;
}

test("a 帧率 asked: no second carries more frames than it (and one), and a source at that rate keeps it", () => {
  for (const fps of FPS_CHOICES) {
    // A source faster than any asked (a 240 Hz display's).
    const went = capped(fps, 1000 / 240, 5000);
    for (let i = 0; i < went.length; i++) {
      const within = went.slice(i).filter((t) => t < went[i]! + 1000).length;
      assert.ok(within <= fps + 1, `${fps}: ${within} in the second from ${went[i]}`);
    }
    assert.ok(went.length >= fps * 5 * 0.95, `${fps}: ${went.length} in 5 s`);
  }
  // A source at the rate asked (still.fail Helper's capture asked it, its frames a little early or late): all of them.
  assert.ok(capped(60, 1000 / 60, 2000).length >= 119);
  // None asked (自动): as many as come.
  assert.equal(new Pacer(() => 0).wait(), 0);
  assert.ok(capped(undefined, 1000 / 240, 1000).length >= 239);
});

test("the station's loop standing still is left out of round trips and waits: frames held by it lower nothing", () => {
  // Frames each 16 ms over a near link (acknowledged 30 ms after they went), the station's loop standing still 128 ms
  // every 640 ms (nothing read meanwhile; then the pump asks before the acknowledgements are read): told, the rate stays
  // its own; not told, it is taken for the link.
  const run = (told: boolean) => {
    let now = 0;
    let stood = 0;
    const pacer = new Pacer(() => now, null, undefined, told ? () => stood : () => 0);
    pacer.ceiling(ownRate(1920, 1080));
    const due: { at: number; ts: number }[] = [];
    let ts = 0;
    for (let t = 0; t < 20_000; t++) {
      now = t;
      if (t % 640 >= 512) continue;
      if (t % 640 === 0 && t > 0) stood += 128;
      if (t % 16 === 0 && pacer.may()) {
        ts += 1000;
        pacer.sent(ts, 2_000);
        due.push({ at: t + 30, ts });
      }
      while (due.length > 0 && due[0]!.at <= t) pacer.acked(due.shift()!.ts);
    }
    return pacer.rate()!;
  };
  assert.equal(run(true), ownRate(1920, 1080));
  assert.ok(run(false) < ownRate(1920, 1080) / 2, `not told, taken for the link: ${run(false)}`);
});

test("LoopStall counts how long the loop stood still past its tick, the stand it is in now too", () => {
  let now = 0;
  const stall = new LoopStall(() => now);
  const used = stall.use();
  assert.equal(used.stalled(), 0);
  now = 100;
  assert.equal(used.stalled(), 90);
  used.done();
});
