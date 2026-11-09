// What the station knows of models (accounts/models.ts): which read images, and the outdated models a profile names
// unchecked once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { lineOf, newerOf, seesImages, VISION, uncheckOutdated } from "../src/accounts/models.ts";
import { modelKey } from "../src/read/usage.ts";

test("a model that reads images is known however it is spelled; one that was not checked is not", () => {
  for (const m of ["deepseek-v4.1-flash", "openrouter/deepseek-v4.1-flash", "claude-haiku-5-5", "anthropic/claude-opus-5-5-20261001", "kimi-k3[1m]"]) assert.ok(seesImages(m), m);
  for (const m of ["deepseek-v4-pro", "glm-5.3", "qwen3.7-max", "longcat-2.0", "kimi-k2.6"]) assert.ok(!seesImages(m), m);
});

test("the vision table lists models by key", () => {
  for (const key of VISION) assert.equal(modelKey(key), key);
});

test("a model's line and version are read from its name, however it is spelled", () => {
  const cases: [string, string, number[]][] = [
    ["claude-fable-5-1", "claude-fable", [5, 1]],
    ["anthropic/claude-opus-4-5-20251101", "claude-opus", [4, 5]],
    ["claude-3-5-sonnet", "claude-sonnet", [3, 5]],
    ["claude-opus-4-6[1m]", "claude-opus", [4, 6]],
    ["openai/gpt-6.1-sol", "gpt-sol", [6, 1]],
    ["gpt-5.6-terra", "gpt-terra", [5, 6]],
    ["kimi-k3", "kimi-k", [3]],
    ["deepseek-v4.1-flash", "deepseek-v-flash", [4, 1]],
    // A snapshot's stamp is not a version.
    ["deepseek-v4-flash-0731", "deepseek-v-flash", [4]],
    ["o4-mini", "o-mini", [4]],
    ["grok-imagine-video-1.5", "grok-imagine-video", [1, 5]],
  ];
  for (const [model, line, version] of cases) assert.deepEqual(lineOf(model), { line, version }, model);
});

test("the newer model of a line is the newest offered, in the context it was named in; none of another line or a snapshot", () => {
  const offered = ["claude-fable-5", "claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "gpt-6.1-sol", "grok-4.6", "deepseek-v4-flash-0731"];
  assert.equal(newerOf("claude-fable-5-1", offered), "claude-fable-5-2");
  assert.equal(newerOf("claude-opus-4-6[1m]", offered), "claude-opus-5-5[1m]");
  assert.equal(newerOf("anthropic/claude-3-5-sonnet-20241022", offered), "claude-sonnet-5-5");
  assert.equal(newerOf("openai/gpt-6-sol", offered), "gpt-6.1-sol");
  assert.equal(newerOf("claude-fable-5-2", offered), null);
  assert.equal(newerOf("claude-haiku-4-5", offered), null);
  assert.equal(newerOf("gpt-6-astra", offered), null);
  assert.equal(newerOf("grok-imagine-video-1.5", offered), null);
  assert.equal(newerOf("deepseek-v4-flash", offered), null);
});

test("outdated models are unchecked once, each replaced by the newest of its line the profile is offered", () => {
  const raw: any = {
    profiles: [
      // Its default follows the one it named.
      { id: "a", home: "homes/a", access: { kind: "subscription" }, model: "claude-fable-5-1", models: ["claude-opus-4-6", "claude-sonnet-5-5", "claude-haiku-4-5-20251001", "claude-fable-5-1"] },
      // Its newer one ticked already; one with none newer, which its key's list does not name: kept.
      { id: "b", home: "homes/b", models: ["gpt-6-sol", "gpt-6.1-sol", "gpt-5.6-terra", "gpt-6-astra"] },
      // Its check does not list a newer one (maybe not yet): left until one does.
      { id: "later", home: "homes/later", access: { kind: "subscription" }, models: ["claude-sonnet-4-6", "claude-opus-5-5"] },
      // A subscription whose account no longer runs it: unchecked, unless it is all the profile has.
      { id: "gone", home: "homes/gone", access: { kind: "subscription" }, models: ["gpt-5.6-terra", "gpt-6.1-sol"] },
      { id: "only", home: "homes/only", access: { kind: "subscription" }, models: ["gpt-5.6-terra"] },
      // Another station's, changed there.
      { id: "lent", home: "homes/lent", models: ["claude-opus-5"], share: { borrowed: true } },
      // Unchecked here before and checked again by hand.
      { id: "again", home: "homes/again", models: ["claude-opus-4-8"] },
      { id: "none", home: "homes/none" },
    ],
    // A connect's model follows too; one nothing replaced is kept.
    connects: [{ id: "s", bind: { runtime: "claude", model: "claude-fable-5-1" } }, { id: "t", bind: { runtime: "codex", model: "gpt-5.6-terra" } }],
  };
  const found: Record<string, string[]> = {
    a: ["claude-haiku-5-5", "claude-opus-5-5", "claude-opus-4-6", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1"],
    later: ["claude-opus-5-5", "claude-sonnet-4-6"],
    gone: ["gpt-6.1-sol"],
    only: ["gpt-6.1-sol"],
    again: ["claude-opus-5-5"],
  };
  const { changes, unchecked } = uncheckOutdated(raw, (id) => found[id] ?? null, new Set(["claude-opus-4-8"]));
  assert.deepEqual(
    raw.profiles.map((p: any) => p.models),
    [
      ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5", "claude-fable-5-2"],
      ["gpt-6.1-sol", "gpt-5.6-terra", "gpt-6-astra"],
      ["claude-sonnet-4-6", "claude-opus-5-5"],
      ["gpt-6.1-sol"],
      ["gpt-5.6-terra"],
      ["claude-opus-5"],
      ["claude-opus-4-8"],
      undefined,
    ],
  );
  assert.deepEqual(changes, [
    { profile: "a", removed: ["claude-opus-4-6", "claude-haiku-4-5-20251001", "claude-fable-5-1"], added: ["claude-opus-5-5", "claude-haiku-5-5", "claude-fable-5-2"] },
    { profile: "b", removed: ["gpt-6-sol"], added: [] },
    { profile: "gone", removed: ["gpt-5.6-terra"], added: [] },
  ]);
  assert.equal(raw.profiles[0].model, "claude-fable-5-2");
  assert.deepEqual(raw.connects.map((c: any) => c.bind.model), ["claude-fable-5-2", "gpt-5.6-terra"]);
  assert.deepEqual([...unchecked].sort(), ["claude-fable-5-1", "claude-haiku-4-5", "claude-opus-4-6", "gpt-5.6-terra", "gpt-6-sol"]);
});
