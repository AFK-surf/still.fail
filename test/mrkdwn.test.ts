import assert from "node:assert/strict";
import { test } from "node:test";
import { splitForSlack, toMrkdwn } from "../src/chat/mrkdwn.ts";

test("markdown emphasis, links and headings become mrkdwn", () => {
  assert.equal(toMrkdwn("**bold** and *italic* and ~~gone~~"), "*bold* and _italic_ and ~gone~");
  assert.equal(toMrkdwn("see [the PR](https://github.com/x/y/pull/1)"), "see <https://github.com/x/y/pull/1|the PR>");
  assert.equal(toMrkdwn("## Result\n- one\n* two"), "*Result*\n• one\n• two");
});

test("special characters are escaped outside links", () => {
  assert.equal(toMrkdwn("a < b && c > d"), "a &lt; b &amp;&amp; c &gt; d");
});

test("code is left alone apart from escaping and the fence language", () => {
  assert.equal(toMrkdwn("run `a **b**` now"), "run `a **b**` now");
  assert.equal(toMrkdwn("```ts\nconst x = a < b;\n```"), "```\nconst x = a &lt; b;\n```");
});

test("long text splits on paragraph boundaries", () => {
  const para = "x".repeat(60);
  const chunks = splitForSlack(Array(5).fill(para).join("\n\n"), 130);
  assert.deepEqual(chunks, [`${para}\n\n${para}`, `${para}\n\n${para}`, para]);
  assert.deepEqual(splitForSlack(""), [""]);
});
