import assert from "node:assert/strict";
import { test } from "node:test";
import { splitForSlack } from "../src/chat/mrkdwn.ts";

test("long text splits on paragraph boundaries", () => {
  const para = "x".repeat(60);
  const chunks = splitForSlack(Array(5).fill(para).join("\n\n"), 130);
  assert.deepEqual(chunks, [`${para}\n\n${para}`, `${para}\n\n${para}`, para]);
  assert.deepEqual(splitForSlack(""), [""]);
});
