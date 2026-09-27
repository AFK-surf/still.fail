import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { codexOverrides } from "../src/profiles.ts";
import { hostSkillsOff, withCaBundle } from "../src/runtime/codex.ts";
import { TranscriptTail } from "../src/transcript.ts";
import type { RuntimeKind } from "../src/config.ts";

const readUsage = (runtime: RuntimeKind, path: string) => {
  const tail = new TranscriptTail(runtime, path);
  tail.read();
  return tail.usage;
};

const parse = (profiles: unknown[]) => parseConfig({ profiles: profiles as never }, "/data");

test("an account runs every runtime it can, each with the environment it needs; hand-set variables win", () => {
  const [ocg, anthropic, sub] = parse([
    { id: "a", home: "h/a", access: { kind: "opencode-go", key: "k1" }, env: { ANTHROPIC_SMALL_FAST_MODEL: "mine" } },
    { id: "b", home: "h/b", access: { kind: "anthropic-api", key: "k2" } },
    { id: "c", runtime: "codex", home: "h/c", access: { kind: "subscription" } },
  ]).profiles;
  assert.deepEqual(ocg!.runtimes, ["claude", "codex"]);
  assert.equal(ocg!.envs.claude!.ANTHROPIC_API_KEY, "k1");
  assert.equal(ocg!.envs.claude!.ANTHROPIC_BASE_URL, "https://opencode.ai/zen/go");
  assert.equal(ocg!.envs.claude!.ANTHROPIC_SMALL_FAST_MODEL, "mine");
  assert.deepEqual(ocg!.customEnv, { ANTHROPIC_SMALL_FAST_MODEL: "mine" });
  assert.deepEqual(ocg!.envs.codex, { OPENCODE_GO_KEY: "k1", OPENCODE_SESSION: "ember-{route}", ANTHROPIC_SMALL_FAST_MODEL: "mine" });
  assert.deepEqual(anthropic!.runtimes, ["claude"]);
  assert.deepEqual(sub!.runtimes, ["codex"]);
});

test("profiles without access keep their raw environment", () => {
  const [p] = parse([{ id: "a", runtime: "claude", home: "h", env: { X: "1" } }]).profiles;
  assert.deepEqual(p!.access, { kind: "env", key: "" });
  assert.deepEqual(p!.envs.claude, { X: "1" });
});

test("access kinds are checked against the runtime and need their key", () => {
  assert.throws(() => parse([{ id: "a", home: "h", access: { kind: "subscription" } }]), /needs a runtime/);
  assert.throws(() => parse([{ id: "a", runtime: "claude", home: "h", access: { kind: "opencode-go" } }]), /needs a key/);
});

test("codex gets its provider as config overrides, so config.toml stays the user's", () => {
  const overrides = codexOverrides("opencode-go", "glm-5");
  assert.equal(overrides.model_provider, `"opencode-go"`);
  assert.equal(overrides.model, `"glm-5"`);
  assert.equal(overrides["model_providers.opencode-go.env_http_headers"], `{"x-opencode-session"="OPENCODE_SESSION"}`);
  assert.deepEqual(codexOverrides("subscription", undefined), { "features.apps": "false", "features.recommended_plugins": "false" });
  assert.equal(overrides["features.apps"], "false");
});

test("codex reads a CA file rather than the system's roots, unless the user chose one", () => {
  const dir = mkdtempSync(join(tmpdir(), "ember-ca-"));
  const bundle = join(dir, "cert.pem");
  writeFileSync(bundle, "");
  assert.equal(withCaBundle({}, bundle).SSL_CERT_FILE, bundle);
  assert.equal(withCaBundle({ SSL_CERT_FILE: "/mine.pem" }, bundle).SSL_CERT_FILE, "/mine.pem");
  assert.equal(withCaBundle({ CODEX_CA_CERTIFICATE: "/mine.pem" }, bundle).SSL_CERT_FILE, undefined);
  assert.equal(withCaBundle({}, join(dir, "missing.pem")).SSL_CERT_FILE, undefined);
});

test("the user's own skills are turned off one SKILL.md at a time, linked folders included", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-skills-"));
  const elsewhere = mkdtempSync(join(tmpdir(), "ember-skills-src-"));
  mkdirSync(join(root, "plain"));
  writeFileSync(join(root, "plain", "SKILL.md"), "");
  mkdirSync(join(elsewhere, "inner"));
  writeFileSync(join(elsewhere, "inner", "SKILL.md"), "");
  symlinkSync(elsewhere, join(root, "pack"));
  symlinkSync(root, join(root, "pack", "loop")); // a cycle ends
  assert.deepEqual(hostSkillsOff(root), [
    { path: join(root, "pack", "inner", "SKILL.md"), enabled: false },
    { path: join(root, "plain", "SKILL.md"), enabled: false },
  ]);
  assert.deepEqual(hostSkillsOff(join(root, "none")), []);
});

test("usage sums model requests; claude's split responses count once", () => {
  const dir = mkdtempSync(join(tmpdir(), "ember-usage-"));
  const write = (name: string, lines: unknown[]) => {
    writeFileSync(join(dir, name), `${lines.map((l) => JSON.stringify(l)).join("\n")}\n`);
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

test("a connect's effort must be one its runtime knows", () => {
  const profiles = [{ id: "cc", runtime: "claude" as const, home: "h" }];
  assert.throws(() => parseConfig({ profiles, connects: [{ id: "a", bind: { runtime: "claude", effort: "minimal" } }] }, "/d"), /has no effort minimal/);
  assert.equal(parseConfig({ profiles, connects: [{ id: "a", bind: { runtime: "claude", effort: "max" } }] }, "/d").connects[0]!.bind.effort, "max");
});
