// A change to one message must not make the background reader hash the rest of the page again.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Data } from "../src/data.ts";
import { MdAhead } from "../src/md-ahead.ts";
import { mdKey, parse } from "../src/markdown.ts";
import { Runner } from "../src/runtime.ts";

test("a_message_change_keeps_unchanged_readings_ready_without_hashing_their_words_again", () => {
  const stable = "An already cached long reply: " + "same words. ".repeat(100);
  const changed = "An edited reply with different words.";
  const stableKey = mdKey(stable);
  const changedKey = mdKey(changed);
  const entries = new Map<number, unknown>([
    [1, { n: 1, kind: "message", thread: 7, authorKind: "agent", text: stable }],
    [2, { n: 2, kind: "message", thread: 7, authorKind: "person", text: "first" }],
  ]);
  const checks: string[] = [];
  const data = {
    logSpan: () => ({ min: 1, max: Math.max(...entries.keys()), count: entries.size }),
    logRange: () => entries,
    mdStore: () => ({ has: (key: string) => { checks.push(key); return true; } }),
  } as unknown as Data;
  const ahead = new MdAhead(data, {} as Runner, () => 0);
  const readChar = String.prototype.charCodeAt;
  let stableChars = 0;
  String.prototype.charCodeAt = function (at: number) {
    if (String(this) === stable) stableChars++;
    return readChar.call(this, at);
  };
  try {
    ahead.thread("w/s", 7);
    assert.ok(stableChars > 0, "the first time, the old reply is identified for the cache");
    stableChars = 0;
    checks.length = 0;
    entries.set(2, { n: 2, kind: "message", thread: 7, authorKind: "person", text: "second" });
    ahead.thread("w/s", 7);
    assert.deepEqual(checks, [stableKey], "still check the cache, since it can have evicted a reading");
    assert.equal(stableChars, 0, "an unchanged reply's words need no second hash");
    entries.set(3, { n: 3, kind: "edit", target: 1, text: stable, attachments: ["a new attachment"] });
    checks.length = 0;
    ahead.thread("w/s", 7);
    assert.deepEqual(checks, [stableKey]);
    assert.equal(stableChars, 0, "an edit of the attachments leaves the reply's words alone");
    entries.set(3, { n: 3, kind: "edit", target: 1, text: changed });
    checks.length = 0;
    ahead.thread("w/s", 7);
    assert.deepEqual(checks, [changedKey], "an edit is checked by its new words");
    entries.delete(3);
    checks.length = 0;
    ahead.thread("w/s", 7);
    assert.deepEqual(checks, [stableKey], "removing the edit restores the original reply's key");
    assert.equal(stableChars, 0);
  } finally {
    String.prototype.charCodeAt = readChar;
  }
});

test("a_reply_is_prepared_again_when_its_cached_reading_has_been_evicted", async () => {
  const text = `**A saved reply.** ${Math.random()}`;
  const key = mdKey(text);
  const entries = new Map([[1, Object.freeze({ n: 1, kind: "message", thread: 7, authorKind: "agent", text })]]);
  const cached = new Map([[key, "old cached tree"]]);
  let ready!: () => void;
  const prepared = new Promise<void>((resolve) => { ready = resolve; });
  const store = {
    has: (k: string) => cached.has(k),
    get: (k: string) => cached.get(k) ?? null,
    put: (k: string, value: string) => { cached.set(k, value); ready(); },
  };
  const data = {
    logSpan: () => ({ min: 1, max: 1, count: 1 }),
    logRange: () => entries,
    mdStore: () => store,
  } as unknown as Data;
  const runner = new Runner();
  const ahead = new MdAhead(data, runner, () => 0);
  try {
    ahead.thread("w/s", 7);
    cached.delete(key);
    ahead.thread("w/s", 7);
    await prepared;
    assert.deepEqual(JSON.parse(cached.get(key)!), parse(text));
  } finally {
    runner.shutdown();
  }
});
