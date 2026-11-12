import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { LiveHub, type LiveMessage, type Locate } from "../src/sessions/live.ts";
import { settle, testClock } from "./hub-fakes.ts";

const line = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-09-26T00:00:00Z", message: { id, content: [{ type: "text", text }] } })}\n`;
const deferred = () => {
  let resolve!: (at: ReturnType<Locate>) => void;
  const promise = new Promise<ReturnType<Locate>>((done) => { resolve = done; });
  return { promise, resolve };
};
const texts = (got: LiveMessage[]) => got.flatMap((m) => m.type === "timeline" ? m.entries.map((e) => e.text) : []);

test("a turn ending during a location tells its final transcript before clear", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-")), left = join(dir, "left.jsonl"), now = join(dir, "now.jsonl");
  writeFileSync(left, line("one", "m1"));
  const time = testClock();
  let paths = [left];
  const hub = new LiveHub(() => ({ runtime: "claude", paths, current: true }), time.clock);
  const got: LiveMessage[] = [];
  try {
    hub.subscribe("s", 0, null, (m) => got.push(m));
    await hub.idle();
    const request = deferred();
    const signals: AbortSignal[] = [];
    // The lookup asked as it moved is pending; one asked after finds where it is now.
    hub.locateAsync = (_key, abort) => { signals.push(abort); return signals.length === 1 ? request.promise : Promise.resolve({ runtime: "claude", paths, current: true }); };
    appendFileSync(left, line("last old", "m2"));
    writeFileSync(now, line("last new", "m3"));
    paths = [left, now];
    hub.moved("s");
    await hub.idle();
    await settle(2);
    await hub.idle();
    await hub.turnEnded("s");
    assert.equal(signals[0]?.aborted, true);
    const last = got.findIndex((m) => m.type === "timeline" && m.entries.some((e) => e.text === "last new"));
    const clear = got.findIndex((m) => m.type === "clear");
    assert.ok(last >= 0 && last < clear);
    assert.deepEqual(texts(got), ["one", "last old", "last new"]);
    request.resolve({ runtime: "claude", paths: [left], current: false });
    await settle();
    await hub.idle();
    appendFileSync(now, line("next", "m4"));
    hub.event("s", { kind: "start", id: "x", step: "text" });
    hub.event("s", { kind: "end", id: "x" });
    await settle(2);
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    assert.deepEqual(texts(got), ["one", "last old", "last new", "next"], "the cancelled result cannot restore the old path");
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a second move supersedes an unfinished lookup", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-"));
  const paths = [join(dir, "a.jsonl"), join(dir, "b.jsonl"), join(dir, "c.jsonl")];
  for (let i = 0; i < paths.length; i++) writeFileSync(paths[i]!, line(String(i), `m${i}`));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [paths[0]!], current: true }), time.clock);
  const got: LiveMessage[] = [];
  const requests: { signal: AbortSignal; pending: ReturnType<typeof deferred> }[] = [];
  try {
    hub.subscribe("s", 0, null, (m) => got.push(m));
    await hub.idle();
    hub.locateAsync = (_key, signal) => {
      const pending = deferred(); requests.push({ signal, pending }); return pending.promise;
    };
    hub.moved("s");
    await hub.idle();
    await settle(2);
    await hub.idle();
    hub.moved("s");
    await hub.idle();
    await settle(2);
    await hub.idle();
    assert.equal(requests[0]!.signal.aborted, true);
    requests[1]!.pending.resolve({ runtime: "claude", paths, current: true });
    await settle();
    await hub.idle();
    requests[0]!.pending.resolve({ runtime: "claude", paths: paths.slice(0, 2), current: true });
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    assert.deepEqual(texts(got), ["0", "1", "2"]);
    appendFileSync(paths[2]!, line("3", "m3"));
    hub.event("s", { kind: "start", id: "x", step: "text" });
    hub.event("s", { kind: "end", id: "x" });
    await settle(2);
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    assert.deepEqual(texts(got), ["0", "1", "2", "3"]);
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed background lookup leaves the old transcript readable and can be tried again", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-")), old = join(dir, "old.jsonl"), next = join(dir, "next.jsonl");
  writeFileSync(old, line("one", "m1"));
  writeFileSync(next, line("two", "m2"));
  const time = testClock();
  let paths = [old];
  const hub = new LiveHub(() => ({ runtime: "claude", paths, current: true }), time.clock);
  const got: LiveMessage[] = [];
  let calls = 0;
  try {
    hub.subscribe("s", 0, null, (m) => got.push(m));
    await hub.idle();
    assert.deepEqual(texts(got), ["one"]);
    hub.locateAsync = async () => {
      if (++calls === 1) throw new Error("location unavailable");
      return { runtime: "claude", paths: [old, next], current: true };
    };
    paths = [old, next];
    hub.moved("s");
    await hub.idle();
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    assert.ok(calls >= 2);
    assert.deepEqual(texts(got), ["one", "two"]);
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a read requested during a slow lookup finds the transcript written meanwhile", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-")), old = join(dir, "old.jsonl"), next = join(dir, "next.jsonl");
  writeFileSync(old, line("one", "m1"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [old], current: true }), time.clock);
  const got: LiveMessage[] = [];
  const first = deferred();
  let calls = 0;
  try {
    hub.subscribe("s", 0, null, (m) => got.push(m));
    await hub.idle();
    hub.locateAsync = async () => ++calls === 1 ? first.promise : { runtime: "claude", paths: [old, next], current: true };
    hub.moved("s");
    await hub.idle();
    await settle();
    await hub.idle();
    writeFileSync(next, line("two", "m2"));
    // The scheduled read occurs while the first lookup is still using an older snapshot.
    await time.adjust(40);
    await settle();
    await hub.idle();
    first.resolve({ runtime: "claude", paths: [old], current: false });
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    assert.equal(calls, 2);
    assert.deepEqual(texts(got), ["one", "two"]);
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a missing transcript does not make the live reader poll without another request", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-")), old = join(dir, "old.jsonl");
  writeFileSync(old, line("one", "m1"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [old], current: true }), time.clock);
  const first = deferred();
  let calls = 0;
  try {
    hub.subscribe("s", 0, null, () => {});
    await hub.idle();
    hub.locateAsync = async () => ++calls === 1 ? first.promise : { runtime: "claude", paths: [old], current: false };
    hub.moved("s");
    await hub.idle();
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    first.resolve({ runtime: "claude", paths: [old], current: false });
    await settle();
    await hub.idle();
    await time.adjust(400);
    await settle();
    await hub.idle();
    assert.equal(calls, 2);
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a transcript at the same path is reread when its runtime changes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-follow-order-")), path = join(dir, "current.jsonl");
  writeFileSync(path, line("one", "m1"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path], current: true }), time.clock);
  const got: LiveMessage[] = [];
  try {
    hub.subscribe("s", 0, null, (m) => got.push(m));
    await hub.idle();
    hub.locateAsync = async () => ({ runtime: "codex", paths: [{ path, runtime: "codex" }], current: true });
    hub.moved("s");
    await hub.idle();
    writeFileSync(path, `${JSON.stringify({ type: "response_item", timestamp: "2026-09-26T00:00:00Z", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "two" }] } })}\n`);
    await settle();
    await hub.idle();
    await time.adjust(40);
    await settle();
    await hub.idle();
    const timelines = got.filter((m) => m.type === "timeline");
    assert.deepEqual(timelines.at(-1)?.entries.map((entry) => entry.text), ["two"]);
    assert.equal(timelines.at(-1)?.start, 0);
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});
