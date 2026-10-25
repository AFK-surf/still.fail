import assert from "node:assert/strict";
import { test } from "node:test";
import { springStep } from "../web/ui/src/spring.ts";
import { GestureVelocity, latestFrame } from "../web/ui/src/frames.ts";

test("springs preserve position and release velocity across refresh rates and missed frames", () => {
  for (const damping of [17, 2 * Math.sqrt(300), 60]) {
    const expected = springStep(0, 120, 180, 300, damping, 0.5);
    for (const steps of [Array(30).fill(1 / 60), Array(60).fill(1 / 120), [0.1, 0.03, 0.17, 0.2]]) {
      let at = { value: 0, velocity: 120 };
      for (const dt of steps) at = springStep(at.value, at.velocity, 180, 300, damping, dt);
      assert(Math.abs(at.value - expected.value) < 1e-8);
      assert(Math.abs(at.velocity - expected.velocity) < 1e-8);
    }
    const resumed = springStep(0, 120, 180, 300, damping, 60);
    assert(Math.abs(resumed.value - 180) < 0.01);
    assert(Math.abs(resumed.velocity) < 0.01);
  }
});

test("gesture frames coalesce samples, flush the release endpoint and discard cancelled work", () => {
  const request = globalThis.requestAnimationFrame, cancel = globalThis.cancelAnimationFrame;
  const frames = new Map<number, FrameRequestCallback>();
  let id = 0;
  globalThis.requestAnimationFrame = callback => { frames.set(++id, callback); return id; };
  globalThis.cancelAnimationFrame = id => { frames.delete(id); };
  try {
    const drawn: number[] = [], task = latestFrame<number>(value => drawn.push(value));
    for (let n = 0; n < 200; n++) task.set(n);
    assert.equal(frames.size, 1);
    assert.deepEqual(drawn, []);
    for (const callback of frames.values()) callback(16);
    assert.deepEqual(drawn, [199]);
    task.set(210); task.flush();
    assert.deepEqual(drawn, [199, 210]);
    assert.equal(frames.size, 0, "release owns the last pending point, with no callback left to overwrite the spring");
    task.set(220); task.cancel();
    assert.equal(frames.size, 0);
    task.flush();
    assert.deepEqual(drawn, [199, 210]);
  } finally { globalThis.requestAnimationFrame = request; globalThis.cancelAnimationFrame = cancel; }
});

test("release speed ignores a long initial hold and expires after holding still", () => {
  const speed = new GestureVelocity();
  speed.reset(0, 0); speed.push(10, 1000); speed.push(70, 1050);
  assert.equal(speed.speed(1050), 1200);
  assert.equal(speed.speed(1200), 0);
  speed.push(70, 1200);
  assert.equal(speed.speed(1200), 0);
  speed.reset(0, 1300); speed.push(-30, 1350);
  assert.equal(speed.speed(1350), -600);
});
