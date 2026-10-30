import assert from "node:assert/strict";
import { test } from "node:test";
import { markdown } from "../src/markdown.ts";
import { Output } from "../src/output.ts";

test("output_an_agents_markdown_goes_out_as_the_tree_kept_for_its_words_not_copied_again", () => {
  // A chat's page of agents' replies is mostly their trees: copied, put through the shape and cloned to keep for the
  // next change, each time it went out, they were most of what the core did to open a chat (2026-10-31).
  const md = markdown("一段 **粗** 和 `code`\n\n- 一\n- 二");
  const message = { seq: 1, outgoing: null, authorKind: "agent", text: "…", md };
  const out = new Output();
  const topic = { topic: "chat", station: "w/s", thread: 1, session: null };
  const clock = { now: Date.UTC(2026, 9, 31, 12), offsetMin: 480 };
  const first = out.shape(topic, { messages: [message], outbox: [] }, clock, false) as { ok: { messages: { md: unknown }[] } };
  assert.equal(first.ok.messages[0]!.md, md, "the tree itself");
  // and again, its message changed beside it (a reaction, an edit's time): the same tree
  const again = out.shape(topic, { messages: [{ ...message, text: "…!" }], outbox: [] }, clock, false) as { ok: { messages: { md: unknown }[] } };
  assert.equal(again.ok.messages[0]!.md, md);
});
