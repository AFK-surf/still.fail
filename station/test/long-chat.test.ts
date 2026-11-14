// A session whose context is compacted, or that goes on in a new conversation, in a long chat is told to read back what
// people said in it (instructions.ts `longChat`, afresh.ts `toldLongChat`), so that it does not drift from them.
import assert from "node:assert/strict";
import { test } from "node:test";
import { LONG_CHAT } from "../src/agents/instructions.ts";
import { type RuntimeEvent } from "../src/agents/runtime.ts";
import { type Turn, onFrame } from "../src/agents/claude.ts";
import { codexCompacted } from "../src/agents/codex.ts";
import { Rig, matches, message, reply, settle } from "./hub-fakes.ts";

const READ_BACK = "read back what people said in it";

/// A chat with `count` messages from people, its agent's turns all over.
async function chat(r: Rig, count: number) {
  const m = message();
  await r.accept(m);
  await settle();
  r.claude.last().complete();
  await settle();
  for (let i = 1; i < count; i++) {
    await r.accept(reply(m, `${2000 + i}.000100`, `and ${i}`));
    await settle();
    if (r.claude.last().busy()) r.claude.last().complete();
    await settle();
  }
  return m;
}

test("Claude Code's compact_boundary, automatic or by hand, says it compacted", () => {
  const told: RuntimeEvent[] = [];
  const turn: Turn = { busy: true, aborting: false, authFailure: null, closed: false };
  onFrame({ type: "system", subtype: "compact_boundary", compact_metadata: { trigger: "auto", pre_tokens: 180000 } }, turn, (e) => told.push(e), () => {});
  assert.deepEqual(told, [{ type: "compacted" }]);
});

test("Codex's contextCompaction item, done, says it compacted", () => {
  assert.equal(codexCompacted("item/completed", { threadId: "t", turnId: "u", item: { type: "contextCompaction", id: "c" } }), true);
  assert.equal(codexCompacted("item/started", { threadId: "t", turnId: "u", item: { type: "contextCompaction", id: "c" } }), false);
  assert.equal(codexCompacted("item/completed", { threadId: "t", turnId: "u", item: { type: "agentMessage", id: "m" } }), false);
});

test("compacted in the middle of a turn in a long chat: the turn is told at once to read back what people said", async () => {
  const r = new Rig();
  const m = await chat(r, LONG_CHAT + 1);
  await r.accept(reply(m, "3000.000100", "go on"));
  await settle();
  const agent = r.claude.last();
  assert.ok(agent.busy());
  const before = agent.steers.length;
  agent.events({ type: "compacted" });
  await settle();
  const told = agent.steers.slice(before);
  assert.equal(told.length, 1, JSON.stringify(told));
  assert.ok(matches(told[0]!, ['via="station"', "This chat is long", READ_BACK, "chat_history for C1/"]), told[0]);
  agent.complete();
  await settle();
  // Told once: the next turn is not told again.
  await r.accept(reply(m, "3001.000100", "next"));
  await settle();
  assert.ok(!r.claude.last().prompts.at(-1)!.includes(READ_BACK), r.claude.last().prompts.at(-1));
  await r.close();
});

test("compacted with no turn to tell it in (by hand, or a steer refused): its next prompt tells it", async () => {
  const r = new Rig();
  const m = await chat(r, LONG_CHAT + 1);
  await r.accept(reply(m, "3000.000100", "go on"));
  await settle();
  const agent = r.claude.last();
  agent.unsteerable = true;
  const before = agent.prompts.length;
  agent.events({ type: "compacted" });
  await settle();
  agent.complete();
  await settle();
  await r.accept(reply(m, "3001.000100", "next"));
  await settle();
  // The first prompt after it (a nudge at the turn's end here) begins with it; only that one.
  assert.equal(r.claude.last(), agent);
  const after = agent.prompts.slice(before);
  assert.ok(after.length > 0);
  assert.ok(after[0]!.replace(/^\[Delivered at [^\n]+\]\n/, "").startsWith("This chat is long"), after[0]);
  assert.equal(after.filter((p) => p.includes(READ_BACK)).length, 1, JSON.stringify(after));
  await r.close();
});

test("a short chat is not told to read back when compacted", async () => {
  const r = new Rig();
  const m = await chat(r, 3);
  await r.accept(reply(m, "3000.000100", "go on"));
  await settle();
  const agent = r.claude.last();
  const before = agent.steers.length;
  agent.events({ type: "compacted" });
  await settle();
  assert.equal(agent.steers.length, before);
  agent.complete();
  await settle();
  await r.accept(reply(m, "3001.000100", "next"));
  await settle();
  assert.ok(!r.claude.last().prompts.at(-1)!.includes(READ_BACK));
  await r.close();
});

test("gone on in a new conversation in a long chat: told to read back what people said, with where its work is", async () => {
  const r = new Rig();
  const m = await chat(r, LONG_CHAT + 1);
  const key = r.claude.last().options.key;
  assert.equal(await r.hub.clear(key, true), null);
  await r.accept(reply(m, "3000.000100", "next"));
  await settle();
  const prompt = r.claude.last().prompts.at(-1)!;
  assert.ok(matches(prompt, ["This is a new conversation", "This chat is long", READ_BACK, "next"]), prompt);
  await r.close();
});
