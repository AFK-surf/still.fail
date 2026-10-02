// Slack as a chat surface (chat/slack.rs, chat/names.rs, chat/status.rs tests, ported), against a stand-in for Slack
// (test/slack-fake.ts): events taken from Socket Mode, the socket given up when it goes quiet, posting, history, the
// Web API as the bot, token checks, names kept on disk, and the status line in a thread.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Option, Result } from "effect";
import type { ChatEvent } from "../src/sessions/chat.ts";
import { toolStatus } from "../src/sessions/chat.ts";
import { NameBook } from "../src/slack/names.ts";
import { ThreadStatus } from "../src/slack/status.ts";
import { SlackSurface, toEvent, verifySlackTokens } from "../src/slack/surface.ts";
import { SlackClient } from "../src/slack/web.ts";
import { FakeSlack, bot } from "./slack-fake.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const quiet = async (_: ChatEvent) => {};
const PING = 50;
const STALE = 200;

test("slack events become messages and edits, and the rest is left", () => {
  assert.deepEqual(toEvent({ type: "message", channel: "C1", user: "U1", ts: "2.1", thread_ts: "1.1", text: "hi <@UBOT>" }, "UBOT", "BBOT"), {
    type: "message",
    message: { channel: "C1", threadTs: "1.1", ts: "2.1", user: "U1", text: "hi <@UBOT>", addressed: true },
  });
  // A message of its own starts its thread; a direct message is addressed.
  const dm = toEvent({ type: "message", channel: "D1", channel_type: "im", user: "U1", ts: "3.1", text: "hey" }, "UBOT", "BBOT");
  assert.ok(dm?.type === "message" && dm.message.threadTs === "3.1" && dm.message.addressed);
  const plain = toEvent({ type: "message", channel: "C1", user: "U1", ts: "3.2", text: "chatter" }, "UBOT", "BBOT");
  assert.ok(plain?.type === "message" && !plain.message.addressed);
  const mention = toEvent({ type: "app_mention", channel: "C1", user: "U1", ts: "3.3", text: "yo" }, "UBOT", "BBOT");
  assert.ok(mention?.type === "message" && mention.message.addressed);
  assert.deepEqual(toEvent({ type: "message", subtype: "message_changed", channel: "C1", message: { ts: "2.1", thread_ts: "1.1", text: "new" } }, "UBOT", "BBOT"), {
    type: "changed",
    channel: "C1",
    threadTs: "1.1",
    ts: "2.1",
    text: "new",
  });
  for (const left of [
    { type: "message", subtype: "message_deleted", channel: "C1" },
    { type: "message", channel: "C1", user: "UBOT", ts: "1" },
    { type: "message", subtype: "channel_join", channel: "C1", user: "U1", ts: "1" },
    { type: "reaction_added" },
    { type: "message", subtype: "message_changed", channel: "C1", message: { ts: "2.1", user: "UBOT", text: "mine" } },
  ]) {
    assert.equal(toEvent(left, "UBOT", "BBOT"), null, JSON.stringify(left));
  }
  // Another app's bot is heard like a person (by its bot user, else its bot id); its own bot, by either, is not.
  const other = toEvent({ type: "message", channel: "C1", bot_id: "B2", user: "U2", ts: "4.1", text: "done" }, "UBOT", "BBOT");
  assert.ok(other?.type === "message" && other.message.user === "U2");
  const bare = toEvent({ type: "message", subtype: "bot_message", channel: "C1", bot_id: "B2", ts: "4.2", text: "hook" }, "UBOT", "BBOT");
  assert.ok(bare?.type === "message" && bare.message.user === "B2");
  assert.equal(toEvent({ type: "message", subtype: "bot_message", channel: "C1", bot_id: "BBOT", ts: "4.3" }, "UBOT", "BBOT"), null);
});

test("tokens must be of their kind", () => {
  assert.throws(() => new SlackSurface({ appToken: "xoxb-1", botToken: "xoxb-1" }), /app-level token/);
  assert.throws(() => new SlackSurface({ appToken: "xapp-1", botToken: "xapp-1" }), /bot token/);
});

test("a socket that goes quiet is given up; one that answers pings stays", async () => {
  const fake = await FakeSlack.start();
  try {
    fake.answersPings = false;
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE });
    const started = Date.now();
    const failed = await Effect.runPromise(Effect.flip(surface.runSocket(fake.socketUrl(), quiet)));
    const took = Date.now() - started;
    assert.match(failed.message, /said nothing/);
    assert.ok(took >= STALE && took < STALE * 3, `${took} ms`);

    fake.answersPings = true;
    const staying = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE });
    // Nothing but pongs comes in, for well past STALE: still up.
    const raced = await Effect.runPromise(Effect.result(Effect.timeoutOption(staying.runSocket(fake.socketUrl(), quiet), STALE * 6)));
    assert.ok(Result.isSuccess(raced) && Option.isNone(raced.success), "still running when the time was up");
    assert.ok(staying.socket().connected);
  } finally {
    await fake.close();
  }
});

test("a connected surface takes Socket Mode events, acknowledges those it kept, reconnects when asked, and stops", async () => {
  const fake = await FakeSlack.start();
  bot(fake);
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE * 5 });
  const heard: ChatEvent[] = [];
  let changes = 0;
  surface.onChange(() => changes++);
  try {
    await surface.start(async (event) => {
      if (event.type === "message" && event.message.text === "refuse") throw new Error("not kept");
      heard.push(event);
    });
    assert.deepEqual([surface.botUserId(), surface.botName(), surface.workspace()], ["UBOT", "ember", "T1"]);
    assert.equal(surface.identity()!.botImage, "https://avatars.slack-edge.com/ember_72.png");
    await fake.until("a socket", () => fake.sockets.length === 1 && surface.socket().connected);
    assert.equal(fake.calls("apps.connections.open")[0]!.auth, "xapp-1");
    fake.event("e1", { type: "app_mention", channel: "C1", user: "U1", ts: "5.1", text: "<@UBOT> hi" });
    fake.event("e2", { type: "message", channel: "C1", user: "UBOT", ts: "5.2", text: "mine" });
    fake.event("e3", { type: "message", channel: "C1", user: "U1", ts: "5.3", text: "refuse" });
    fake.send({ type: "hello" });
    await fake.until("two acks", () => fake.acks.length >= 2);
    await sleep(50);
    assert.deepEqual(
      fake.acks.map((a) => a.envelope_id).sort(),
      ["e1", "e2"],
      "what it kept, and what it ignores, acknowledged; what failed is not (Slack sends it again)",
    );
    assert.deepEqual(heard, [{ type: "message", message: { channel: "C1", threadTs: "5.1", ts: "5.1", user: "U1", text: "<@UBOT> hi", addressed: true } }]);
    // Slack rotates connections: asked to, it connects again.
    fake.send({ type: "disconnect", reason: "refresh_requested" });
    await fake.until("a second socket", () => fake.sockets.length === 2 && surface.socket().connected);
    assert.ok(changes >= 3, "the socket's ups and downs are told");
    await surface.stop();
    await fake.until("the socket closed", () => fake.sockets[1]!.readyState === fake.sockets[1]!.CLOSED);
    await sleep(100);
    assert.equal(fake.sockets.length, 2, "stopped: not connected again");
  } finally {
    await surface.stop();
    await fake.close();
  }
});

test("a socket that fails is tried again later, its error said", async () => {
  const fake = await FakeSlack.start();
  bot(fake);
  let opens = 0;
  fake.answer("apps.connections.open", () => (++opens === 1 ? { ok: false, error: "invalid_auth" } : { ok: true, url: fake.socketUrl() }));
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE * 5 });
  try {
    const states: string[] = [];
    surface.onChange(() => states.push(`${surface.socket().connected}:${surface.socket().lastError}`));
    // A short first wait, for the test: the station's is a second.
    (surface as any).backoffMs = 30;
    await surface.start(quiet);
    await fake.until("connected after a failure", () => surface.socket().connected);
    assert.deepEqual(states, ["false:slack apps.connections.open: invalid_auth", "true:null"]);
  } finally {
    await surface.stop();
    await fake.close();
  }
});

test("posts go out as written, a long one in parts; files are uploaded first and shared below the text", async () => {
  const fake = await FakeSlack.start();
  bot(fake);
  const dir = mkdtempSync(join(tmpdir(), "sl-"));
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
  try {
    const thread = { channel: "C1", threadTs: "1.1" };
    const ts = await surface.post(thread, "*hello* <https://x|x>", []);
    const first = fake.calls("chat.postMessage")[0]!;
    assert.deepEqual(first.params, { channel: "C1", thread_ts: "1.1", text: "*hello* <https://x|x>", unfurl_links: "false" });
    assert.equal(first.auth, "xoxb-1");
    assert.equal(ts, "8000001.000100");
    const para = "y".repeat(2000);
    const long = await surface.post(thread, `${para}\n\n${para}`, []);
    assert.equal(fake.calls("chat.postMessage").length, 3);
    assert.equal(long, "8000002.000100", "the first part's ts stands for the whole");
    await assert.rejects(surface.post(thread, "", []), /nothing to post/);

    // Files: the bytes to the address Slack gives, then shared in the thread; with no text, the share's ts.
    const file = join(dir, "shot.png");
    writeFileSync(file, "PNGDATA");
    const uploads: string[] = [];
    fake.answer("files.getUploadURLExternal", { ok: true, upload_url: `${fake.base}/upload-here`, file_id: "F1" });
    fake.answer("upload-here", (s) => (uploads.push(s.body), { ok: true }));
    fake.answer("files.completeUploadExternal", { ok: true, files: [{ id: "F1", shares: { public: { C1: [{ ts: "9.9" }] } } }] });
    assert.equal(await surface.post(thread, "", [{ name: "shot.png", path: file, size: 7 }]), "9.9");
    assert.deepEqual(fake.calls("files.getUploadURLExternal")[0]!.params, { filename: "shot.png", length: "7" });
    assert.deepEqual(uploads, ["PNGDATA"]);
    const shared = fake.calls("files.completeUploadExternal")[0]!.params;
    assert.deepEqual([JSON.parse(shared.files!), shared.channel_id, shared.thread_ts], [[{ id: "F1", title: "shot.png" }], "C1", "1.1"]);
    // An app without files:write: nothing is said.
    fake.answer("files.getUploadURLExternal", { ok: false, error: "missing_scope" });
    const before = fake.calls("chat.postMessage").length;
    await assert.rejects(surface.post(thread, "with a file", [{ name: "shot.png", path: file, size: 7 }]), /slack files.getUploadURLExternal: missing_scope/);
    assert.equal(fake.calls("chat.postMessage").length, before);
  } finally {
    await fake.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("history pages through the thread and gives what came before, the latest at most; people and channels are named", async () => {
  const fake = await FakeSlack.start();
  bot(fake);
  fake.answer("conversations.replies", (s) =>
    s.params.cursor === undefined
      ? { ok: true, messages: [{ ts: "1.1", user: "U1", text: "a" }, { ts: "1.2", bot_id: "B9", text: "b" }], response_metadata: { next_cursor: "c2" } }
      : { ok: true, messages: [{ ts: "1.3", user: "UBOT", text: "c" }, { ts: "1.4", user: "U2", text: "d" }] },
  );
  fake.answer("conversations.info", (s) => (s.params.channel === "D1" ? { ok: true, channel: { id: "D1", is_im: true } } : { ok: true, channel: { id: "C1", name: "general" } }));
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
  try {
    await surface.start(quiet);
    const earlier = await surface.history({ channel: "C1", threadTs: "1.1" }, "1.4", 2);
    assert.deepEqual(earlier, [
      { ts: "1.2", user: "B9", text: "b", fromBot: true },
      { ts: "1.3", user: "UBOT", text: "c", fromBot: true },
    ]);
    assert.deepEqual(fake.calls("conversations.replies").map((c) => c.params.cursor ?? null), [null, "c2"]);
    assert.deepEqual([await surface.userName("U1"), await surface.userEmail("U1")], ["Ada", "ada@example.test"]);
    assert.equal(fake.calls("users.info").filter((c) => c.params.user === "U1").length, 1, "asked once for the connection's lifetime");
    assert.deepEqual([await surface.channelName("C1"), await surface.channelName("D1"), await surface.channelName("C1")], ["general", null, "general"]);
    assert.equal(fake.calls("conversations.info").length, 2);
  } finally {
    await surface.stop();
    await fake.close();
  }
});

test("any Web API method as the bot: structures go as JSON, nulls left out; Slack's refusal and its 429 waits", async () => {
  const fake = await FakeSlack.start();
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
  try {
    await surface.api("chat.postMessage", { channel: "C1", blocks: [{ type: "section" }], unfurl: false, limit: 3, skip: null });
    assert.deepEqual(fake.calls("chat.postMessage")[0]!.params, { channel: "C1", blocks: '[{"type":"section"}]', unfurl: "false", limit: "3" });
    fake.answer("reactions.add", { ok: false, error: "already_reacted" });
    await assert.rejects(surface.api("reactions.add", {}), { message: "slack reactions.add: already_reacted" });
    fake.answer("pins.add", { ok: false });
    await assert.rejects(surface.api("pins.add", {}), { message: "slack pins.add: undefined" });
    let tries = 0;
    fake.answer("users.list", () => (++tries === 1 ? { __status: 429, __headers: { "retry-after": "0" }, __body: { ok: false, error: "ratelimited" } } : { ok: true, members: [] }));
    assert.deepEqual(await surface.api("users.list", {}), { ok: true, members: [] });
    assert.equal(tries, 2);
  } finally {
    await fake.close();
  }
});

test("a token pair is checked without connecting: the bot's identity, or what is wrong with each", async () => {
  const fake = await FakeSlack.start();
  bot(fake, { name: "helper" });
  const client = new SlackClient(fake.base);
  try {
    const [identity, errors] = await verifySlackTokens(client, "xapp-1", "xoxb-1", "zh");
    assert.deepEqual(errors, []);
    assert.deepEqual(identity, { team: "Acme", teamId: "T1", url: "https://acme.slack.com/", botUserId: "UBOT", botName: "helper", botImage: "https://avatars.slack-edge.com/ember_72.png", botId: "BBOT" });
    const [none, wrong] = await verifySlackTokens(client, "xoxb-2", "xapp-2", "zh");
    assert.equal(none, null);
    assert.deepEqual(wrong, ["Bot Token 应该以 xoxb- 开头", "App-Level Token 应该以 xapp- 开头"]);
    fake.answer("auth.test", { ok: false, error: "invalid_auth" });
    fake.answer("apps.connections.open", { ok: false, error: "not_allowed_token_type" });
    const [, refused] = await verifySlackTokens(client, "xapp-1", "xoxb-1", "en");
    assert.equal(refused.length, 2);
    assert.match(refused[0]!, /slack auth\.test: invalid_auth/);
    assert.match(refused[1]!, /slack apps\.connections\.open: not_allowed_token_type/);
  } finally {
    await fake.close();
  }
});

test("a name not known yet is fetched once, kept and told", async () => {
  const dir = mkdtempSync(join(tmpdir(), "nb-"));
  const path = join(dir, "slack-names.json");
  try {
    const book = new NameBook(path, { learnAfterMs: 20, saveAfterMs: 60 });
    let told = 0;
    let asked = 0;
    book.onLearn(() => told++);
    const ada = async () => (asked++, { name: "Ada", email: "ada@x" });
    assert.equal(book.person("u:T:U1", ada), null);
    assert.equal(book.person("u:T:U1", ada), null, "asked again while fetching: not twice");
    assert.equal(book.channel("c:T:D1", async () => null), null);
    assert.equal(book.person("u:T:U9", async () => null), null);
    await sleep(150);
    assert.equal(asked, 1);
    assert.equal(book.person("u:T:U1", ada)?.name, "Ada");
    assert.equal(told, 1, "once per burst");
    // A failed lookup is not tried again for a while.
    let again = 0;
    book.person("u:T:U9", async () => (again++, null));
    await sleep(10);
    assert.equal(again, 0);
    await book.close();
    // Kept on disk: a direct message known to have no name, and the person.
    const kept = JSON.parse(readFileSync(path, "utf8"));
    assert.equal(kept["c:T:D1"].channel, null);
    const reopened = new NameBook(path);
    assert.equal(reopened.person("u:T:U1", ada)?.email, "ada@x");
    assert.equal(reopened.channel("c:T:D1", async () => "never"), null);
    await reopened.close();
    // A broken file: starting empty.
    writeFileSync(path, "{nope");
    const broken = new NameBook(path);
    assert.equal(broken.person("u:T:U1", async () => null), null);
    await broken.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

type Calls = [string, Record<string, string>][];
function recording(fail: string | null): [(method: string, params: [string, string][]) => Promise<void>, Calls] {
  const calls: Calls = [];
  return [
    async (method, params) => {
      calls.push([method, Object.fromEntries(params)]);
      if (fail !== null && method === "assistant.threads.setStatus") throw new Error(`slack assistant.threads.setStatus: ${fail}`);
    },
    calls,
  ];
}
const run = (effect: Effect.Effect<void>) => Effect.runPromise(effect);

test("a thread's status line says what the agent does and goes when it is done", async () => {
  const [call, calls] = recording(null);
  const line = new ThreadStatus(call, run, "C1", "1.1");
  line.say("正在思考…", "1.2");
  await sleep(30);
  line.say("", null);
  await sleep(30);
  assert.deepEqual(
    calls.map(([m, p]) => [m, p.status]),
    [
      ["assistant.threads.setStatus", "正在思考…"],
      ["assistant.threads.setStatus", ""],
    ],
  );
  assert.deepEqual([calls[0]![1].channel_id, calls[0]![1].thread_ts, calls[0]![1].loading_messages], ["C1", "1.1", "正在思考…"]);
  // Changed at most every couple of seconds: what is said meanwhile waits, and only the latest goes.
  const [paced, sent] = recording(null);
  const busy = new ThreadStatus(paced, run, "C1", "1.1");
  busy.say("a", null);
  await sleep(20);
  busy.say("b", null);
  busy.say("c", null);
  await sleep(50);
  assert.deepEqual(sent.map(([, p]) => p.status), ["a"]);
});

test("where Slack will not show a status, an eyes reaction stands in", async () => {
  const [call, calls] = recording("missing_scope");
  const line = new ThreadStatus(call, run, "C1", "1.1");
  line.say("正在运行命令…", "1.2");
  await sleep(30);
  line.say("", null);
  await sleep(30);
  assert.deepEqual(
    calls.map(([m, p]) => [m, p.timestamp ?? null, p.name ?? null]),
    [
      ["assistant.threads.setStatus", null, null],
      ["reactions.add", "1.2", "eyes"],
      ["reactions.remove", "1.2", "eyes"],
    ],
  );
});

test("tool calls in words, by either runtime's names", () => {
  const words = ["Read", "Bash", "exec_command", "apply_patch", "WebSearch", "mcp__ember__chat_post", "something"].map(toolStatus);
  assert.deepEqual(words, ["正在查看文件…", "正在运行命令…", "正在运行命令…", "正在修改文件…", "正在搜索网页…", "正在看 Slack…", "正在处理…"]);
});

test("a surface's status line goes to Slack as the bot", async () => {
  const fake = await FakeSlack.start();
  const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
  try {
    surface.working({ channel: "C1", threadTs: "1.1" }, "1.2", "正在思考…");
    await fake.until("a status", () => fake.calls("assistant.threads.setStatus").length === 1);
    assert.deepEqual(fake.calls("assistant.threads.setStatus")[0]!.params, { channel_id: "C1", thread_ts: "1.1", status: "正在思考…", loading_messages: "正在思考…" });
    assert.equal(fake.calls("assistant.threads.setStatus")[0]!.auth, "xoxb-1");
  } finally {
    await surface.stop();
    await fake.close();
  }
});
