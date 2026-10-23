// A view's pace (mesh/screen-pace.ts, docs/remote-screens.md "Pace"): which frames may go, and the bit rate its source
// is asked for, from the acknowledgements alone, on a clock the test moves.
import assert from "node:assert/strict";
import { test } from "node:test";
import { DOWN, DOWNSIZE_MS, DOWNSIZE_SHARE, HOLD_MS, LOW_BOUNDS, MAX_UNACKED, MIN_RATE, Pacer, QUEUE_MS, START_RATE, START_UNACKED, START_UP, Sizer, UP, UPSIZE_MS, UP_AFTER_MS, UP_EVERY_MS, ownRate } from "../src/mesh/screen-pace.ts";

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
});

test("the bit rate: down to what went through once a queue stays, not for a loss's moment; up again a step at a time", () => {
  const p = paced();
  const own = ownRate(1920, 1080);
  p.pacer.ceiling(own);
  assert.equal(p.pacer.rate(), own);
  // A steady 20 ms link, a frame each 16 ms of 10 kB: 5 Mbit/s goes through.
  let t = 0;
  const step = (trip: number) => {
    p.at(t);
    const [ts] = p.send(1);
    t += trip;
    p.at(t);
    if (ts !== undefined) p.pacer.acked(ts);
    t += 16 - trip > 0 ? 16 - trip : 0;
  };
  for (let i = 0; i < 100; i++) step(20);
  assert.equal(p.pacer.rate(), own, "nothing queues: as it was");
  // One frame held a round trip (a packet lost and sent again): not slower.
  step(60);
  assert.equal(p.pacer.rate(), own);
  // Frames held for longer than two round trips and HOLD_MS: the link is slower than they are.
  const from = t;
  while (t - from <= Math.max(HOLD_MS, 40) + 40) step(60);
  const down = p.pacer.rate()!;
  assert.ok(down < own, "lower");
  assert.ok(down <= 5_000_000 * DOWN + 1 && down >= MIN_RATE, `about what went through: ${down}`);
  // Nothing queues for UP_AFTER_MS: up by UP each UP_EVERY_MS, no higher than its own.
  const quiet = t;
  while (t - quiet < UP_AFTER_MS) step(20);
  const before = p.pacer.rate()!;
  const up = t;
  while (t - up < UP_EVERY_MS + 20) step(20);
  assert.ok(Math.abs(p.pacer.rate()! - Math.min(own, before * UP)) < 1, `${p.pacer.rate()} after ${before}`);
  for (let i = 0; i < 2000; i++) step(20);
  assert.equal(p.pacer.rate(), own);
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
  // A view asked no larger than the small bounds is never made smaller.
  const phone = new Sizer(() => now, { maxWidth: 1280, maxHeight: 720 });
  for (let i = 0; i < 100; i++, now += 100) assert.equal(phone.step(MIN_RATE, MIN_RATE, small), null);
});
