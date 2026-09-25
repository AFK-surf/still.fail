import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { prepareCodexHome } from "../src/profiles.ts";
import { readUsage } from "../src/transcript.ts";

const parse = (profiles: unknown[]) => parseConfig({ profiles: profiles as never }, "/data");

test("an access kind derives the environment; hand-set variables win", () => {
  const [claude, codex] = parse([
    { id: "a", runtime: "claude", home: "h/a", access: { kind: "opencode-go", key: "k1" }, env: { ANTHROPIC_SMALL_FAST_MODEL: "mine" } },
    { id: "b", runtime: "codex", home: "h/b", access: { kind: "opencode-go", key: "k2" } },
  ]).profiles;
  assert.equal(claude!.env.ANTHROPIC_API_KEY, "k1");
  assert.equal(claude!.env.ANTHROPIC_BASE_URL, "https://opencode.ai/zen/go");
  assert.equal(claude!.env.ANTHROPIC_SMALL_FAST_MODEL, "mine");
  assert.deepEqual(claude!.customEnv, { ANTHROPIC_SMALL_FAST_MODEL: "mine" });
  assert.deepEqual(codex!.env, { OPENCODE_GO_KEY: "k2", OPENCODE_SESSION: "ember-{route}" });
});

test("profiles without access keep their raw environment", () => {
  const [p] = parse([{ id: "a", runtime: "claude", home: "h", env: { X: "1" } }]).profiles;
  assert.deepEqual(p!.access, { kind: "env", key: "" });
  assert.deepEqual(p!.env, { X: "1" });
});

test("access kinds are checked against the runtime and need their key", () => {
  assert.throws(() => parse([{ id: "a", runtime: "codex", home: "h", access: { kind: "anthropic-api", key: "k" } }]), /cannot use access anthropic-api/);
  assert.throws(() => parse([{ id: "a", runtime: "claude", home: "h", access: { kind: "opencode-go" } }]), /needs a key/);
});

test("the codex provider config is written, updated, but never over a hand-written file", () => {
  const home = mkdtempSync(join(tmpdir(), "ember-codex-"));
  assert.equal(prepareCodexHome(home, "opencode-go", "deepseek-flash"), true);
  assert.match(readFileSync(join(home, "config.toml"), "utf8"), /model_provider = "opencode-go"/);
  assert.equal(prepareCodexHome(home, "opencode-go", "deepseek-flash"), false, "unchanged");
  assert.equal(prepareCodexHome(home, "opencode-go", "glm-5"), true);
  assert.match(readFileSync(join(home, "config.toml"), "utf8"), /model = "glm-5"/);
  writeFileSync(join(home, "config.toml"), "model = \"mine\"\n");
  assert.equal(prepareCodexHome(home, "opencode-go", "deepseek-flash"), false);
  assert.equal(readFileSync(join(home, "config.toml"), "utf8"), "model = \"mine\"\n");
  assert.equal(prepareCodexHome(home, "subscription", undefined), false);
});

test("usage sums model requests; claude's split responses count once", () => {
  const dir = mkdtempSync(join(tmpdir(), "ember-usage-"));
  const write = (name: string, lines: unknown[]) => {
    writeFileSync(join(dir, name), lines.map((l) => JSON.stringify(l)).join("\n"));
    return join(dir, name);
  };
  const usage = { input_tokens: 100, cache_read_input_tokens: 900, cache_creation_input_tokens: 0, output_tokens: 50 };
  assert.deepEqual(readUsage("claude", write("c.jsonl", [
    { type: "assistant", message: { id: "m1", model: "deepseek-flash", usage } },
    { type: "assistant", message: { id: "m1", model: "deepseek-flash", usage } },
    { type: "assistant", message: { id: "m2", model: "deepseek-flash", usage } },
  ])), { modelCalls: 2, inputTokens: 2000, cachedTokens: 1800, outputTokens: 100, model: "deepseek-flash" });
  assert.deepEqual(readUsage("codex", write("x.jsonl", [
    { type: "turn_context", payload: { model: "gpt-5" } },
    { type: "event_msg", payload: { type: "token_count", info: { last_token_usage: { input_tokens: 10, cached_input_tokens: 4, output_tokens: 2 } } } },
    { type: "event_msg", payload: { type: "token_count", info: null } },
    { type: "event_msg", payload: { type: "token_count", info: { last_token_usage: { input_tokens: 20, cached_input_tokens: 0, output_tokens: 3 } } } },
  ])), { modelCalls: 2, inputTokens: 30, cachedTokens: 4, outputTokens: 5, model: "gpt-5" });
});
