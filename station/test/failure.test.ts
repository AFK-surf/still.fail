// What failed a turn, from what any runtime said of it (agents/runtime.ts `failureOf`): the account, the provider
// refusing it, a limit, the provider out of room, the network, the conversation's size, else the model.
import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyResult } from "../src/agents/claude.ts";
import { failureOf } from "../src/agents/runtime.ts";

test("a failure is told apart by what it means to people", () => {
  assert.equal(failureOf("401 Unauthorized"), "auth");
  // A 403 is the account's only where it says so; else the provider turning whoever asks away.
  assert.equal(failureOf("unexpected status 403 Forbidden: "), "refused");
  assert.equal(failureOf("403: OAuth token does not meet scope requirement"), "auth");
  assert.equal(failureOf('{"error":{"code":"unsupported_country_region_territory"}}'), "refused");
  assert.equal(failureOf("429 Too Many Requests"), "rate_limit");
  assert.equal(failureOf("the model is overloaded"), "overloaded");
  assert.equal(failureOf("stream disconnected before completion: error sending request"), "network");
  assert.equal(failureOf("request failed: ECONNRESET"), "network");
  assert.equal(failureOf("prompt is too long: 210000 tokens > 200000 maximum"), "context");
  assert.equal(failureOf("this model's maximum context length is 128000 tokens"), "context");
  assert.equal(failureOf("the model failed"), "model");
  // Claude Code's own, as before, with the network and the conversation's size told apart from the model.
  assert.equal(classifyResult("API Error: Connection error. (ECONNRESET)"), "network");
  assert.equal(classifyResult("Prompt is too long"), "context");
  assert.equal(classifyResult("API Error: 500 Internal server error"), "model");
});
