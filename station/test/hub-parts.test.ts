// The hub's parts that compute (ported with their Rust tests): splitting for Slack, commands, image sizes, local file
// links, the live view, the agent home, the account pool, the decision protocol, references to other chats.
import assert from "node:assert/strict";
import { appendFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { brief, claudeProject, readTimeline, sessionPlaces, transcriptPaths } from "../src/read/transcript.ts";
import { linkTranscripts, sessionSkills, unlinkAgentHome, writeBuiltinSkills } from "../src/sessions/agent-home.ts";
import { isSlackMethod, isStopCommand, slackWithFiles, threadCommand } from "../src/sessions/args.ts";
import { splitForSlack } from "../src/sessions/chat.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { completionQuestion, parse, request } from "../src/sessions/decision.ts";
import { sizeOf } from "../src/sessions/image-size.ts";
import { nextTsAt } from "../src/sessions/internal.ts";
import { HELD_AFTER_MS, type History, type LiveMessage, LiveHub, briefInput, inBrief } from "../src/sessions/live.ts";
import type { SessionUsage } from "../src/read/usage.ts";
import { chainOf, entriesOf, lengthOf, stateOf } from "../src/read/transcripts.ts";
import { prepare, prepareHere } from "../src/sessions/local-links.ts";
import { formatSteps, linkedSession } from "../src/sessions/others.ts";
import { availableEfforts, cheapToLeave, commonEfforts, pickProfile, serves, urgency } from "../src/sessions/pool.ts";
import { spelling } from "../src/sessions/config.ts";
import { settle, testClock } from "./hub-fakes.ts";

const temp = () => mkdtempSync(join(tmpdir(), "hub-parts-"));

test("long text splits on paragraph boundaries", () => {
  const para = "x".repeat(60);
  assert.deepEqual(splitForSlack(Array(5).fill(para).join("\n\n"), 130), [`${para}\n\n${para}`, `${para}\n\n${para}`, para]);
  assert.deepEqual(splitForSlack("", 3500), [""]);
});

test("commands: -stop after mentions, Slack methods by their shape", () => {
  assert.ok(isStopCommand("<@UBOT>  -stop "));
  assert.ok(!isStopCommand("please -stop now"));
  assert.equal(threadCommand("<@UBOT> -Compact"), "compact");
  assert.equal(threadCommand(" -clear "), "clear");
  assert.equal(threadCommand("-clear the cache"), null);
  assert.ok(isSlackMethod("conversations.history") && isSlackMethod("assistant.threads.setStatus"));
  assert.ok(!isSlackMethod("Chat.postMessage") && !isSlackMethod("chat") && !isSlackMethod("chat..x"));
});

test("timestamps only go up", () => {
  const a = nextTsAt(1_000);
  const b = nextTsAt(1_000);
  assert.ok(b > a, `${a} ${b}`);
  assert.equal(nextTsAt(4_102_444_800_000), "4102444800.000000");
});

test("sizes are read from each format's header", () => {
  const be32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
  const png = [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0, 0, 0, 13, ...Buffer.from("IHDR"), ...be32(640), ...be32(480)];
  assert.deepEqual(sizeOf(Buffer.from(png)), [640, 480]);
  assert.deepEqual(sizeOf(Buffer.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 10, 0, 20, 0])), [10, 20]);
  const jpeg = [0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xc0, 0, 17, 8, 1, 44, 0, 200, ...Array(8).fill(0)];
  assert.deepEqual(sizeOf(Buffer.from(jpeg)), [200, 300]);
  assert.equal(sizeOf(Buffer.from("plain text")), null);
});

test("local links and images are delivered once; code and web links are kept", () => {
  const dir = temp();
  const path = join(dir, "a report(1).txt");
  writeFileSync(path, "report");
  const text = `[报告](<${path}>) ![](<file://${path}>) [line](<${path}:12:3>)\n\`[example](/tmp/missing)\`\n\`\`\`md\n[x](/tmp/missing)\n\`\`\`\n[web](https://example.com/a) [chat](/o/ws/st/chat) [cdn](//example.com/a)`;
  const paths: string[] = [];
  const result = prepare(text, paths, dir);
  assert.equal(paths.length, 1);
  assert.ok(result.startsWith("[报告](<a%20report%281%29%2Etxt>) ![](<a%20report%281%29%2Etxt>) [line](<a%20report%281%29%2Etxt>)"), result);
  assert.ok(result.includes("`[example](/tmp/missing)`\n```md\n[x](/tmp/missing)\n```"));
  assert.ok(result.endsWith("[web](https://example.com/a) [chat](/o/ws/st/chat) [cdn](//example.com/a)"));
  assert.equal(prepare(`[![preview](<${path}>)](<${path}>)`, paths, dir), "[![preview](<a%20report%281%29%2Etxt>)](<a%20report%281%29%2Etxt>)");
  rmSync(dir, { recursive: true, force: true });
});

test("explicit files are reused, and missing or colliding files are refused", () => {
  const dir = temp();
  const file = join(dir, "report.txt");
  writeFileSync(file, "one");
  const paths = ["report.txt"];
  prepare(`[report](${file})`, paths, dir);
  assert.equal(paths.length, 1);
  assert.throws(() => prepare("[missing](/tmp/stillfail-no-such-report.txt)", [], dir), /correct the path/);
  mkdirSync(join(dir, "other"));
  const other = join(dir, "other/report.txt");
  writeFileSync(other, "two");
  assert.throws(() => prepare(`[report](${other})`, paths, dir), /same name/);
  // A reference link to a local file is refused: it must be inline.
  assert.throws(() => prepare(`[report][r]\n\n[r]: ${file}`, [], dir), /must use inline Markdown/);
  rmSync(dir, { recursive: true, force: true });
});

test("a relative link names a file in the workspace, or one attached by its name; naming none, it is refused", () => {
  for (const [how, prep] of [["as the station reads it", prepare], ["without the addon", prepareHere]] as const) {
    const dir = temp();
    mkdirSync(join(dir, "films"));
    writeFileSync(join(dir, "films/新建对话-手机.mp4"), "film");
    writeFileSync(join(dir, "report.pdf"), "report");
    // A film in the workspace, as an absolute path would be: attached, the link naming it by its name.
    const paths: string[] = [];
    const out = prep("[手机](films/新建对话-手机.mp4)\n[网页](https://example.com/a) [节](#a) <a@b.co>", paths, dir);
    assert.deepEqual(paths, [join(dir, "films/新建对话-手机.mp4")], how);
    assert.equal(out, `[手机](${encodeURIComponent("新建对话-手机").replace(/-/g, "%2D")}%2Emp4)\n[网页](https://example.com/a) [节](#a) <a@b.co>`, how);
    // One the message attaches with files, by its name: left as it is, the clients place it so.
    const attached = [join(dir, "report.pdf")];
    assert.equal(prep("[报告](report.pdf)", attached, dir), "[报告](report.pdf)", how);
    assert.deepEqual(attached, [join(dir, "report.pdf")], how);
    // Naming nothing a reader could open: refused before it is posted.
    assert.throws(() => prep("[手机](films/missing.mp4)", [], dir), /names no file in the workspace/, how);
    assert.throws(() => prep("[站点](www.example.com)", [], dir), /names no file in the workspace/, how);
    rmSync(dir, { recursive: true, force: true });
  }
});

test("files an app cannot upload stay in still.fail, and the post links there", () => {
  const file = (name: string) => ({ name, path: `/w/uploads/${name}`, size: 1 });
  const [posted, kept] = slackWithFiles("这周的天气", [file("weather.html"), file("shot.png")], "https://e/o/w/s/k");
  assert.equal(posted, "这周的天气\n\n<https://e/o/w/s/k?file=weather.html|在 still.fail 中查看图表和附件>", "the link opens the figure");
  assert.equal(kept, "这周的天气\n\n[weather.html](weather.html)", "the HTML placed so still.fail draws it");
  assert.deepEqual(slackWithFiles("看图：[天气](weather.html)", [file("weather.html")], "L"), ["看图：[天气](weather.html)\n\n<L?file=weather.html|在 still.fail 中查看图表>", "看图：[天气](weather.html)"]);
  assert.deepEqual(slackWithFiles("", [file("a b.pdf")], "L"), ["<L?file=a%20b.pdf|在 still.fail 中查看附件>", ""]);
});

test("posts show in the history where the agent made them, whole", () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const long = "长".repeat(5000);
  const record = (content: unknown[]) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-05T00:00:00Z", message: { content } })}\n`;
  const result = (id: string, text: string) => `${JSON.stringify({ type: "user", timestamp: "2026-10-05T00:00:01Z", message: { content: [{ type: "tool_result", tool_use_id: id, content: text }] } })}\n`;
  writeFileSync(
    path,
    record([{ type: "thinking", thinking: "plan" }, { type: "tool_use", id: "p", name: "mcp__stillfail__chat_post", input: { to: "C1/1.1", text: long, kind: "all_done" } }]) +
      result("p", "Posted to C1/1.1.") +
      record([{ type: "text", text: "after" }]),
  );
  const entries = readTimeline("claude", path);
  assert.deepEqual(entries.map((e) => e.kind), ["thinking", "tool_call", "tool_result", "assistant"]);
  assert.equal(JSON.parse(entries[1]!.text).text, long);
  assert.deepEqual([entries[1]!.callId, entries[2]!.callId, entries[2]!.ok], ["p", "p", true]);
  rmSync(dir, { recursive: true });
});

test("in brief, a history's entries say only what names them; what is short, posts, states and Slack whole", () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const command = `cd station && ${"node --test test/account-proxy.test.ts && ".repeat(120)}true`;
  const record = (content: unknown[]) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-05T00:00:00Z", message: { content } })}\n`;
  const result = (id: string, text: string) => `${JSON.stringify({ type: "user", timestamp: "2026-10-05T00:00:01Z", message: { content: [{ type: "tool_result", tool_use_id: id, content: text }] } })}\n`;
  writeFileSync(
    path,
    record([
      { type: "thinking", thinking: `${"想".repeat(40)}\n${"细节".repeat(400)}` },
      { type: "tool_use", id: "b", name: "Bash", input: { command, description: "Run the tests 3 times", timeout: 600000 } },
    ]) +
      result("b", "ok\n".repeat(400)) +
      record([{ type: "tool_use", id: "r", name: "Read", input: { file_path: "/w/a.ts" } }]) +
      result("r", "short") +
      record([{ type: "tool_use", id: "s", name: "mcp__stillfail__slack_api", input: { method: "chat.postMessage", params: { channel: "C1", text: "嗨".repeat(400) } } }]) +
      result("s", JSON.stringify({ ok: true, ts: "1.2", message: { text: "嗨".repeat(800) } })) +
      record([{ type: "text", text: "说完了".repeat(300) }]),
  );
  const whole = readTimeline("claude", path);
  const short = whole.map(brief);
  assert.deepEqual(short.map((e) => [e.kind, e.brief === true]), [
    ["thinking", true], ["tool_call", true], ["tool_result", true], ["tool_call", false], ["tool_result", false],
    ["tool_call", false], ["tool_result", true], ["assistant", false],
  ]);
  // A thought by its first line; a call by what says what it does, the description whole after a long command.
  assert.equal(short[0]!.text, "想".repeat(40));
  assert.deepEqual(JSON.parse(short[1]!.text), { command: [...command].slice(0, 300).join(""), description: "Run the tests 3 times" });
  // A result without what it gave, but Slack's answer: whether it went, and its ts.
  assert.equal(short[2]!.text, "");
  assert.deepEqual(JSON.parse(short[6]!.text), { ok: true, ts: "1.2" });
  // Everything else as it is, and the whole of each as it was read.
  assert.deepEqual([short[3], short[4], short[5], short[7]], [whole[3], whole[4], whole[5], whole[7]]);
  assert.deepEqual(short.map((e, i) => ({ ...e, text: whole[i]!.text, brief: undefined })), whole.map((e) => ({ ...e, brief: undefined })));
  rmSync(dir, { recursive: true });
});

test("references name sessions in every link form", () => {
  assert.deepEqual(linkedSession("http://127.0.0.1:4760/admin/chats/c-e74a0bfa0b"), ["c-e74a0bfa0b", null]);
  assert.deepEqual(linkedSession("[修 bug](https://ember.3720.org/w/ws1/s/st1/chats/cl%3AC1%3A1.2?x=1)"), ["cl:C1:1.2", null]);
  assert.deepEqual(linkedSession("<https://ember.3720.org/o/ws1/st1/c-abc|在 ember 里查看>"), ["c-abc", null]);
  assert.deepEqual(linkedSession("https://ember.3720.org/w/ws/s/st/chats/c-1?history=c-2&entry=41"), ["c-2", 41]);
  assert.deepEqual(linkedSession("<https://app.still.fail/o/ws1/st1/c-abc|在 still.fail 里查看>"), ["c-abc", null]);
  assert.deepEqual(linkedSession("https://app.still.fail/w/ws1/s/st1/chats/c-2"), ["c-2", null]);
  assert.equal(linkedSession("C1/1.000001"), null);
  assert.equal(linkedSession("c-abc"), null);
});

test("steps are numbered and cut", () => {
  const entry = (kind: string, tool: string | undefined, text: string) => ({ at: "2026-09-29T00:00:00.000Z", kind, text, ...(tool ? { tool } : {}) });
  assert.equal(
    formatSteps(7, [entry("assistant", undefined, "好的"), entry("tool_call", "Bash", "ls -la /tmp")], 4),
    "#7 2026-09-29T00:00:00.000Z assistant:\n好的\n\n#8 2026-09-29T00:00:00.000Z tool_call Bash:\nls -… (7 more characters)",
  );
});

const line = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-09-26T00:00:00Z", message: { id, content: [{ type: "text", text }], usage: { input_tokens: 10, output_tokens: 2 } } })}\n`;

test("a watched session's usage is what the counter recorded, told again as it records more; what its transcript gains, the counter is asked to count", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  let counted: SessionUsage | null = null;
  const asked: string[] = [];
  hub.countWith({ of: () => counted, ask: (key) => void asked.push(key) });
  const got: any[] = [];
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  assert.deepEqual([got[0].usage.modelCalls, got[0].usage.cost], [0, 0], "none recorded yet: none, though its transcript has a call");
  counted = { modelCalls: 4, inputTokens: 900, cachedTokens: 800, outputTokens: 40, cost: 1.5, unpricedCalls: 0, model: "m", contextTokens: 10, contextWindow: null };
  got.length = 0;
  hub.usageCounted();
  assert.equal(got.length, 1);
  assert.deepEqual([got[0].entries, got[0].start, got[0].usage], [[], 1, counted]);
  hub.usageCounted();
  assert.equal(got.length, 1, "told only when it changed");
  appendFileSync(path, line("two", "m2"));
  (hub as any).soon("s");
  await settle();
  await time.adjust(40);
  await settle();
  assert.deepEqual(asked, ["s"], "working on: the counter is asked to count it");
  assert.deepEqual([got.at(-1).entries.map((e: any) => e.text), got.at(-1).usage], [["two"], counted], "what it gained, with what was recorded so far");
  rmSync(dir, { recursive: true, force: true });
});

/// What a LiveHub's watch on a transcript does when the file changes.
const watched = (hub: LiveHub, key: string) => (hub as any).soon(key);

test("a watcher gets what it lacks, the steps in flight, then new entries as the file grows", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1") + line("two", "m2"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  hub.event("s", { kind: "start", id: "x", step: "text" });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "wri" });
  const got: LiveMessage[] = [];
  const id = hub.subscribe("s", 1, null, (m) => void got.push(m));
  assert.equal(got[0]!.type, "timeline");
  assert.deepEqual((got[0] as any).entries.map((e: any) => e.text), ["two"]);
  assert.equal(got[1]!.type, "steps");
  assert.equal((got[1] as any).steps[0].step, "text", "what a step is, not what it wrote");
  got.length = 0;
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "ting" });
  assert.equal(got.length, 0, "a delta sends nothing");
  hub.event("s", { kind: "end", id: "x" });
  appendFileSync(path, line("writing", "m3"));
  // What its watch does on the file's change (that it comes is side/hub-parts.test.ts's): read once the burst is over.
  watched(hub, "s");
  await settle();
  await time.adjust(40);
  await settle();
  const timeline = got.filter((m): m is Extract<LiveMessage, { type: "timeline" }> => m.type === "timeline").at(-1)!;
  assert.deepEqual([timeline.start, timeline.entries.map((e) => e.text)], [2, ["writing"]]);
  hub.turnEnded("s");
  assert.ok(got.some((m) => m.type === "clear"));
  hub.unsubscribe("s", id);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a watcher in brief is told the entries in brief, those it lacks and those written since", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const bash = (id: string, n: number) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-05T00:00:00Z", message: { id, content: [{ type: "tool_use", id, name: "Bash", input: { command: "true && ".repeat(n), description: `Step ${id}` } }] } })}\n`;
  writeFileSync(path, bash("a", 200));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, null, inBrief((m) => void got.push(m)));
  appendFileSync(path, bash("b", 300));
  watched(hub, "s");
  await settle();
  await time.adjust(40);
  await settle();
  const told = got.flatMap((m) => (m.type === "timeline" ? m.entries : []));
  // Each by what says what it does: the description that came after its long command too.
  assert.deepEqual(told.map((e) => [e.brief, JSON.parse(e.text).description]), [[true, "Step a"], [true, "Step b"]]);
  assert.ok(told.every((e) => Array.from(e.text).length < 400));
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a session at work is followed by the station itself: told from where it ends, its last entries before it is done, kept a while after", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1") + line("two", "m2"));
  const time = testClock();
  let reads = 0;
  const hub = new LiveHub(() => (reads++, { runtime: "claude", paths: [path] }), time.clock);
  const told: LiveMessage[] = [];
  const lengths: [string, number][] = [];
  hub.heldTold = (key, m) => void told.push({ ...m, key } as any);
  hub.lengths = (key, n) => void lengths.push([key, n]);
  hub.running("s", true);
  assert.deepEqual(hub.held(), ["s"]);
  // Where it ends, none of what it said before; the steps in flight.
  const start = told.find((m) => m.type === "timeline") as any;
  assert.deepEqual([start.start, start.entries], [2, []]);
  assert.ok(told.some((m) => m.type === "steps"));
  assert.deepEqual(lengths, [["s", 2]]);
  // As a stream that opens finds it.
  assert.deepEqual(hub.now("s").map((m: any) => [m.type, m.start ?? null]), [["timeline", 2], ["steps", null], ["work", null]]);
  told.length = 0;
  // Its last entry, written as its turn ends, is told before it is told to be done (no 40 ms wait).
  appendFileSync(path, line("three", "m3"));
  hub.turnEnded("s");
  const kinds = told.map((m) => m.type);
  assert.ok(kinds.indexOf("timeline") >= 0 && kinds.indexOf("timeline") < kinds.indexOf("clear"), kinds.join());
  assert.deepEqual((told.find((m) => m.type === "timeline") as any).entries.map((e: any) => e.text), ["three"]);
  assert.deepEqual(lengths.at(-1), ["s", 3]);
  // Done: still followed a while, and at work again within it, not read again from the start.
  hub.running("s", false);
  await time.adjust(HELD_AFTER_MS - 1);
  await settle();
  assert.deepEqual(hub.held(), ["s"]);
  hub.running("s", true);
  await time.adjust(HELD_AFTER_MS * 2);
  await settle();
  assert.deepEqual(hub.held(), ["s"]);
  assert.equal(reads, 1, "located and read once");
  // Done for longer than the while: let go.
  hub.running("s", false);
  await time.adjust(HELD_AFTER_MS);
  await settle();
  assert.deepEqual(hub.held(), []);
  told.length = 0;
  appendFileSync(path, line("four", "m4"));
  watched(hub, "s");
  await time.adjust(40);
  await settle();
  assert.equal(told.length, 0, "nothing told of a session let go");
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

/// Where a LiveHub reads a transcript's past (as the readers do: read/transcripts.ts), counting what it is asked.
function historyOf(path: string, asked: string[] = [], hold?: Promise<void>): History {
  return {
    state: async () => (asked.push("state"), stateOf("claude", [path], null)),
    page: async (_key, before, limit, briefed) => {
      asked.push(`page ${before} ${limit} ${briefed}`);
      await hold;
      const chain = chainOf("claude", [path], null);
      const end = lengthOf(chain);
      const upto = Math.min(before, end);
      const start = Math.max(0, upto - limit);
      return { start, entries: entriesOf("claude", chain, start, upto, briefed), end };
    },
  };
}

test("where the readers keep a session's history the live view reads none of its past: it goes on from where they stand, a listener given what it lacks from them, in brief once", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const bash = (id: string, n: number) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-05T00:00:00Z", message: { id, content: [{ type: "tool_use", id, name: "Bash", input: { command: "true && ".repeat(n), description: `Step ${id}` } }] } })}\n`;
  writeFileSync(path, line("one", "m1") + bash("b", 200) + line("three", "m3"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  const asked: string[] = [];
  hub.history = historyOf(path, asked);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 1, null, (m) => void got.push(m), true);
  assert.equal(got.length, 0, "where it stands is read off the main thread first");
  await settle();
  const first = got[0] as Extract<LiveMessage, { type: "timeline" }>;
  assert.deepEqual([first.type, first.start, first.entries.length], ["timeline", 1, 2]);
  assert.equal(JSON.parse(first.entries[0]!.text).description, "Step b", "in brief, once");
  assert.equal(got[1]!.type, "steps");
  // Its checklist read back from the latest page, whole; then what it lacks, in brief.
  assert.deepEqual(asked, ["state", "page 3 3 false", "page 3 2 true"]);
  // None of it kept here: only where it stands.
  const watching = (hub as any).watched.get("s");
  assert.deepEqual([watching.tail.keeps, watching.tail.length, watching.tail.entries.length], [false, 3, 0]);
  // Written on: read here from where the readers stood, told in brief.
  got.length = 0;
  appendFileSync(path, bash("d", 300));
  watched(hub, "s");
  await time.adjust(40);
  await settle();
  const told = got.find((m): m is Extract<LiveMessage, { type: "timeline" }> => m.type === "timeline")!;
  assert.deepEqual([told.start, told.entries[0]!.brief, JSON.parse(told.entries[0]!.text).description], [3, true, "Step d"]);
  // A page of it (session_history): from the readers, whole.
  const page = await hub.page("s", Number.MAX_SAFE_INTEGER, 2);
  assert.deepEqual([page!.start, page!.end, page!.entries.map((e) => e.kind)], [2, 4, ["assistant", "tool_call"]]);
  assert.ok(Array.from(page!.entries[1]!.text).length > 600, "whole");
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("what is said while a listener joins is told it after what it lacks", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1") + line("two", "m2"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  let release = () => {};
  hub.history = historyOf(path, [], new Promise<void>((r) => (release = r)));
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  await settle();
  hub.event("s", { kind: "phase", phase: "working" });
  assert.equal(got.length, 0);
  release();
  await settle();
  assert.deepEqual(got.map((m) => m.type), ["timeline", "steps", "work", "step"]);
  assert.deepEqual((got[0] as any).entries.map((e: any) => e.text), ["one", "two"]);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a watcher can take only the latest entries, and ask for those before", () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1") + line("two", "m2") + line("three", "m3"));
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }));
  const texts = (r: [number, { text: string }[]] | null) => r && [r[0], r[1].map((e) => e.text)];
  // Not watched yet: read for the asking.
  assert.deepEqual(texts(hub.before("s", 2, 1)), [1, ["two"]]);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, 1, (m) => void got.push(m));
  assert.deepEqual([(got[0] as any).start, (got[0] as any).entries.map((e: any) => e.text)], [2, ["three"]]);
  // Watched: from what is held.
  assert.deepEqual(texts(hub.before("s", 2, 5)), [0, ["one", "two"]]);
  assert.deepEqual(texts(hub.before("s", 0, 5)), [0, []]);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a session gone on in a new runtime session: its history reads on from the transcript it left into the new one", async () => {
  const dir = temp();
  const left = join(dir, "a.jsonl");
  const now = join(dir, "b.jsonl");
  writeFileSync(left, line("one", "m1"));
  let paths = [left];
  const time = testClock();
  let current = true;
  const hub = new LiveHub(() => ({ runtime: "claude", paths, current }), time.clock);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  // The one left gets its last words, then the session moves on: its new transcript is written only once the
  // conversation begins, after it moved.
  appendFileSync(left, line("two", "m2"));
  current = false;
  hub.moved("s");
  writeFileSync(now, line("three", "m3"));
  paths = [left, now];
  current = true;
  watched(hub, "s");
  await settle();
  await time.adjust(40);
  await settle();
  appendFileSync(now, line("four", "m4"));
  watched(hub, "s");
  await settle();
  await time.adjust(40);
  await settle();
  const told = () => got.flatMap((m) => (m.type === "timeline" ? m.entries.map((e, i) => `${m.start + i}:${e.text}`) : []));
  assert.deepEqual(told(), ["0:one", "1:two", "2:three", "3:four"]);
  assert.deepEqual(hub.before("s", 10, 10)![1].map((e) => e.text), ["one", "two", "three", "four"]);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a session's transcripts are found in the shared place, else in the home of whichever account wrote them; the current one's once written", () => {
  const dir = temp();
  const [a, b] = [join(dir, "a"), join(dir, "b")];
  mkdirSync(join(a, "projects", "w"), { recursive: true });
  mkdirSync(join(b, "projects", "w"), { recursive: true });
  mkdirSync(join(dir, "transcripts", "claude", "w"), { recursive: true });
  writeFileSync(join(a, "projects", "w", "one.jsonl"), line("one", "m1"));
  writeFileSync(join(b, "projects", "w", "two.jsonl"), line("two", "m2"));
  // Written in a home no profile has any more: in the shared place, as every home the station keeps writes there.
  writeFileSync(join(dir, "transcripts", "claude", "w", "zero.jsonl"), line("zero", "m0"));
  assert.deepEqual(transcriptPaths("claude", dir, [b, a], ["zero", "one", "two", "three"]), {
    paths: [join(dir, "transcripts", "claude", "w", "zero.jsonl"), join(a, "projects", "w", "one.jsonl"), join(b, "projects", "w", "two.jsonl")],
    current: false,
  });
  writeFileSync(join(b, "projects", "w", "three.jsonl"), line("three", "m3"));
  assert.equal(transcriptPaths("claude", dir, [b, a], ["one", "two", "three"]).current, true);
  rmSync(dir, { recursive: true, force: true });
});

test("a Claude transcript is looked for in the project of its session's working directory, the projects listed only for one that ran elsewhere", () => {
  const dir = temp();
  const shared = join(dir, "transcripts", "claude");
  const workspace = join(dir, "sessions", "ember", "c-1", "workspace");
  const moved = join(dir, "repos", "app");
  const [here, there] = [claudeProject(workspace)!, claudeProject(moved)!];
  assert.equal(claudeProject("/Users/a/.stillfail/sessions/ember/c-1/workspace"), "-Users-a--stillfail-sessions-ember-c-1-workspace");
  assert.equal(claudeProject(`/${"x".repeat(200)}`), null, "one Claude Code shortens and hashes");
  for (const project of [here, there, "-old-place", ...Array.from({ length: 40 }, (_, i) => `-other-${i}`)]) mkdirSync(join(shared, project), { recursive: true });
  writeFileSync(join(shared, here, "now.jsonl"), line("now", "m1"));
  writeFileSync(join(shared, there, "since.jsonl"), line("since", "m2"));
  // Before the data directory moved: in a project no place of the session's names.
  writeFileSync(join(shared, "-old-place", "before.jsonl"), line("before", "m0"));
  // Each listing of a directory, counted.
  const listed: string[] = [];
  const real = fs.readdirSync;
  fs.readdirSync = ((path: fs.PathLike, ...rest: unknown[]) => (listed.push(String(path)), (real as (...a: unknown[]) => unknown)(path, ...rest))) as unknown as typeof real;
  syncBuiltinESMExports();
  try {
    const places = sessionPlaces({ cwd: null, workspace });
    assert.deepEqual(transcriptPaths("claude", dir, [], ["now"], places), { paths: [join(shared, here, "now.jsonl")], current: true });
    assert.deepEqual(listed, [], "found where it works: nothing listed");
    // One that ran elsewhere: found by listing the projects, then where it was found.
    assert.deepEqual(transcriptPaths("claude", dir, [], ["before", "now"], places).paths, [join(shared, "-old-place", "before.jsonl"), join(shared, here, "now.jsonl")]);
    assert.equal(listed.length, 1);
    assert.equal(transcriptPaths("claude", dir, [], ["before", "now"], places).paths.length, 2);
    assert.equal(listed.length, 1, "where it was found");
    // Moved to another directory: there first, its workspace's still.
    const both = sessionPlaces({ cwd: moved, workspace });
    assert.deepEqual(both, [moved, workspace]);
    assert.deepEqual(transcriptPaths("claude", dir, [], ["now", "since"], both).paths, [join(shared, here, "now.jsonl"), join(shared, there, "since.jsonl")]);
    assert.equal(listed.length, 1);
    // No places said: every project's looked in, as before.
    assert.deepEqual(transcriptPaths("claude", dir, [], ["since"]).paths, [join(shared, there, "since.jsonl")]);
    assert.equal(listed.length, 2);
    // A new session's, not written yet: the projects listed once, not at each read; once written, where it works.
    assert.deepEqual(transcriptPaths("claude", dir, [], ["fresh"], places), { paths: [], current: false });
    assert.equal(listed.length, 3);
    assert.deepEqual(transcriptPaths("claude", dir, [], ["fresh"], places), { paths: [], current: false });
    assert.equal(listed.length, 3, "not listed again");
    writeFileSync(join(shared, here, "fresh.jsonl"), line("fresh", "m3"));
    assert.deepEqual(transcriptPaths("claude", dir, [], ["fresh"], places), { paths: [join(shared, here, "fresh.jsonl")], current: true });
    assert.equal(listed.length, 3);
  } finally {
    fs.readdirSync = real;
    syncBuiltinESMExports();
  }
  rmSync(dir, { recursive: true, force: true });
});

test("a Codex transcript is looked for through its days once, then where it was found", () => {
  const dir = temp();
  const day = join(dir, "transcripts", "codex", "sessions", "2026", "10", "29");
  mkdirSync(day, { recursive: true });
  for (let i = 1; i < 28; i++) mkdirSync(join(dir, "transcripts", "codex", "sessions", "2026", "10", String(i).padStart(2, "0")), { recursive: true });
  const file = join(day, "rollout-2026-10-29T07-00-00-abc.jsonl");
  writeFileSync(file, "");
  const listed: string[] = [];
  const real = fs.readdirSync;
  fs.readdirSync = ((path: fs.PathLike, ...rest: unknown[]) => (listed.push(String(path)), (real as (...a: unknown[]) => unknown)(path, ...rest))) as unknown as typeof real;
  syncBuiltinESMExports();
  try {
    assert.deepEqual(transcriptPaths("codex", dir, [], ["abc"]).paths, [file]);
    const once = listed.length;
    assert.ok(once > 1);
    assert.deepEqual(transcriptPaths("codex", dir, [], ["abc"]).paths, [file]);
    assert.equal(listed.length, once, "where it was found");
  } finally {
    fs.readdirSync = real;
    syncBuiltinESMExports();
  }
  rmSync(dir, { recursive: true, force: true });
});

test("how fast the model writes is told once half a second of it has come", async (t) => {
  t.mock.timers.enable({ apis: ["Date"], now: 1_000_000 });
  const hub = new LiveHub(() => null);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  hub.event("s", { kind: "start", id: "x", step: "text" });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "x".repeat(400) });
  const rates = () => got.flatMap((m) => (m.type === "rate" ? [m.tokensPerSecond] : []));
  assert.deepEqual(rates(), [], "a first few bytes say nothing of the pace");
  t.mock.timers.tick(600);
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "x".repeat(400) });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "x".repeat(400) });
  assert.equal(rates().length, 1, "then told, and not again within the second");
  assert.ok(rates()[0]! > 0);
  hub.event("s", { kind: "end", id: "x" });
  assert.equal(rates().at(-1), 0);
  assert.ok(!got.some((m) => m.type === "step" && m.event.kind === "delta"), "no delta is told");
  hub.close();
  await settle(1);
});

// For client cores before 0.1.2301, which say what a running call does by its step (a newer one: by its transcript entry).
test("a call's step carries what says what it runs, whole, however long the command before it", () => {
  const description = "Run account-proxy tests 3 times with new mock clock";
  const command = `cd station && ${"node --test test/account-proxy.test.ts && ".repeat(8)}true`;
  const hub = new LiveHub(() => null);
  const got: LiveMessage[] = [];
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  hub.event("s", { kind: "start", id: "t", step: "tool", tool: "Bash", input: JSON.stringify({ command, description, timeout: 600000 }) });
  const told = got.flatMap((m) => (m.type === "step" && m.event.kind === "start" ? [m.event.input] : []));
  assert.deepEqual(JSON.parse(told[0]!), { command: [...command].slice(0, 300).join(""), description });
  assert.equal(briefInput("ls -la"), "ls -la", "a runtime's plain input stays as it is");
  assert.equal(briefInput("x".repeat(400)), "x".repeat(300));
  assert.equal(briefInput('{"command": "echo hi", "descrip'), '{"command": "echo hi", "descrip', "an input cut short stays cut short");
  hub.close();
});

test("what stations before linked into the profile homes (the home workspace's memory and skills) is taken away; anything else is left", () => {
  const root = temp();
  const agent = join(root, "agent");
  mkdirSync(join(agent, "skills", "team"), { recursive: true });
  writeFileSync(join(agent, "MEMORY.md"), "# one's\n");
  const [cc, both, synced, own] = [join(root, "cc"), join(root, "both"), join(root, "synced"), join(root, "own")];
  mkdirSync(join(cc, "grok"), { recursive: true });
  symlinkSync(join(agent, "MEMORY.md"), join(cc, "CLAUDE.md"));
  symlinkSync(join(agent, "skills"), join(cc, "skills"));
  symlinkSync(join(agent, "MEMORY.md"), join(cc, "grok", "AGENTS.md"));
  // Under another name (~/.ember is ~/.stillfail): the same.
  symlinkSync(agent, join(root, "alias"));
  mkdirSync(both);
  symlinkSync(join(root, "alias", "MEMORY.md"), join(both, "AGENTS.md"));
  symlinkSync(join(root, "alias", "skills"), join(both, "skills"));
  // A runtime's own skills/ (Claude Code's synced ones) took the shared ones one by one, one of them gone since.
  mkdirSync(join(synced, "skills", "synced", "pdf"), { recursive: true });
  symlinkSync(join(agent, "skills", "team"), join(synced, "skills", "team"));
  symlinkSync(join(agent, "skills", "gone"), join(synced, "skills", "gone"));
  mkdirSync(join(own, "skills", "mine"), { recursive: true });
  writeFileSync(join(own, "CLAUDE.md"), "mine");
  const profiles = [
    { id: "cc", runtimes: ["claude" as const, "grok" as const], home: cc },
    { id: "both", runtimes: ["claude" as const, "codex" as const], home: both },
    { id: "synced", runtimes: ["claude" as const], home: synced },
    { id: "own", runtimes: ["claude" as const], home: own },
  ];
  unlinkAgentHome(agent, profiles);
  unlinkAgentHome(agent, profiles); // idempotent
  assert.deepEqual(readdirSync(cc), ["grok"]);
  assert.deepEqual(readdirSync(join(cc, "grok")), []);
  assert.deepEqual(readdirSync(both), []);
  assert.deepEqual(readdirSync(join(synced, "skills")), ["synced"]);
  assert.equal(readFileSync(join(own, "CLAUDE.md"), "utf8"), "mine");
  assert.deepEqual(readdirSync(join(own, "skills")), ["mine"]);
  // What they linked to stays.
  assert.equal(readFileSync(join(agent, "MEMORY.md"), "utf8"), "# one's\n");
  assert.deepEqual(readdirSync(join(agent, "skills")), ["team"]);
  rmSync(root, { recursive: true, force: true });
});

test("a session's workspace has its workspace's skills where it runs: one gone is taken away, a preset's of the same name left", () => {
  const root = temp();
  const [skills, workspace] = [join(root, "agent", "skills"), join(root, "workspace")];
  for (const name of ["team", "gone", "both"]) {
    mkdirSync(join(skills, name), { recursive: true });
    writeFileSync(join(skills, name, "SKILL.md"), name);
  }
  mkdirSync(join(skills, "notes"));
  mkdirSync(join(workspace, ".claude", "skills", "both"), { recursive: true });
  sessionSkills(workspace, skills);
  rmSync(join(skills, "gone"), { recursive: true });
  sessionSkills(workspace, skills);
  assert.deepEqual(readdirSync(join(workspace, ".claude", "skills")).sort(), ["both", "team"]);
  assert.ok(!lstatSync(join(workspace, ".claude", "skills", "both")).isSymbolicLink());
  assert.deepEqual(readdirSync(join(workspace, ".agents", "skills")).sort(), ["both", "team"]);
  assert.equal(readFileSync(join(workspace, ".agents", "skills", "team", "SKILL.md"), "utf8"), "team");
  rmSync(root, { recursive: true, force: true });
});

test("every profile's transcripts are a runtime's one shared place", () => {
  const root = temp();
  const data = join(root, "data");
  const [both, own] = [join(data, "homes", "both"), join(root, "own")];
  mkdirSync(join(own, "sessions"), { recursive: true });
  linkTranscripts(data, [
    { id: "both", runtimes: ["claude", "codex"], home: both },
    { id: "own", runtimes: ["codex"], home: own },
  ]);
  assert.equal(readlinkSync(join(both, "projects")), join(data, "transcripts/claude"));
  assert.equal(readlinkSync(join(both, "sessions")), join(data, "transcripts/codex"));
  // A home outside the data directory whose runtime keeps its transcripts there already: the person's own, left.
  assert.ok(lstatSync(join(own, "sessions")).isDirectory());
  rmSync(root, { recursive: true, force: true });
});

test("transcripts a home kept itself go to the shared place, a runtime still writing them goes on there, and a home no profile names any more gives its own", () => {
  const data = temp();
  const shared = join(data, "transcripts", "claude", "w");
  const [now, was, gone] = [join(data, "homes", "a-sync"), join(data, "homes", "a"), join(data, "homes", "b")];
  const put = (home: string, name: string, text: string) => {
    mkdirSync(join(home, "projects", "w", "s1", "subagents"), { recursive: true });
    writeFileSync(join(home, "projects", "w", name), text);
  };
  // The profile's home was copied (a-sync) while a runtime went on writing in the one it started in (a), which no
  // profile names now; another (b) is a profile's that was removed.
  put(was, "s1.jsonl", line("one", "m1") + line("two", "m2"));
  writeFileSync(join(was, "projects", "w", "s1", "subagents", "agent-x.jsonl"), line("sub", "m9"));
  put(now, "s1.jsonl", line("one", "m1"));
  put(now, "s2.jsonl", line("new", "m3"));
  put(gone, "s0.jsonl", line("old", "m0"));
  // Claude Code's own sessions/ in a home of its: not Codex's transcripts.
  mkdirSync(join(gone, "sessions"), { recursive: true });
  writeFileSync(join(gone, "sessions", "123.json"), "{}");
  linkTranscripts(data, [{ id: "a", runtimes: ["claude"], home: now }]);
  for (const home of [now, was, gone]) assert.equal(readlinkSync(join(home, "projects")), join(data, "transcripts", "claude"));
  assert.ok(lstatSync(join(gone, "sessions")).isDirectory());
  assert.equal(readFileSync(join(shared, "s1.jsonl"), "utf8"), line("one", "m1") + line("two", "m2"), "the copy from before it grew gives way");
  assert.equal(readFileSync(join(shared, "s1", "subagents", "agent-x.jsonl"), "utf8"), line("sub", "m9"));
  assert.equal(readFileSync(join(shared, "s2.jsonl"), "utf8"), line("new", "m3"));
  assert.equal(readFileSync(join(shared, "s0.jsonl"), "utf8"), line("old", "m0"));
  for (const home of [now, was, gone]) assert.deepEqual(readdirSync(home).filter((n) => n.startsWith("projects.")), [], "nothing kept aside");
  // The runtime started in the home it ran in goes on writing there: the same transcript.
  appendFileSync(join(was, "projects", "w", "s1.jsonl"), line("three", "m4"));
  assert.deepEqual(transcriptPaths("claude", data, [now], ["s0", "s1", "s2"]).paths.map((p) => readTimeline("claude", p).map((e) => e.text)), [["old"], ["one", "two", "three"], ["new"]]);
  // Linked again (the config changed): as it is.
  linkTranscripts(data, [{ id: "a", runtimes: ["claude"], home: now }]);
  assert.equal(readFileSync(join(shared, "s1.jsonl"), "utf8"), line("one", "m1") + line("two", "m2") + line("three", "m4"));
  rmSync(data, { recursive: true, force: true });
});

test("a transcript that went its own way in two homes keeps the shared place's and is left aside, not lost", () => {
  const data = temp();
  const [a, b] = [join(data, "homes", "a"), join(data, "homes", "b")];
  for (const [home, text] of [[a, "mine"], [b, "theirs"]] as const) {
    mkdirSync(join(home, "projects", "w"), { recursive: true });
    writeFileSync(join(home, "projects", "w", "s.jsonl"), line(text, "m"));
  }
  linkTranscripts(data, [
    { id: "a", runtimes: ["claude"], home: a },
    { id: "b", runtimes: ["claude"], home: b },
  ]);
  assert.equal(readFileSync(join(data, "transcripts", "claude", "w", "s.jsonl"), "utf8"), line("mine", "m"));
  assert.equal(readlinkSync(join(b, "projects")), join(data, "transcripts", "claude"));
  const aside = readdirSync(b).filter((n) => n.startsWith("projects.unshared"));
  assert.equal(aside.length, 1);
  assert.equal(readFileSync(join(b, aside[0]!, "w", "s.jsonl"), "utf8"), line("theirs", "m"));
  rmSync(data, { recursive: true, force: true });
});

test("the station's own skills are written and kept as the station has them; the feedback skill on the stable channel only", () => {
  const root = temp();
  const home = join(root, "agent");
  mkdirSync(join(home, "skills", "team-skill"), { recursive: true });
  writeFileSync(join(home, "skills", "team-skill", "SKILL.md"), "ours");
  writeBuiltinSkills(home, false);
  // The same skills as the station wrote them before the rename: replaced; one someone added to is left.
  for (const name of ["ember-jobs", "ember-viz"]) {
    mkdirSync(join(home, "skills", name), { recursive: true });
    writeFileSync(join(home, "skills", name, "SKILL.md"), `---\nname: ${name}\n---\n`);
  }
  writeFileSync(join(home, "skills", "ember-viz", "notes.md"), "mine");
  writeBuiltinSkills(home, false);
  assert.ok(!existsSync(join(home, "skills", "ember-jobs")));
  assert.ok(existsSync(join(home, "skills", "ember-viz", "notes.md")));
  const path = join(home, "skills", "stillfail-jobs", "SKILL.md");
  assert.ok(readFileSync(path, "utf8").startsWith("---\nname: stillfail-jobs\n"));
  assert.equal(readFileSync(path, "utf8"), readFileSync(new URL("../src/skills/stillfail-jobs.md", import.meta.url), "utf8"), "the station's text");
  writeFileSync(path, "edited by hand");
  writeBuiltinSkills(home, false);
  assert.ok(readFileSync(path, "utf8").includes("job_start"), "the station's own, as it has it");
  assert.equal(readFileSync(join(home, "skills", "team-skill", "SKILL.md"), "utf8"), "ours", "the team's stay");
  const feedback = join(home, "skills", "stillfail-feedback", "SKILL.md");
  writeBuiltinSkills(home, true);
  assert.ok(readFileSync(feedback, "utf8").includes("feedback_send"));
  writeBuiltinSkills(home, false);
  assert.ok(!existsSync(join(home, "skills", "stillfail-feedback")));
  writeBuiltinSkills(home, true);
  writeFileSync(join(home, "skills", "stillfail-feedback", "notes.md"), "mine");
  writeBuiltinSkills(home, false);
  assert.ok(existsSync(join(home, "skills", "stillfail-feedback", "notes.md")));
  rmSync(root, { recursive: true, force: true });
});

const profile = (id: string, models: string[]) => hubConfig({ profiles: [{ id, runtime: "claude", home: `/h/${id}`, models }] }, "/").profiles[0]!;
const ok = (state: string) => ({ state, detail: "", models: null, checkedAt: 0 });
const quota = (used: number) => ({ state: "ok", windows: [{ label: "5 小时", usedPercent: used, resetsAt: null }], detail: null, checkedAt: 0 });

test("the pool skips broken, spent and unfit profiles, then prefers headroom, then fewer sessions", () => {
  const [a, b, c, d] = [profile("a", ["m1"]), profile("b", ["m1"]), profile("c", ["m1", "m2"]), profile("d", ["m2"])];
  const health: Record<string, any> = { a: { check: ok("failed"), quota: quota(0) }, b: { check: ok("ok"), quota: quota(100) }, c: { check: ok("ok"), quota: quota(60) }, d: { check: ok("ok"), quota: quota(20) } };
  const signals = (load: Record<string, number> = {}, picked: Record<string, number> = {}) => ({ health: (id: string) => health[id], load: (id: string) => load[id] ?? 0, lastPicked: (id: string) => picked[id] ?? 0, now: () => 0 });
  const all = [a, b, c, d];
  assert.equal(pickProfile(all, "m1", signals(), true).id, "c", "a failed, b spent, d lacks m1");
  assert.equal(pickProfile(all, "m2", signals(), true).id, "d", "most headroom");
  assert.equal(pickProfile(all, null, signals(), true).id, "d");
  health.c = { check: ok("ok"), quota: quota(20) };
  assert.equal(pickProfile([c, d], null, signals({ d: 2, c: 1 }), true).id, "c", "fewer sessions");
  assert.equal(pickProfile([c, d], null, signals({}, { c: 5, d: 1 }), true).id, "d", "least recently picked");
  assert.equal(pickProfile([a], "m1", signals(), true).id, "a", "nothing healthy: still one, so the failure shows");
  assert.throws(() => pickProfile([a, b], "m2", signals(), true), /no profile has m2 enabled/);
  assert.equal(pickProfile([a, c], "m9", signals(), false).id, "c", "a connect's binding still runs on its healthy profiles");
});

test("the pool runs sessions on subscriptions, however full, and on an account billed per use only when none can", () => {
  const with_ = (id: string, access: Record<string, unknown>) => hubConfig({ profiles: [{ id, runtime: "claude", home: `/h/${id}`, models: ["m"], access }] }, "/").profiles[0]!;
  const sub = with_("sub", { kind: "subscription" });
  const key = with_("key", { kind: "anthropic-api", key: "k" });
  const gateway = with_("gateway", {});
  const kimi = with_("kimi", { kind: "api-provider", provider: "kimi-code", key: "k" });
  const week = (used: number) => ({ state: "ok", windows: [{ label: "每周", usedPercent: used, resetsAt: null }], detail: null, checkedAt: 0 });
  const perUse = { state: "unsupported", windows: [], detail: "", checkedAt: 0 };
  const health: Record<string, any> = { sub: { check: ok("ok"), quota: week(90) }, key: { check: ok("ok"), quota: perUse }, gateway: { check: ok("ok") }, kimi: { check: ok("ok"), quota: week(95) } };
  const signals = (load: Record<string, number> = {}) => ({ health: (id: string) => health[id], load: (id: string) => load[id] ?? 0, lastPicked: () => 0, now: () => 0 });
  // An unknown allowance counts as half used, an API key's too: it no longer comes before a nearly full subscription.
  assert.equal(pickProfile([key, gateway, sub], "m", signals(), true).id, "sub");
  assert.equal(pickProfile([key, sub], "m", signals({ sub: 9 }), true).id, "sub", "however many sessions it has");
  assert.equal(pickProfile([key, kimi], "m", signals(), true).id, "kimi", "a membership is paid for already");
  // Used up, or a turn on it ran into its allowance: one billed per use takes it on.
  health.sub = { check: ok("ok"), quota: week(100) };
  assert.equal(pickProfile([sub, key], "m", signals(), true).id, "key");
  health.sub = { check: ok("ok"), quota: week(10), spent: true };
  assert.equal(pickProfile([sub, key], "m", signals(), true).id, "key");
});

test("the pool shares sessions by what each account would lose, and keeps them off nearly full five hours", () => {
  const now = 1_791_270_331_000;
  const hours = (h: number) => now + h * 3_600_000;
  const windows = (five: [number, number], week: [number, number]) => ({
    state: "ok",
    windows: [
      { label: "5 小时", usedPercent: five[0], resetsAt: hours(five[1]), minutes: 300 },
      { label: "每周", usedPercent: week[0], resetsAt: hours(week[1]), minutes: 7 * 24 * 60 },
    ],
    detail: null,
    checkedAt: 0,
  });
  // As the station's accounts were on 2026-10-19 before the evening: cuesurf3 and cuesurf4 had the most of their week
  // to lose; every session went to one of them in turn, and ran its five hours out.
  const health: Record<string, any> = {
    s1: { check: ok("ok"), quota: windows([0, 5], [4, 119]) },
    s2: { check: ok("ok"), quota: windows([0, 5], [1, 146]) },
    s3: { check: ok("ok"), quota: windows([10, 3], [30, 58]) },
    s4: { check: ok("ok"), quota: windows([10, 3], [45, 41]) },
    s5: { check: ok("ok"), quota: windows([0, 5], [0, 167]) },
  };
  const all = ["s1", "s2", "s3", "s4", "s5"].map((id) => profile(id, ["m"]));
  const signals = (load: Record<string, number> = {}, picked: Record<string, number> = {}) => ({ health: (id: string) => health[id], load: (id: string) => load[id] ?? 0, lastPicked: (id: string) => picked[id] ?? 0, now: () => now });
  /// Where `n` sessions go, picked one after another as the station does (each counted where it went).
  const spread = (n: number) => {
    const load: Record<string, number> = {};
    for (let i = 0; i < n; i++) {
      const p = pickProfile(all, "m", signals(load), true);
      load[p.id] = (load[p.id] ?? 0) + 1;
    }
    return load;
  };
  const u = (id: string) => urgency(health[id].quota, now);
  assert.ok(Math.abs(u("s4").pace - (0.55 * 168) / 41) < 1e-9, "left × length ÷ time to refill");
  assert.ok(Math.abs(u("s4").weight - u("s4").pace * 0.9) < 1e-9, "times what its five hours have left");
  // The first goes where the most would be lost; twenty are shared by weight, every account taking some.
  assert.equal(pickProfile(all, "m", signals(), true).id, "s4");
  const twenty = spread(20);
  assert.deepEqual(Object.keys(twenty).sort(), ["s1", "s2", "s3", "s4", "s5"]);
  const weights = Object.fromEntries(all.map((p) => [p.id, u(p.id).weight]));
  const total = Object.values(weights).reduce((a, b) => a + b, 0);
  for (const id of Object.keys(weights)) assert.ok(Math.abs(twenty[id]! - (20 * weights[id]!) / total) <= 1, `${id}: ${twenty[id]} of 20`);
  assert.ok(twenty.s4! > twenty.s5!, "the week that would be lost takes more");
  // A week refilling within an hour counts as a day away: it takes more, not all.
  health.s4 = { check: ok("ok"), quota: windows([10, 3], [45, 0.5]) };
  assert.ok(Math.abs(u("s4").pace - 0.55 * 7) < 1e-9);
  assert.ok(spread(20).s4! < 12);
  // Nearly full five hours: last, whatever its week; it takes none while another has room.
  health.s4 = { check: ok("ok"), quota: windows([85, 2.4], [1, 22.9]) };
  assert.equal(u("s4").crowded, true);
  assert.equal(spread(20).s4, undefined);
  // Used up this week: passed over.
  health.s4 = { check: ok("ok"), quota: windows([2, 2.4], [100, 22.9]) };
  assert.equal(spread(20).s4, undefined);
  // Equal allowances: fewer sessions, then the one picked least recently.
  for (const id of ["s3", "s4"]) health[id] = { check: ok("ok"), quota: windows([2, 2], [0, 30]) };
  assert.equal(pickProfile([all[2]!, all[3]!], "m", signals({ s3: 1 }), true).id, "s4");
  assert.equal(pickProfile([all[2]!, all[3]!], "m", signals({}, { s3: 1, s4: 2 }), true).id, "s3");
});

test("a session loses little by moving when its context was just compacted, or is about to be", () => {
  const at = (turn: string, context: number, profile = "p", model: string | null = "m") => ({ turn, profile, model, context });
  const points = new Map([["m", 200_000]]);
  assert.equal(cheapToLeave([], points), false, "nothing known");
  assert.equal(cheapToLeave([at("1", 30_000), at("1", 90_000)], points), false, "growing, far from it");
  assert.equal(cheapToLeave([at("1", 90_000), at("2", 150_000)], points), true, "three quarters of where m is compacted");
  assert.equal(cheapToLeave([at("1", 90_000, "p", "other"), at("2", 190_000, "p", "other")], points), false, "where other is compacted is not known");
  assert.equal(cheapToLeave([at("1", 180_000), at("2", 20_000), at("2", 30_000)], points), true, "compacted in its last turn");
  assert.equal(cheapToLeave([at("1", 180_000), at("1", 20_000), at("2", 30_000)], points), true, "or the one before");
  assert.equal(cheapToLeave([at("1", 180_000), at("1", 20_000), at("2", 30_000), at("3", 40_000)], points), false, "longer ago");
  assert.equal(cheapToLeave([at("1", 180_000, "q"), at("2", 20_000)], points), false, "started over on another account, not compacted");
  assert.equal(cheapToLeave([at("1", 40_000), at("2", 10_000)], points), false, "too little to say");
});

test("a model is served however a profile spells it", () => {
  const [direct, router] = [profile("direct", ["gpt-6-astra"]), profile("router", ["openai/gpt-6-astra"])];
  const health: Record<string, any> = { direct: { check: ok("ok"), quota: quota(100) }, router: { check: ok("ok"), quota: quota(10) } };
  const picked = pickProfile([direct, router], "gpt-6-astra", { health: (id) => health[id], load: () => 0, lastPicked: () => 0, now: () => 0 }, true);
  assert.equal(picked.id, "router", "the direct account is spent; the router's spelling is the same model");
  assert.equal(spelling(picked, "gpt-6-astra"), "openai/gpt-6-astra", "and it runs as the router spells it");
  assert.equal(spelling(direct, "openai/gpt-6-astra"), "gpt-6-astra");
  assert.ok(!serves(direct, "gpt-6"));
});

test("reported levels, aliases, empty and legacy", () => {
  const catalog = { codex: { "gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"], "gpt-6-luna": ["low", "medium", "high", "xhigh", "max"], "no-reasoning": [] } };
  const astra = availableEfforts("codex", "openai/gpt-6-astra", catalog);
  assert.ok(astra.includes("max") && astra.includes("ultra") && !astra.includes("minimal"));
  assert.deepEqual(availableEfforts("codex", "no-reasoning", catalog), []);
  assert.deepEqual(availableEfforts("codex", "unknown", catalog), ["minimal", "low", "medium", "high", "xhigh"]);
  assert.deepEqual(availableEfforts("claude", "gpt-6-astra", catalog), ["low", "medium", "high", "xhigh", "max"]);
  assert.ok(!commonEfforts([astra, availableEfforts("codex", "gpt-6-luna", catalog)], "codex").includes("ultra"));
});

const config = (provider: "jev" | "chat_logprobs") => ({ provider, endpoint: "http://127.0.0.1:1", model: "test", apiKey: "", sessionHeader: false, threshold: 0.85 });

test("native choices are strict, and uncertainty is not completion", () => {
  const c = config("jev");
  const q = completionQuestion();
  const raw: any = { answers: { decision: { type: "choice", probabilities: { complete: 0.9, agent_work: 0.04, human_needed: 0.04, uncertain: 0.02 } } } };
  const accepts = () => {
    const r = parse(c, q, raw);
    return r.selected === "complete" && r.probabilities.complete! >= c.threshold;
  };
  assert.ok(accepts());
  raw.answers.decision.probabilities.complete = 0.6;
  raw.answers.decision.probabilities.uncertain = 0.32;
  assert.ok(!accepts());
  raw.answers.decision.probabilities.complete = -0.1;
  assert.throws(() => parse(c, q, raw));
});

test("incomplete top logprobs never become a confident answer", () => {
  const c = config("chat_logprobs");
  const q = completionQuestion();
  const tokens: any[] = [["A", 0.02], ["B", 0.9], ["C", 0.04], ["D", 0.03]].map(([token, p]) => ({ token, logprob: Math.log(p as number) }));
  const raw = (ts: any[]) => ({ choices: [{ logprobs: { content: [{ top_logprobs: ts }] } }] });
  // Criteria in their names' order (a BTreeMap's): agent_work A, complete B, human_needed C, uncertain D.
  const r = parse(c, q, raw(tokens));
  assert.equal(r.selected, "complete");
  // A choice too unlikely to be among the top tokens counts as none, while the rest hold nearly all of it.
  tokens.pop();
  assert.equal(parse(c, q, raw(tokens)).probabilities.uncertain, 0);
  tokens.shift();
  tokens.shift();
  assert.throws(() => parse(c, q, raw(tokens)), /mass/);
  tokens.unshift({ token: "A", logprob: Math.log(0.02) });
  tokens.push({ token: "D", logprob: -2.0 });
  assert.throws(() => parse(c, q, raw(tokens)));
});

test("requests disable reasoning and keep evidence out of the system prompt", () => {
  const r = request(config("chat_logprobs"), completionQuestion(), { text: "untrusted sample" });
  assert.equal(r.reasoning_effort, "none");
  assert.equal(r.max_completion_tokens, 1);
  assert.ok(!r.messages[0].content.includes("untrusted sample"));
  assert.ok(r.messages[1].content.includes("untrusted sample"));
});

const todos = (id: string, items: [string, string][]) =>
  `${JSON.stringify({ type: "assistant", timestamp: "2026-10-29T00:00:00Z", message: { id, content: [{ type: "tool_use", id, name: "TodoWrite", input: { todos: items.map(([content, status]) => ({ content, status, activeForm: content })) } }] } })}\n`;

test("what a session has going in the background and its checklist are told whole as either changes, past its turns, with how long each task has run", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1") + todos("p1", [["Read", "completed"], ["Fix", "in_progress"]]));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  const got: LiveMessage[] = [];
  const work = () => got.filter((m): m is Extract<LiveMessage, { type: "work" }> => m.type === "work");
  hub.subscribe("s", 0, null, (m) => void got.push(m));
  // As it joins: its checklist as its transcript says it, nothing in the background.
  assert.deepEqual(work().at(-1), { type: "work", tasks: [], plan: [{ text: "Read", status: "completed" }, { text: "Fix", status: "in_progress" }] });
  hub.event("s", { kind: "tasks", tasks: [{ id: "a1", kind: "agent", description: "gaps" }] });
  await time.adjust(65_000);
  hub.event("s", { kind: "tasks", tasks: [{ id: "a1", kind: "agent", description: "gaps" }, { id: "b1", kind: "command", description: "watch CI", startedAt: 60_000 }] });
  assert.deepEqual(work().at(-1)!.tasks, [
    { id: "a1", kind: "agent", description: "gaps", startedAt: 0, elapsedMs: 65_000 },
    { id: "b1", kind: "command", description: "watch CI", startedAt: 60_000, elapsedMs: 5_000 },
  ]);
  // The turn ends: they stay.
  hub.turnEnded("s");
  assert.equal(hub.now("s").find((m) => m.type === "work") !== undefined, true);
  assert.equal((hub.now("s").find((m) => m.type === "work") as any).tasks.length, 2);
  // Its checklist written again: told.
  const before = work().length;
  appendFileSync(path, todos("p2", [["Read", "completed"], ["Fix", "completed"], ["Ship", "in_progress"]]));
  watched(hub, "s");
  await time.adjust(40);
  await settle();
  assert.equal(work().length, before + 1);
  assert.deepEqual(work().at(-1)!.plan.map((p) => p.status), ["completed", "completed", "in_progress"]);
  // Its process ended: nothing in the background.
  hub.event("s", { kind: "tasks", tasks: [] });
  assert.deepEqual(work().at(-1)!.tasks, []);
  // A runtime that says its plan apart (ACP): that one is told.
  hub.event("s", { kind: "plan", plan: [{ text: "Survey", status: "pending" }] });
  assert.deepEqual(work().at(-1)!.plan, [{ text: "Survey", status: "pending" }]);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a session's checklist is read back from its transcript where the readers keep it, as after the station started anew", async () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, todos("p1", [["Old", "pending"]]) + todos("p2", [["Read", "completed"], ["Fix", "in_progress"]]) + line("after", "m3"));
  const time = testClock();
  const hub = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  hub.history = historyOf(path);
  const got: LiveMessage[] = [];
  // Only the latest entry asked for: the checklist is read back from before it all the same.
  hub.subscribe("s", 0, 1, (m) => void got.push(m), true);
  await settle();
  const last = got.filter((m): m is Extract<LiveMessage, { type: "work" }> => m.type === "work").at(-1);
  assert.deepEqual(last?.plan, [{ text: "Read", status: "completed" }, { text: "Fix", status: "in_progress" }]);
  hub.close();
  rmSync(dir, { recursive: true, force: true });
});
