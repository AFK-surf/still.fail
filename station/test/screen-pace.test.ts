// A view's pace (mesh/screen-pace.ts, docs/remote-screens.md "Pace"): which frames may go, and the bit rate its source
// is asked for, from the acknowledgements alone, on a clock the test moves.
import assert from "node:assert/strict";
import { test } from "node:test";
import { DOWN, HOLD_MS, MAX_UNACKED, MIN_RATE, Pacer, QUEUE_MS, START_UNACKED, UP, UP_AFTER_MS, UP_EVERY_MS, ownRate } from "../src/mesh/screen-pace.ts";

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

test("a picture's size sets the most it is asked; none before it is known", () => {
  const p = paced();
  assert.equal(p.pacer.rate(), null);
  p.pacer.ceiling(ownRate(1280, 720));
  assert.equal(p.pacer.rate(), Math.max(1_000_000, 1280 * 720 * 3));
  p.pacer.ceiling(ownRate(640, 360));
  assert.equal(p.pacer.rate(), 1_000_000);
});
