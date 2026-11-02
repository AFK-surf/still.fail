// What the station knows of models (accounts/models.ts): which read images, and the known outdated models a profile
// names unchecked once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { OUTDATED, outdated, replacement, seesImages, VISION, uncheckOutdated } from "../src/accounts/models.ts";
import { modelKey } from "../src/read/usage.ts";

test("a model that reads images is known however it is spelled; one that was not checked is not", () => {
  for (const m of ["deepseek-v4.1-flash", "openrouter/deepseek-v4.1-flash", "claude-haiku-5-5", "anthropic/claude-opus-5-5-20261001", "kimi-k3[1m]"]) assert.ok(seesImages(m), m);
  for (const m of ["deepseek-v4-pro", "glm-5.3", "qwen3.7-max", "longcat-2.0", "kimi-k2.6"]) assert.ok(!seesImages(m), m);
});

test("the vision table lists models by key", () => {
  for (const key of VISION) assert.equal(modelKey(key), key);
});

test("a model is outdated however it is spelled, and what replaced it is the newest of its line", () => {
  for (const m of ["claude-opus-4-5-20251101", "anthropic/claude-sonnet-4-5", "claude-opus-4-6[1m]", "openai/gpt-5.6-sol", "gpt-6-sol"]) assert.ok(outdated(m), m);
  for (const m of ["claude-opus-5-5", "claude-haiku-5-5", "claude-fable-5-1", "gpt-6.1-sol", "gpt-6-astra", "deepseek-v4-pro"]) assert.ok(!outdated(m), m);
  assert.equal(replacement("claude-opus-4-5-20251101"), "claude-opus-5-5");
  assert.equal(replacement("claude-opus-4-6[1m]"), "claude-opus-5-5[1m]");
  assert.equal(replacement("claude-haiku-4-5-20251001"), "claude-haiku-5-5");
  assert.equal(replacement("openai/gpt-5.6-sol"), "gpt-6.1-sol");
  assert.equal(replacement("gpt-5.6-terra"), null, "GPT-6 has no Terra");
  assert.equal(replacement("claude-opus-5-5"), null);
});

test("the table lists models by key, and each of its lines ends", () => {
  for (const [key, first] of OUTDATED) {
    assert.equal(modelKey(key), key);
    const seen = new Set([key]);
    for (let next = first; typeof next === "string" && OUTDATED.has(next); next = OUTDATED.get(next)!) {
      assert.ok(!seen.has(next), `${key}'s line comes back to ${next}`);
      seen.add(next);
    }
  }
});

test("known outdated models are unchecked once, each replaced by what came after it", () => {
  const raw: any = {
    profiles: [
      { id: "a", home: "homes/a", models: ["claude-opus-4-6", "claude-sonnet-5-5", "claude-haiku-4-5-20251001"] },
      // Its replacement enabled already; one nothing replaced.
      { id: "b", home: "homes/b", models: ["gpt-6-sol", "gpt-6.1-sol", "gpt-5.6-terra", "gpt-6-astra"] },
      // Its check does not list what replaced it (maybe not yet): left for a later start.
      { id: "later", home: "homes/later", models: ["claude-sonnet-4-6", "claude-opus-5-5"] },
      // Nothing replaced it and it is all the profile has: kept, or the profile would serve no chat.
      { id: "only", home: "homes/only", models: ["gpt-5.6-terra"] },
      // Another station's, changed there.
      { id: "lent", home: "homes/lent", models: ["claude-opus-5"], share: { borrowed: true } },
      // Unchecked here before and checked again by hand.
      { id: "again", home: "homes/again", models: ["claude-opus-4-8"] },
      { id: "none", home: "homes/none" },
    ],
  };
  const found: Record<string, string[]> = {
    a: ["claude-haiku-5-5", "claude-opus-5-5", "claude-opus-4-6", "claude-sonnet-5-5"],
    later: ["claude-opus-5-5", "claude-sonnet-4-6"],
    again: ["claude-opus-5-5"],
  };
  const { changes, deferred } = uncheckOutdated(raw, (id) => found[id] ?? null, new Set(["claude-opus-4-8"]));
  assert.deepEqual(
    raw.profiles.map((p: any) => p.models),
    [
      ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"],
      ["gpt-6.1-sol", "gpt-6-astra"],
      ["claude-sonnet-4-6", "claude-opus-5-5"],
      ["gpt-5.6-terra"],
      ["claude-opus-5"],
      ["claude-opus-4-8"],
      undefined,
    ],
  );
  assert.deepEqual(changes, [
    { profile: "a", removed: ["claude-opus-4-6", "claude-haiku-4-5-20251001"], added: ["claude-opus-5-5", "claude-haiku-5-5"] },
    { profile: "b", removed: ["gpt-6-sol", "gpt-5.6-terra"], added: [] },
  ]);
  assert.deepEqual([...deferred], ["claude-sonnet-4-6"]);
});
