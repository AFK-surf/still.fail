// The Rust core's pill.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { BACK_MS, BUSY_MS, Timing, nothing, raw } from "../src/pill.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const link = (tone: string) => ({ tone, text: `${tone} 「studio」` });
const tone = (v: J) => v.tone ?? null;

test("coming_back_shows_once_it_lasted_and_back_only_after_that", () => {
  const t = new Timing();
  const busy = () => raw(link("busy"), null);
  assert.deepEqual(t.step(0, busy()), [nothing(), BUSY_MS]);
  assert.equal(tone(t.step(1_000, busy())[0]), null);
  assert.deepEqual(t.step(1_200, null), [nothing(), null]);
  t.step(2_000, busy());
  assert.equal(tone(t.step(3_500, busy())[0]), "busy");
  const [back, again] = t.step(4_000, null);
  assert.deepEqual([tone(back), again], ["back", BACK_MS]);
  assert.equal(tone(t.step(5_000, null)[0]), "back");
  assert.deepEqual(t.step(5_500, null), [nothing(), null]);
});

test("trouble_and_what_the_status_says_show_at_once", () => {
  let t = new Timing();
  const [shown, again] = t.step(0, raw(link("trouble"), null));
  assert.deepEqual([tone(shown), again], ["trouble", null]);
  assert.equal(tone(t.step(100, raw(link("busy"), null))[0]), "busy");
  assert.equal(tone(t.step(200, null)[0]), "back");
  t = new Timing();
  const slow = { state: "slow", text: "studio 读取对话 · 2 秒", items: [{ state: "slow", text: "studio 读取对话", detail: "已等 2 秒" }] };
  const [s] = t.step(0, raw(null, slow));
  assert.deepEqual([tone(s), s.items[0].text], ["busy", "studio 读取对话"]);
  assert.equal(raw(null, { state: null, text: null, items: [] }), null);
});
