// What a chat an agent opens runs when it names no model (sessions/model-choice.ts): the starter's most used model on
// the station it is opened on, of those its profiles run; asked about when that is not one.
import assert from "node:assert/strict";
import { test } from "node:test";
import { hubConfig } from "../src/sessions/config.ts";
import { askWhich, candidates, choose } from "../src/sessions/model-choice.ts";

const profiles = (list: object[]) => hubConfig({ profiles: list }, "/nonexistent-model-choice").profiles;

// As Studio had them on 2026-10-19: two codex accounts on gpt-6-astra, and one on DeepSeek.
const studio = profiles([
  { id: "cx1", runtime: "codex", home: "h1", models: ["gpt-6-astra"] },
  { id: "cx2", runtime: "codex", home: "h2", models: ["gpt-6-astra"] },
  { id: "ds", runtime: "claude", home: "h3", models: ["deepseek-v4.1-flash"] },
]);

test("the models a station's profiles run, each once, of a runtime when one is named", () => {
  assert.deepEqual(candidates(studio, null), [
    { runtime: "codex", model: "gpt-6-astra" },
    { runtime: "claude", model: "deepseek-v4.1-flash" },
  ]);
  assert.deepEqual(candidates(studio, "codex"), [{ runtime: "codex", model: "gpt-6-astra" }]);
  assert.deepEqual(candidates(studio, "dsh"), []);
  // A profile that names no model runs its runtime's default.
  assert.deepEqual(candidates(profiles([{ id: "cc", runtime: "claude", home: "h" }]), null), [{ runtime: "claude", model: null }]);
});

test("the starter's most used model there is the one; another station's model the opener runs counts for nothing", () => {
  const cands = candidates(studio, null);
  const used = [
    { runtime: "codex", model: "gpt-6-astra", n: 12 },
    { runtime: "claude", model: "deepseek-v4.1-flash", n: 3 },
    // Chats that ran a model no profile here runs (the opener's Opus, which failed): not counted.
    { runtime: "claude", model: "claude-opus-5-5", n: 40 },
  ];
  assert.deepEqual(choose(cands, used), { pick: { runtime: "codex", model: "gpt-6-astra" } });
  // Spelled another way, the same model.
  assert.deepEqual(choose(cands, [{ runtime: "claude", model: "deepseek-v4.1-flash", n: 1 }]), { pick: { runtime: "claude", model: "deepseek-v4.1-flash" } });
});

test("one close to the most used, or none used with several to choose from: asked, not guessed", () => {
  const cands = candidates(studio, null);
  // Close: used more than half as often as the most used.
  const close = choose(cands, [
    { runtime: "codex", model: "gpt-6-astra", n: 3 },
    { runtime: "claude", model: "deepseek-v4.1-flash", n: 2 },
  ]);
  assert.ok("ask" in close);
  assert.deepEqual(close.ask.map((a) => [a.candidate.model, a.n]), [["gpt-6-astra", 3], ["deepseek-v4.1-flash", 2]]);
  // Twice as often: that one.
  assert.deepEqual(choose(cands, [{ runtime: "codex", model: "gpt-6-astra", n: 4 }, { runtime: "claude", model: "deepseek-v4.1-flash", n: 2 }]), { pick: { runtime: "codex", model: "gpt-6-astra" } });
  const tie = choose(cands, [
    { runtime: "codex", model: "gpt-6-astra", n: 4 },
    { runtime: "claude", model: "deepseek-v4.1-flash", n: 4 },
  ]);
  assert.ok("ask" in tie);
  assert.deepEqual(tie.ask.map((a) => [a.candidate.model, a.n]), [["gpt-6-astra", 4], ["deepseek-v4.1-flash", 4]]);
  // Most used first, whatever order the profiles are in.
  const second = choose(cands, [{ runtime: "codex", model: "gpt-6-astra", n: 2 }, { runtime: "claude", model: "deepseek-v4.1-flash", n: 3 }]);
  assert.ok("ask" in second && second.ask[0]!.candidate.model === "deepseek-v4.1-flash");
  const none = choose(cands, []);
  assert.ok("ask" in none && none.ask.length === 2);
  const said = askWhich(none.ask, "Studio");
  assert.ok(said.includes("gpt-6-astra (runtime codex, not used in 30 days)") && said.includes("same key"), said);
  // Only one there: that one, used or not.
  assert.deepEqual(choose(candidates(studio, "codex"), []), { pick: { runtime: "codex", model: "gpt-6-astra" } });
});

test("none used: a profile's first model, not every model its check found", () => {
  // One Claude account that runs all its check found: never used, its own first model, no question.
  const one = hubConfig({ profiles: [{ id: "cc", runtime: "claude", home: "h", models: ["claude-opus-5-5"] }] }, "/nonexistent-model-choice", () => ["claude-haiku-5", "claude-sonnet-5"]).profiles;
  assert.deepEqual(candidates(one, null).map((c) => c.model), ["claude-opus-5-5", "claude-haiku-5", "claude-sonnet-5"]);
  assert.deepEqual(choose(candidates(one, null), [], candidates(one, null, true)), { pick: { runtime: "claude", model: "claude-opus-5-5" } });
  // Used: any it runs counts.
  assert.deepEqual(choose(candidates(one, null), [{ runtime: "claude", model: "claude-sonnet-5", n: 2 }], candidates(one, null, true)), { pick: { runtime: "claude", model: "claude-sonnet-5" } });
  // Two accounts never used: asked about their first models alone.
  const two = choose(candidates(studio, null), [], candidates(studio, null, true));
  assert.ok("ask" in two && two.ask.length === 2);
});

test("a chat that ran its runtime's default counts for a profile that names no model", () => {
  const cands = candidates(profiles([{ id: "cc", runtime: "claude", home: "h" }, { id: "cx", runtime: "codex", home: "h2" }]), null);
  assert.deepEqual(choose(cands, [{ runtime: "codex", model: "whatever-it-ran", n: 2 }, { runtime: "claude", model: null, n: 1 }]), { pick: { runtime: "codex", model: null } });
});
