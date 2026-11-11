import assert from "node:assert/strict";
import { test } from "node:test";
import { noticeExcerpt, remoteNotice } from "../src/jobs/notice.ts";

test("compiler column padding cannot fill a completion notice or hide its warning", () => {
  const output = " ".repeat(62_810) + "╰── Warning (text_segment_excceed)\nTotal tests: 1, passed: 1, failed: 0.";
  const excerpt = noticeExcerpt(output);
  assert.ok(excerpt.length < 200);
  assert.match(excerpt, /62810 spaces\/tabs omitted/);
  assert.match(excerpt, /Warning \(text_segment_excceed\)/);
  assert.match(excerpt, /passed: 1, failed: 0/);
  assert.equal(noticeExcerpt("compiling\n  diagnostic\ndone"), "compiling\n  diagnostic\ndone");
});

test("long JSON and many lines have bounded excerpts with marked omissions and intact Unicode", () => {
  const line = '{"value":"' + "😀".repeat(70_000) + '","error":"failed"}';
  const excerpt = noticeExcerpt(line);
  assert.ok(Array.from(excerpt).length <= 512);
  assert.ok(excerpt.startsWith('{"value":"'));
  assert.ok(excerpt.endsWith('","error":"failed"}'));
  assert.match(excerpt, /\[omitted\]/);
  assert.equal(excerpt.isWellFormed(), true);
  const many = noticeExcerpt(("line " + "中".repeat(400) + "\n").repeat(100) + "last failure");
  assert.ok(Array.from(many).length <= 4096);
  assert.match(many, /^\[Earlier output omitted\]/);
  assert.ok(many.endsWith("last failure"));
});

test("remote notifications retain status and artifact information without embedding the full result", () => {
  const result = {
    job: { state: "exited", exitCode: 3, command: "private-command".repeat(10_000), cwd: "/remote/work" },
    log: " ".repeat(62_810) + "Warning: column limit\nfailed test",
    notices: [{ text: "half way" }], back: { saved: ["station-back/build/result.txt"], errors: ["missing report"] },
  };
  const before = JSON.stringify(result);
  const notice = remoteNotice("build", "B", result);
  assert.ok(notice.startsWith('Remote task build on B: {"state":"exited","exitCode":3}'));
  for (const text of ["Warning: column limit", "failed test", "half way", "result.txt", "missing report", "station_task", "action=get or log"]) {
    assert.ok(notice.includes(text), text);
  }
  assert.ok(notice.length < 1000);
  assert.ok(!notice.includes("private-command"));
  assert.equal(JSON.stringify(result), before, "tool results and the original log are not modified");
  const huge = remoteNotice("build", "B", { ...result, log: "x\n".repeat(60_000), notices: ["y".repeat(60_000)], back: ["z".repeat(60_000)] });
  assert.ok(Array.from(huge).length < 8192);
  assert.match(huge, /"exitCode":3/);
});
