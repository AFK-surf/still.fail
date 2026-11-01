// The usage counter (src/usage/counter.ts): the Rust station's usage/tests.rs ported, the push-driven reads, and (when a
// copy of a real station is at $USAGE_WORK, default /tmp/usage-work) what it records against what the Rust recorded.
import type { Clock } from "effect";
import assert from "node:assert/strict";
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { monitorEventLoopDelay } from "node:perf_hooks";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";
import { cost, price, priceTable, sessionUsage, usageNow } from "../src/read/usage.ts";
import { iso, parseIso } from "../src/read/transcript.ts";
import { type StoreChange, type UsageGroup, Store, newMessage } from "../src/store/store.ts";
import { type CallState, UsageCounter, callsOf, claudeFiles, claudeProject, readFrom } from "../src/usage/counter.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";
import { keepUsage } from "../src/usage/module.ts";
import { testClock } from "./hub-fakes.ts";

const dirs: string[] = [];
const stores: Store[] = [];
const counters: UsageCounter[] = [];
after(async () => {
  for (const c of counters) await c.stop();
  for (const s of stores) {
    try {
      s.close();
    } catch {}
  }
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "usage-test-"));
  dirs.push(d);
  return d;
}

const claudeLine = (id: string, at: number, model: string, usage: unknown) =>
  JSON.stringify({ type: "assistant", timestamp: iso(at), isSidechain: false, message: { id, model, usage } });

const usage = (input: number, read: number, short: number, long: number, output: number) => ({
  input_tokens: input,
  cache_read_input_tokens: read,
  cache_creation_input_tokens: short + long,
  cache_creation: { ephemeral_5m_input_tokens: short, ephemeral_1h_input_tokens: long },
  output_tokens: output,
});

const fresh = (): CallState => ({ model: null, codexId: null });

test("a Claude response written as several lines counts once, with its cache split by how long and the context it sent", () => {
  const text = [
    claudeLine("m1", 1000, "claude-opus-5-5", usage(2, 100, 0, 50, 10)),
    claudeLine("m1", 1001, "claude-opus-5-5", usage(2, 100, 0, 50, 30)),
    JSON.stringify({ type: "user", message: { content: "usage" } }),
    claudeLine("m2", 2000, "<synthetic>", usage(0, 0, 0, 0, 0)),
    claudeLine("m3", 3000, "claude-sonnet-5-5", { input_tokens: 5, cache_creation_input_tokens: 7, output_tokens: 1, speed: "fast" }),
    // A subagent's prompt is not the session's context.
    JSON.stringify({ type: "assistant", timestamp: iso(4000), isSidechain: true, message: { id: "m4", model: "claude-haiku-4-5", usage: usage(9, 0, 0, 0, 1) } }),
  ].join("\n");
  const calls = callsOf("claude", text, false, fresh());
  assert.equal(calls.length, 3);
  assert.deepEqual(calls[0], {
    id: "m1", at: 1000, model: "claude-opus-5-5", subagent: false, fast: false, input: 2, cacheRead: 100, cacheWrite: 0, cacheWriteLong: 50, output: 30,
    calls: 1, context: 152, window: null,
  });
  // Without the split, what was written to the cache is taken as written for five minutes.
  assert.deepEqual([calls[1]!.cacheWrite, calls[1]!.cacheWriteLong, calls[1]!.fast, calls[1]!.context], [7, 0, true, 12]);
  assert.deepEqual([calls[2]!.subagent, calls[2]!.context], [true, null]);
});

test("Codex calls are its token counts, told once each, with the model its turn named", () => {
  const count = (total: number, input: number, cached: number, output: number) =>
    JSON.stringify({
      timestamp: iso(5000), type: "event_msg",
      payload: { type: "token_count", info: { total_token_usage: { total_tokens: total }, last_token_usage: { input_tokens: input, cached_input_tokens: cached, output_tokens: output }, model_context_window: 258000 } },
    });
  const text = [
    JSON.stringify({ timestamp: iso(4000), type: "session_meta", payload: { id: "th1", cwd: "/w" } }),
    JSON.stringify({ timestamp: iso(4000), type: "turn_context", payload: { model: "gpt-6" } }),
    count(120, 100, 60, 20),
    // The same count again, told with the rate limits.
    count(120, 100, 60, 20),
    JSON.stringify({ timestamp: iso(5000), type: "event_msg", payload: { type: "token_count", info: null } }),
    count(200, 70, 10, 10),
  ].join("\n");
  const state = fresh();
  const calls = callsOf("codex", text, false, state);
  assert.deepEqual(calls.map((c) => c.id), ["codex:th1:120", "codex:th1:120", "codex:th1:200"], "repeats are left to the store, which keeps one");
  assert.deepEqual([calls[0]!.input, calls[0]!.cacheRead, calls[0]!.output, calls[0]!.model], [40, 60, 20, "gpt-6"]);
  // What it sent (its input has what was cached in it) is the context, of the window it says.
  assert.deepEqual([calls[2]!.context, calls[2]!.window], [70, 258000]);
  assert.equal(state.model, "gpt-6");
});

test("a turn told at once is the calls it says, with the context it ended with; dsh's window comes before its calls", () => {
  const turn = (run: string, calls: number, context: number) =>
    JSON.stringify({ type: "usage", run, time: 1000, model: "swe-2", calls, context, window: 262000, usage: { inputTokens: 10, cacheReadTokens: 5, cacheWriteTokens: 0, outputTokens: 2 } });
  assert.deepEqual(callsOf("devin", [turn("r1", 3, 1252), turn("r2", 0, 0)].join("\n"), false, fresh()).map((c) => [c.id, c.calls, c.context, c.window]), [
    ["devin:r1", 3, 1252, 262000],
    // One that says none: one call, its context not told.
    ["devin:r2", 1, null, 262000],
  ]);
  const dsh = [
    JSON.stringify({ type: "request/context", data: { contextWindow: 128000 } }),
    JSON.stringify({ type: "assistant/message", time: 1000, data: { message: { id: "a1", source: { model: "deepseek-v4" } }, usage: { inputTokens: 10, cacheReadTokens: 90, cacheWriteTokens: 5, outputTokens: 3 } } }),
  ].join("\n");
  assert.deepEqual(callsOf("dsh", dsh, false, fresh()).map((c) => [c.calls, c.context, c.window]), [[1, 105, 128000]]);
});

const group = (g: Partial<UsageGroup>): UsageGroup => ({
  day: "", session: "", thread: null, person: null, profile: null, runtime: "", model: null, fast: false, calls: 0, input: 0, cacheRead: 0,
  cacheWrite: 0, cacheWriteLong: 0, output: 0, ...g,
});

test("prices are found however a profile spells the model, and cost counts each kind of token", () => {
  assert.equal(price("claude-opus-5-5")?.input, 4.0);
  assert.equal(price("anthropic/claude-opus-5-5[1m]")?.cacheRead, 0.2);
  assert.equal(price("claude-opus-5")?.input, 5.0);
  assert.equal(price("claude-fable-5-1")?.cacheRead, 0.25);
  assert.equal(price("gpt-6"), null);
  const g = group({ model: "claude-opus-5-5", input: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000, cacheWriteLong: 1_000_000, output: 1_000_000 });
  // 4 + 0.2 + 5 + 8 + 20
  assert.ok(Math.abs(cost(g)! - 37.2) < 1e-9);
  assert.ok(Math.abs(cost({ ...g, fast: true })! - 74.4) < 1e-9);
  assert.equal(cost({ ...g, model: "gpt-6" }), null);
});

test("GPT usage has a price, and unknown variants do not borrow one", () => {
  for (const [model, input, cached, output] of [
    ["gpt-6-astra", 10.0, 1.0, 50.0],
    ["gpt-6.1-terra", 1.0, 0.05, 5.0],
    ["gpt-6.1-sol", 2.0, 0.1, 10.0],
    ["gpt-6-sol", 2.0, 0.2, 10.0],
    ["gpt-6-luna", 0.1, 0.01, 0.5],
    ["gpt-5.6-sol", 4.0, 0.4, 20.0],
  ] as const) {
    const g = group({ model, input: 1_000_000, cacheRead: 1_000_000, output: 1_000_000 });
    assert.ok(Math.abs(cost(g)! - (input + cached + output)) < 1e-9, model);
  }
  assert.deepEqual(price("openai/gpt-6-astra-2026-08-21"), price("gpt-6-astra"));
  assert.deepEqual(price("gpt-6.1-terra"), { input: 1, cacheRead: 0.05, output: 5 });
  assert.equal(price("gpt-6-astra-unknown"), null);
  assert.equal(price("gpt-6-astra:free"), null);
  const astra = (priceTable("en") as any).rows.find((r: any) => r.model === "gpt-6-astra");
  assert.deepEqual([astra.input, astra.cacheRead, astra.output], [10.0, 1.0, 50.0]);
  const terra = (priceTable("zh") as any).rows.find((r: any) => r.model === "gpt-6.1-terra");
  assert.deepEqual([terra.input, terra.cacheRead, terra.cacheWrite, terra.cacheWriteLong, terra.output], [1, 0.05, null, null, 5]);
  // Actual recorded GPT token totals: cached input is already separate from uncached input.
  const g = group({ model: "gpt-6-astra", input: 1_916_566, cacheRead: 71_041_792, output: 245_251 });
  assert.ok(Math.abs(cost(g)! - 102.470002) < 1e-9);
});

test("the price note finishes its explanation in both languages", () => {
  assert.ok((priceTable("zh") as any).note.endsWith("。"));
  assert.ok((priceTable("en") as any).note.endsWith("."));
});

type Rig = { data: string; store: Store; usage: UsageCounter };

function rig(options: { settleMs?: number; safetyMs?: number; clock?: Clock.Clock } = {}): Rig {
  const data = tempdir();
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }] }));
  const store = Store.open(":memory:", null, options.clock);
  stores.push(store);
  const usage = new UsageCounter({ store, config: () => ({ dataDir: data, profiles: [{ home: join(data, "homes/cc") }] }), ...options });
  counters.push(usage);
  return { data, store, usage };
}

function session(store: Store, key: string, workspace: string, createdAt: number) {
  store.insertSession({ key, connect: "ember", createdBy: "creator@x", runtime: "claude", profile: "cc", workspace, token: `t-${key}`, createdAt, lastActiveAt: createdAt });
}

function append(path: string, lines: string[]) {
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, lines.map((l) => `${l}\n`).join(""));
}

const MAX = Number.MAX_SAFE_INTEGER;

/// A TestClock at a day of 2026 (on its own it starts at 1970).
async function today() {
  const time = testClock();
  await time.adjust(Date.parse("2026-10-06T08:00:00Z"));
  return time;
}

test("each call is counted once, for whom its turn worked, where and on what", async () => {
  const time = await today();
  const pause = () => time.adjust(15);
  const r = rig({ clock: time.clock });
  const workspace = join(r.data, "sessions/ember/c-1/workspace");
  const created = r.store.now();
  session(r.store, "ember:c-1", workspace, created);
  const chat = r.store.openThreadOf("ember", "ember", "1.0", null, "creator@x", "ember:c-1");
  r.store.joinThread(chat.id, "ember:c-1", "ember");
  await pause();
  // A turn from before turns said whom they were for: its first person's message says.
  r.store.startTurn("t1", "ember:c-1", "input");
  const [n] = r.store.insertMessage(newMessage(chat.id, "2.0", "person", "b@x", "hi"));
  r.store.deliver(chat.id, n, ["ember:c-1"]);
  r.store.markDelivered("ember:c-1", [{ thread: chat.id, n, apart: false }]);
  r.store.endTurn("t1", "completed", null, null, null);
  await pause();
  r.store.startTurnFor("t2", "ember:c-1", "input", { profile: "cc2", person: "a@x", thread: chat.id });
  r.store.endTurn("t2", "completed", null, null, null);
  await pause();
  // A job's notice goes on with the work of the turn before.
  r.store.startTurn("t3", "ember:c-1", "job");
  const starts = r.store.listTurns("ember:c-1").map((t) => t.summary.startedAt);

  const project = join(r.data, "transcripts/claude", claudeProject(workspace));
  const main = join(project, "r1.jsonl");
  append(main, [
    // From a terminal, before the station had it: not counted.
    claudeLine("m0", created - 60_000, "claude-opus-5-5", usage(1, 0, 0, 0, 1)),
    claudeLine("m1", starts[0]! + 1, "claude-opus-5-5", usage(10, 0, 0, 0, 1)),
    claudeLine("m2", starts[1]! + 1, "claude-opus-5-5", usage(20, 0, 0, 0, 2)),
  ]);
  append(join(project, "r1/subagents/agent-a.jsonl"), [claudeLine("s1", starts[1]! + 2, "claude-haiku-4-5", usage(5, 0, 0, 0, 5))]);
  assert.equal(r.usage.readingAll(), true);
  assert.equal(await r.usage.read(), 3);
  assert.equal(r.usage.readingAll(), false);

  const rows = r.store.usageGroups(0, MAX, 0).sort((a, b) => a.input - b.input);
  assert.deepEqual(rows.map((g) => [g.input, g.person, g.profile, g.thread]), [[5, "a@x", "cc2", chat.id], [10, "b@x", "cc", chat.id], [20, "a@x", "cc2", chat.id]]);

  // Read again: only what was written since, and nothing twice (the last line of a response written again too).
  append(main, [claudeLine("m2", starts[1]! + 1, "claude-opus-5-5", usage(20, 0, 0, 0, 9)), claudeLine("m3", starts[2]! + 1, "claude-opus-5-5", usage(30, 0, 0, 0, 3))]);
  assert.equal(await r.usage.read(), 1);
  const all = r.store.usageGroups(0, MAX, 0);
  const total = (f: (g: UsageGroup) => number) => all.reduce((s, g) => s + f(g), 0);
  assert.deepEqual([total((g) => g.calls), total((g) => g.input), total((g) => g.output)], [4, 65, 1 + 9 + 5 + 3]);
  const job = all.find((g) => g.input === 30)!;
  assert.deepEqual([job.person, job.thread], ["a@x", chat.id]);
  assert.equal(r.store.usageSince(), starts[0]! + 1);

  // Its session gone, what it spent stays.
  r.store.deleteSession("ember:c-1");
  assert.equal(r.store.usageGroups(0, MAX, 0).reduce((s, g) => s + g.calls, 0), 4);
});

test("each part's calls are put to the turns they were made in, those turns alone read", async () => {
  const time = await today();
  const pause = () => time.adjust(15);
  const r = rig({ clock: time.clock });
  const workspace = join(r.data, "sessions/ember/c-1/workspace");
  session(r.store, "ember:c-1", workspace, r.store.now());
  const chat = r.store.openThreadOf("ember", "ember", "1.0", null, "creator@x", "ember:c-1");
  r.store.joinThread(chat.id, "ember:c-1", "ember");
  // The turns read for each part: from when its first call was made until its last.
  const real = r.store.usageTurns.bind(r.store);
  const asked: [number, number][] = [];
  r.store.usageTurns = (key: string, from: number, until: number) => (asked.push([from, until]), real(key, from, until));
  await pause();
  r.store.startTurnFor("t1", "ember:c-1", "input", { profile: "cc", person: "a@x", thread: chat.id });
  const main = join(r.data, "transcripts/claude", claudeProject(workspace), "r1.jsonl");
  let last = 0;
  const at = () => (last = r.store.now() + 1);
  append(main, [claudeLine("m1", at(), "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
  assert.equal(await r.usage.read(), 1);
  assert.deepEqual(asked.at(-1), [last, last]);
  // The same turn going on: read on from where it was left.
  await pause();
  append(main, [claudeLine("m2", at(), "claude-opus-5-5", usage(2, 0, 0, 0, 1))]);
  assert.equal(await r.usage.read(), 1);
  assert.deepEqual(asked.at(-1), [last, last]);
  // A turn begun (a job's notice: for whom the one before worked), and a message taken during it.
  await pause();
  r.store.startTurn("t2", "ember:c-1", "job");
  append(main, [claudeLine("m3", at(), "claude-opus-5-5", usage(3, 0, 0, 0, 1))]);
  assert.equal(await r.usage.read(), 1);
  assert.deepEqual(asked.at(-1), [last, last]);
  await pause();
  const [n] = r.store.insertMessage(newMessage(chat.id, "2.0", "person", "b@x", "再看看"));
  r.store.deliver(chat.id, n, ["ember:c-1"]);
  r.store.markDelivered("ember:c-1", [{ thread: chat.id, n, apart: false }]);
  append(main, [claudeLine("m4", at(), "claude-opus-5-5", usage(4, 0, 0, 0, 1))]);
  assert.equal(await r.usage.read(), 1);
  assert.deepEqual(asked.at(-1), [last, last]);
  // Each for whom its turn worked: the job's and the one during it for the person before.
  assert.deepEqual(r.store.usageGroups(0, MAX, 0).map((g) => [g.calls, g.input, g.person, g.thread]), [[4, 10, "a@x", chat.id]]);
});

test("days are the asker's own", async () => {
  const r = rig();
  const workspace = join(r.data, "w");
  session(r.store, "k", workspace, 0);
  // 2026-10-01T23:30Z: still the 1st in UTC, the 2nd in UTC+8.
  const at = parseIso("2026-10-01T23:30:00.000Z")!;
  append(join(r.data, "transcripts/claude", claudeProject(workspace), "r.jsonl"), [claudeLine("m", at, "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
  await r.usage.read();
  assert.equal(r.store.usageGroups(0, MAX, 0)[0]!.day, "2026-10-01");
  assert.equal(r.store.usageGroups(0, MAX, 480)[0]!.day, "2026-10-02");
  assert.deepEqual(r.store.usageGroups(at + 1, MAX, 0), []);
});

/// All of a read_from: its text and where it ends; null for nothing.
async function readAll(path: string, offset: number): Promise<[string, number] | null> {
  let text = "";
  let end: number | null = null;
  for await (const part of readFrom(path, offset)) {
    text += part.text;
    end = part.offset;
  }
  return end === null ? null : [text, end];
}

const pack = (path: string) => {
  writeFileSync(`${path}.zst`, zstdCompressSync(readFileSync(path)));
  unlinkSync(path);
};
const restore = (path: string) => {
  writeFileSync(path, zstdDecompressSync(readFileSync(`${path}.zst`)));
  unlinkSync(`${path}.zst`);
};

test("compressed history keeps usage offsets and sub-agent discovery", async () => {
  const root = tempdir();
  const main = join(root, "session.jsonl");
  const sub = join(root, "session/subagents/agent.jsonl");
  mkdirSync(dirname(sub), { recursive: true });
  writeFileSync(main, "first\nsecond\n");
  writeFileSync(sub, "child\n");
  pack(main);
  pack(sub);
  assert.deepEqual(await readAll(main, 6), ["second\n", 13]);
  assert.equal(await readAll(main, 13), null);
  const files = await claudeFiles(root, "session");
  assert.ok(files.some(([p, s]) => p === main && !s));
  assert.ok(files.some(([p, s]) => p === sub && s));
  restore(main);
  appendFileSync(main, "third\n");
  assert.deepEqual(await readAll(main, 13), ["third\n", 19]);
});

test("as the station starts, a transcript put away after it was read is not read again; one never read is", async () => {
  const r = rig();
  const read = join(r.data, "w1");
  const never = join(r.data, "w2");
  session(r.store, "k1", read, 0);
  session(r.store, "k2", never, 0);
  const first = join(r.data, "transcripts/claude", claudeProject(read), "r1.jsonl");
  append(first, [claudeLine("m1", 1000, "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
  assert.equal(await r.usage.read(), 1);
  // Put away with a call the count never saw: a station starting again reads it no more (were it decompressed, it would
  // be counted).
  append(first, [claudeLine("m2", 2000, "claude-opus-5-5", usage(2, 0, 0, 0, 2))]);
  pack(first);
  const second = join(r.data, "transcripts/claude", claudeProject(never), "r2.jsonl");
  append(second, [claudeLine("m3", 3000, "claude-opus-5-5", usage(3, 0, 0, 0, 3))]);
  pack(second);
  const again = new UsageCounter({ store: r.store, config: () => ({ dataDir: r.data, profiles: [{ home: join(r.data, "homes/cc") }] }) });
  counters.push(again);
  assert.equal(await again.read(), 1);
  assert.deepEqual(r.store.usageGroups(0, MAX, 0).map((g) => g.input).sort(), [1, 3]);
});

test("a large compressed file is read in parts from its offset, and from its start once shorter than that", async () => {
  const root = tempdir();
  const path = join(root, "big.jsonl");
  const line = (i: number) => `${String(i).padStart(6, "0")}${"y".repeat(99_993)}\n`;
  const text = Array.from({ length: 30 }, (_, i) => line(i)).join("") + "partial";
  writeFileSync(path, text);
  pack(path);
  const whole = text.length - "partial".length;
  const offsets: number[] = [];
  let read = "";
  for await (const p of readFrom(path, line(0).length * 7)) {
    offsets.push(p.offset);
    read += p.text;
  }
  assert.ok(offsets.length > 1, "in parts");
  assert.equal(offsets.at(-1), whole);
  assert.equal(read, text.slice(line(0).length * 7, whole));
  assert.deepEqual(await readAll(path, whole), null);
  assert.deepEqual(await readAll(path, whole + 100), [text.slice(0, whole), whole]);
});

test("a file read in parts records each part's whole lines and leaves a partial last line for later", async () => {
  const root = tempdir();
  const path = join(root, "big.jsonl");
  // Lines past a part's size (1 MiB), and one unfinished.
  const line = `${"x".repeat(300_000)}\n`;
  writeFileSync(path, `${line.repeat(8)}partial`);
  const parts: number[] = [];
  for await (const p of readFrom(path, 0)) parts.push(p.offset);
  assert.ok(parts.length > 1);
  assert.equal(parts.at(-1), line.length * 8);
});

test("a turn's end is read shortly after, and the pages are told", async () => {
  const time = await today();
  const r = rig({ settleMs: 20, safetyMs: 60_000, clock: time.clock });
  const workspace = join(r.data, "w");
  session(r.store, "k", workspace, r.store.now() - 1000);
  const told: StoreChange[] = [];
  r.store.subscribe((c) => told.push(c));
  r.usage.start();
  // Everything read once, it waits (the first wait: the round's).
  await time.begun(1);
  assert.equal(r.usage.readingAll(), false);
  const calls = () => r.store.usageGroups(0, MAX, 0).reduce((s, g) => s + g.calls, 0);
  assert.equal(calls(), 0);
  r.store.startTurn("t1", "k", "input");
  append(join(r.data, "transcripts/claude", claudeProject(workspace), "r.jsonl"), [claudeLine("m", r.store.now() + 1, "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
  // Woken, it lets the burst settle; a turn starting is not its end: it waits again, nothing read (a read would come
  // before that wait).
  await time.begun(2);
  await time.adjust(20);
  await time.begun(3);
  assert.equal(calls(), 0);
  r.store.endTurn("t1", "completed", null, null, null);
  await time.begun(4);
  await time.adjust(20);
  await time.begun(5);
  assert.equal(calls(), 1);
  // Told once the read is over (the rows are there a moment before), with the sessions it counted anew.
  assert.deepEqual(told.filter((c) => c.type === "usage"), [{ type: "usage", sessions: ["k"] }]);
  await r.usage.stop();
});

test("asked, a working session is read before its turn ends; its execution details add it up and price it", async () => {
  const time = await today();
  const r = rig({ settleMs: 20, safetyMs: 60_000, clock: time.clock });
  const workspace = join(r.data, "w");
  session(r.store, "k", workspace, r.store.now() - 1000);
  r.usage.start();
  await time.begun(1);
  r.store.startTurn("t1", "k", "input");
  const project = join(r.data, "transcripts/claude", claudeProject(workspace));
  const at = r.store.now() + 1;
  append(join(project, "r.jsonl"), [claudeLine("m", at, "claude-opus-5-5", usage(10, 1000, 0, 0, 100))]);
  await time.begun(2);
  await time.adjust(20);
  await time.begun(3);
  assert.deepEqual(r.store.usageOfSession("k"), [], "a turn starting is not its end");
  // Another at work, not asked of: not read with it.
  const other = join(r.data, "w2");
  session(r.store, "j", other, r.store.now() - 1000);
  r.store.startTurn("t2", "j", "input");
  append(join(r.data, "transcripts/claude", claudeProject(other), "r.jsonl"), [claudeLine("n", r.store.now() + 1, "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
  await time.begun(4);
  await time.adjust(20);
  await time.begun(5);
  r.usage.soon("k");
  await time.begun(6);
  await time.adjust(20);
  await time.begun(7);
  // Opus 5.5: $4 in, $0.2 read, $20 out.
  r.store.setRuntimeSessionId("k", "r");
  assert.deepEqual(usageNow(r.store, "k"), {
    modelCalls: 1, inputTokens: 1010, cachedTokens: 1000, outputTokens: 100, cost: (10 * 4 + 1000 * 0.2 + 100 * 20) / 1e6, unpricedCalls: 0,
    model: "claude-opus-5-5", contextTokens: 1010, contextWindow: null, lastCallAt: at,
  });
  assert.deepEqual(r.store.usageOfSession("j"), [], "only the one asked of");
  await r.usage.stop();
});

test("a session's usage says how long its cache lasts after its last call, by what it last wrote, and what reading it all again costs", () => {
  const call = (at: number, cacheWrite: number, cacheWriteLong: number, fast = false) =>
    ({ turn: "t", profile: null, model: "claude-opus-5-5", context: 200_000, window: null, at, fast, cacheWrite, cacheWriteLong });
  const groups: UsageGroup[] = [{ day: "", session: "k", thread: null, person: null, profile: null, runtime: "claude", model: "claude-opus-5-5", fast: false, calls: 3, input: 0, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0 }];
  const of = (calls: ReturnType<typeof call>[]) => usageNow({ usageOfSession: () => groups, lastContexts: (_, limit) => calls.slice(-limit), conversationSince: () => 0 }, "k")!;
  // An hour's write, then a call that only read: an hour from the last; all of it written for an hour again at $4 ×2.
  const long = of([call(1000, 0, 5000), call(2000, 0, 0)]);
  assert.deepEqual([long.lastCallAt, long.cacheMs, long.rereadCost], [2000, 3_600_000, (200_000 * 4 * 2) / 1e6]);
  // Five minutes', in fast mode: twice the price.
  const short = of([call(1000, 0, 5000), call(2000, 300, 0, true)]);
  assert.deepEqual([short.cacheMs, short.rereadCost], [300_000, ((200_000 * 4 * 1.25) / 1e6) * 2]);
  // Nothing told of what was written (Codex): not said how long it lasts.
  const none = of([call(1000, 0, 0)]);
  assert.deepEqual([none.lastCallAt, none.cacheMs, none.rereadCost], [1000, undefined, undefined]);
});

// ── against the Rust's own count, on a copy of a real station ──

const WORK = process.env.USAGE_WORK ?? "/tmp/usage-work";
const SNAPSHOT = join(WORK, "transcripts");

type DayTotal = { day: string; calls: number; input: number; cacheRead: number; cacheWrite: number; cacheWriteLong: number; output: number };
const DAYS = `SELECT strftime('%Y-%m-%d', at / 1000, 'unixepoch') AS day, COUNT(*) AS calls, SUM(input) AS input, SUM(cache_read) AS cacheRead,
  SUM(cache_write) AS cacheWrite, SUM(cache_write_long) AS cacheWriteLong, SUM(output) AS output FROM usage GROUP BY day ORDER BY day`;
const ROWS = "SELECT id, at, session, turn, thread, person, profile, runtime, model, subagent, fast, input, cache_read, cache_write, cache_write_long, output FROM usage";

test("on a real station's copy, the calls counted are the Rust's", { skip: !existsSync(SNAPSHOT) && `no ${SNAPSHOT}` }, async (t) => {
  // The copy holds what the Rust recorded; its transcripts (cut where the Rust's offsets stood) are at SNAPSHOT.
  const dir = tempdir();
  copyFileSync(join(WORK, "stillfail.db"), join(dir, "stillfail.db"));
  if (existsSync(join(WORK, "stillfail.db-wal"))) copyFileSync(join(WORK, "stillfail.db-wal"), join(dir, "stillfail.db-wal"));
  symlinkSync(SNAPSHOT, join(dir, "transcripts"));
  const store = Store.open(join(dir, "stillfail.db"), join(dir, "archive"));
  stores.push(store);
  store.db.exec("DELETE FROM usage; DELETE FROM usage_files");
  const counter = new UsageCounter({ store, config: () => ({ dataDir: dir, profiles: [] }) });

  // How long the main thread is held while it reads: a 1 ms timer's lateness, and the event loop's delay.
  const delay = monitorEventLoopDelay({ resolution: 1 });
  delay.enable();
  let worst = 0;
  let previous = performance.now();
  const probe = setInterval(() => {
    const now = performance.now();
    worst = Math.max(worst, now - previous);
    previous = now;
  }, 1);
  const began = performance.now();
  const added = await counter.read();
  const took = performance.now() - began;
  clearInterval(probe);
  delay.disable();
  const again = performance.now();
  const more = await counter.read();
  const tookAgain = performance.now() - again;
  t.diagnostic(`first read: ${added} calls in ${Math.round(took)} ms; longest gap between 1 ms ticks ${worst.toFixed(1)} ms; ` +
    `loop delay p50 ${(delay.percentile(50) / 1e6).toFixed(1)} ms, p99 ${(delay.percentile(99) / 1e6).toFixed(1)} ms, max ${(delay.max / 1e6).toFixed(1)} ms`);
  t.diagnostic(`second read: ${more} new calls in ${Math.round(tookAgain)} ms`);

  const rust = new DatabaseSync(join(WORK, "stillfail.db"), { readOnly: true });
  const theirs = rust.prepare(DAYS).all() as DayTotal[];
  const ours = store.db.prepare(DAYS).all() as DayTotal[];
  const byId = (db: DatabaseSync) => new Map((db.prepare(ROWS).all() as any[]).map((r) => [r.id, r]));
  const [a, b] = [byId(rust), byId(store.db)];
  const missing = [...a.keys()].filter((id) => !b.has(id));
  const extra = [...b.keys()].filter((id) => !a.has(id));
  const fields = ["at", "session", "turn", "thread", "person", "profile", "runtime", "model", "subagent", "fast", "input", "cache_read", "cache_write", "cache_write_long", "output"];
  const differ = new Map<string, number>();
  for (const [id, r] of a) {
    const o = b.get(id);
    if (!o) continue;
    for (const f of fields) if (r[f] !== o[f]) differ.set(f, (differ.get(f) ?? 0) + 1);
  }
  t.diagnostic(`rows: Rust ${a.size}, TS ${b.size}; only the Rust's ${missing.length}, only the TS's ${extra.length}; fields differing: ${JSON.stringify(Object.fromEntries(differ))}`);
  t.diagnostic(`days: ${theirs.length}; differing: ${JSON.stringify(theirs.filter((d, i) => JSON.stringify(d) !== JSON.stringify(ours[i])).map((d) => d.day))}`);
  rust.close();
  assert.deepEqual(ours, theirs);
  assert.equal(more, 0);
});

test("a session's summary says what its calls used as recorded: added up and priced, and where its last call of its own left its context", () => {
  const store = Store.open(":memory:", null);
  stores.push(store);
  store.insertSession({ key: "k", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/k", token: "k", createdAt: 1, lastActiveAt: 1, runtimeSessionId: "r1" });
  keepUsage(store, "k");
  assert.equal(store.sessionUsage("k"), null, "no call: none");
  const of = { turn: null, person: null, thread: null, profile: "cc" };
  const call = (id: string, at: number, subagent: boolean, input: number, window: number | null = null): [UsageCall, UsageFor] => [
    { id, at, model: subagent ? "claude-haiku-4-5" : "claude-opus-5-5", subagent, fast: false, input, cacheRead: 100, cacheWrite: 10, cacheWriteLong: 0, output: 5,
      calls: 1, context: subagent ? null : input + 110, window },
    of,
  ];
  store.recordUsage("/t.jsonl", { session: "k", offset: 1, model: null }, "claude", [call("a", 1000, false, 1), call("b", 2000, false, 2, 1000), call("c", 3000, true, 50)]);
  keepUsage(store, "k", true);
  const kept = store.sessionUsage("k");
  // The model, the context and the window of its last call of its own (not a subagent's).
  assert.deepEqual([kept.modelCalls, kept.inputTokens, kept.cachedTokens, kept.outputTokens, kept.model, kept.contextTokens, kept.contextWindow], [3, 383, 300, 15, "claude-opus-5-5", 112, 1000]);
  assert.ok(kept.cost > 0);
  assert.deepEqual(kept, usageNow(store, "k"), "as its chat says it while it works");
  // A context not told is not said.
  store.recordUsage("/t.jsonl", { session: "k", offset: 2, model: null }, "claude", [[{ ...call("d", 4000, false, 3)[0], context: null }, of]]);
  keepUsage(store, "k", true);
  assert.deepEqual([store.sessionUsage("k").modelCalls, "contextTokens" in store.sessionUsage("k")], [4, false]);
  // Its context cleared (换新上下文): none said, nor when its cache is over, until its next conversation's first call.
  const context = () => {
    const u = store.sessionUsage("k");
    return [u.modelCalls, u.contextTokens, u.lastCallAt];
  };
  store.recordUsage("/t.jsonl", { session: "k", offset: 3, model: null }, "claude", [call("e", 5000, false, 4)]);
  keepUsage(store, "k", true);
  assert.deepEqual(context(), [5, 114, 5000]);
  store.setRuntimeSessionId("k", null);
  keepUsage(store, "k", true);
  assert.deepEqual(context(), [5, undefined, undefined], "cleared");
  const began = store.now();
  store.ranIn("k", "r2", "cc");
  store.setRuntimeSessionId("k", "r2");
  keepUsage(store, "k", true);
  assert.deepEqual(context(), [5, undefined, undefined], "a new conversation, before its first call");
  store.recordUsage("/t2.jsonl", { session: "k", offset: 1, model: null }, "claude", [call("f", began + 1000, false, 6)]);
  keepUsage(store, "k", true);
  assert.deepEqual(context(), [6, 116, began + 1000], "its first call");
});
