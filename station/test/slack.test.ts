// Slack as a chat surface (chat/slack.rs, chat/names.rs, chat/status.rs tests, ported), against a stand-in for Slack
// (test/slack-fake.ts): events taken from Socket Mode, the socket given up when it goes quiet, posting, history, the
// Web API as the bot, token checks, names kept on disk, and the status line in a thread.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { Clock, Effect, Exit, FiberSet, Option, Result, Scope } from "effect";
import { TestClock } from "effect/testing";
import type { ChatEvent } from "../src/sessions/chat.ts";
import { toolStatus } from "../src/sessions/chat.ts";
import { answerOf, answeredBlocks, questionBlocks } from "../src/slack/cards.ts";
import { NameBook } from "../src/connects/names.ts";
import { ThreadStatus } from "../src/slack/status.ts";
import { SlackSurface, personOf, toEvent, verifySlackTokens } from "../src/slack/surface.ts";
import { SlackClient } from "../src/slack/web.ts";
import { settle, testClock } from "./hub-fakes.ts";
import { FakeSlack, bot } from "./slack-fake.ts";

const quiet = async (_: ChatEvent) => {};
const PING = 50;
const STALE = 200;

// Each test has its own stand-in for Slack, surface and files: they run side by side.
describe("slack", { concurrency: true }, () => {
  test("slack events become messages and edits, and the rest is left", () => {
    assert.deepEqual(toEvent({ type: "agent_session_stopped", channel: "C1", thread_ts: "1.1", event_ts: "3.1", user: "U1" }, "UBOT", "BBOT"), {
      type: "stop", channel: "C1", threadTs: "1.1", ts: "3.1",
    });
    assert.equal(toEvent({ type: "agent_session_stopped", channel: "C1", event_ts: "3.1" }, "UBOT", "BBOT"), null);
    assert.equal(toEvent({ type: "agent_session_stopped", channel: "C1", thread_ts: "1.1", event_ts: "bad" }, "UBOT", "BBOT"), null);
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

  test("files shared with a message come with it, those Slack keeps back without an address", () => {
    const shared = toEvent(
      {
        type: "message",
        subtype: "file_share",
        channel: "C1",
        user: "U1",
        ts: "6.1",
        text: "<@UBOT> 看看",
        files: [
          { id: "F1", name: "image.png", size: 10, mode: "hosted", url_private: "https://files.slack.com/files-pri/T-F1/image.png", url_private_download: "https://files.slack.com/files-pri/T-F1/download/image.png" },
          { id: "F2", title: "doc", mode: "external", url_private: "https://docs.google.com/x" },
          { id: "F3", mode: "hidden_by_limit" },
        ],
      },
      "UBOT",
      "BBOT",
    );
    assert.ok(shared?.type === "message");
    assert.deepEqual(shared.message.files, [
      { id: "F1", name: "image.png", size: 10, url: "https://files.slack.com/files-pri/T-F1/download/image.png" },
      { id: "F2", name: "doc", size: 0, url: null },
      { id: "F3", name: "F3", size: 0, url: null },
    ]);
  });

  test("a shared file is read with the bot's token from Slack only, and a sign-in page is no file", async () => {
    const fake = await FakeSlack.start();
    try {
      const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
      const at = (path: string) => fake.base.replace(/\/api$/, `/${path}`);
      fake.answer("F1/shot.png", { __status: 200, __headers: { "content-type": "image/png" }, __body: "png" });
      const bytes = await surface.download({ id: "F1", name: "shot.png", size: 5, url: at("F1/shot.png") });
      assert.equal(new TextDecoder().decode(bytes), '"png"');
      assert.equal(fake.calls("F1/shot.png")[0]!.auth, "xoxb-1");
      fake.answer("F2/shot.png", { __status: 200, __headers: { "content-type": "text/html" }, __body: "sign in" });
      await assert.rejects(surface.download({ id: "F2", name: "shot.png", size: 5, url: at("F2/shot.png") }), /files:read/);
      await assert.rejects(surface.download({ id: "F3", name: "x", size: 1, url: "https://evil.example/x" }), /not a Slack address/);
      await assert.rejects(surface.download({ id: "F4", name: "x", size: 1, url: null }), /does not give/);
      assert.equal(fake.calls("x").length, 0);
    } finally {
      await fake.close();
    }
  });

  test("tables in blocks and attachments are read with the text, as Markdown tables", () => {
    const link = (url: string, label: string) => ({ type: "rich_text", elements: [{ type: "rich_text_section", elements: [{ type: "link", url, text: label }] }] });
    const table = {
      type: "table",
      rows: [
        [link("https://github.com/o/r/pull/1", "o/r#1 · fix(chat): keep it"), { type: "raw_text", text: "Router 复用老 Task" }],
        [{ type: "raw_text", text: "a | b" }, { type: "rich_text", elements: [{ type: "rich_text_section", elements: [{ type: "user", user_id: "U9" }, { type: "text", text: " line\nnext" }] }] }],
      ],
    };
    const table_md = "| <https://github.com/o/r/pull/1|o/r#1 · fix(chat): keep it> | Router 复用老 Task |\n| --- | --- |\n| a \\| b | <@U9> line next |";
    // As Slack's composer sends one: the table in an attachment, the text without it.
    const composed = toEvent({ type: "app_mention", channel: "C1", user: "U1", ts: "5.1", text: "<@UBOT> review & merge", attachments: [{ blocks: [table] }] }, "UBOT", "BBOT");
    assert.ok(composed?.type === "message");
    assert.equal(composed.message.text, `<@UBOT> review & merge\n\n${table_md}`);
    // As an app posts one: in the blocks, beside the rich text the text already says.
    const posted = toEvent({ type: "message", channel: "C1", user: "U1", ts: "5.2", text: "see", blocks: [{ type: "rich_text", elements: [] }, table] }, "UBOT", "BBOT");
    assert.ok(posted?.type === "message" && posted.message.text === `see\n\n${table_md}`);
    const edited = toEvent({ type: "message", subtype: "message_changed", channel: "C1", message: { ts: "5.1", text: "", blocks: [table] } }, "UBOT", "BBOT");
    assert.ok(edited?.type === "changed" && edited.text === table_md);
  });

  test("tokens must be of their kind", () => {
    assert.throws(() => new SlackSurface({ appToken: "xoxb-1", botToken: "xoxb-1" }), /app-level token/);
    assert.throws(() => new SlackSurface({ appToken: "xapp-1", botToken: "xapp-1" }), /bot token/);
  });

  test("Slack timestamps are mapped to the station clock using a response it already received", async () => {
    const fake = await FakeSlack.start();
    fake.answer("api.test", { __status: 200, __headers: { date: "Tue, 14 Nov 2023 22:13:20 GMT" }, __body: { ok: true } });
    const client = new SlackClient(fake.base);
    try {
      assert.equal(client.localTimeUpper("1700000000.500000"), null);
      const before = Date.now();
      await client.api("api.test", [], "xoxb-test");
      const after = Date.now();
      const mapped = client.localTimeUpper("1700000000.500000")!;
      assert.ok(mapped >= before + 500 && mapped <= after + 500);
    } finally {
      await fake.close();
    }
  });

  test("a socket that goes quiet is given up; one that answers pings stays", async () => {
    // The station's own ping and staleness (5 s, 20 s), on a clock of the test's: only pings (and pongs) are real.
    const PING_MS = 5_000;
    const STALE_MS = 20_000;
    const scope = Effect.runSync(Scope.make());
    const fake = await FakeSlack.start();
    try {
      const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
      let heard = 0;
      /// Moves the clock a ping on, until `done`: each time once the surface's look came to its end (or a ping it sent
      /// came, and when the stand-in answers pings, its pong came back), so the surface is waiting for its next.
      const ping = async (done: () => boolean) => {
        while (!done()) {
          const [pings, pongs] = [fake.pings, heard];
          await Effect.runPromise(clock.adjust(PING_MS));
          await fake.until("a ping, or the end", () => done() || (fake.pings > pings && (!fake.answersPings || heard > pongs)));
        }
      };

      fake.answersPings = false;
      const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), clock });
      const started = clock.currentTimeMillisUnsafe();
      let failed: Error | undefined;
      void Effect.runPromise(Effect.flip(surface.runSocket(fake.socketUrl(), quiet))).then((e) => (failed = e));
      await fake.until("a socket", () => surface.socket().connected);
      // Its watch goes on from the socket's opening to its first wait.
      await settle();
      await ping(() => failed !== undefined);
      const took = clock.currentTimeMillisUnsafe() - started;
      assert.match(failed!.message, /said nothing/);
      assert.ok(took >= STALE_MS && took < STALE_MS * 3, `${took} ms`);

      fake.answersPings = true;
      const staying = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), clock, onHeard: () => heard++ });
      // Nothing but pongs comes in, for well past its staleness: still up.
      let raced: Result.Result<Option.Option<void>, Error> | undefined;
      const running = Effect.timeoutOption(staying.runSocket(fake.socketUrl(), quiet), STALE_MS * 6).pipe(Effect.provideService(Clock.Clock, clock));
      void Effect.runPromise(Effect.result(running)).then((r) => (raced = r));
      await fake.until("a second socket", () => fake.sockets.length === 2 && staying.socket().connected);
      await settle();
      await ping(() => raced !== undefined);
      assert.ok(Result.isSuccess(raced!) && Option.isNone(raced.success), "still running when the time was up");
      assert.ok(fake.pings >= 6 * (STALE_MS / PING_MS) - 1, `pinged ${fake.pings} times`);
      assert.ok(staying.socket().connected);
    } finally {
      await fake.close();
      await Effect.runPromise(Scope.close(scope, Exit.void));
    }
  });

  test("a connected surface takes Socket Mode events, acknowledges those it kept, reconnects when asked, and stops", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    // The connections it asks Slack for, counted as it asks.
    const client = new SlackClient(fake.base);
    const api = client.api.bind(client);
    let opens = 0;
    client.api = ((method: string, ...rest: unknown[]) => {
      if (method === "apps.connections.open") opens++;
      return (api as any)(method, ...rest);
    }) as typeof client.api;
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client, pingMs: PING, staleMs: STALE * 5 });
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
      // Taken after e3 was (each event's handler ends before the next is read here): its ack comes after any of e3's.
      fake.event("e4", { type: "message", channel: "C1", user: "UBOT", ts: "5.4", text: "mine again" });
      fake.send({ type: "hello" });
      await fake.until("e4's ack", () => fake.acks.some((a) => a.envelope_id === "e4"));
      assert.deepEqual(
        fake.acks.map((a) => a.envelope_id).sort(),
        ["e1", "e2", "e4"],
        "what it kept, and what it ignores, acknowledged; what failed is not (Slack sends it again)",
      );
      assert.deepEqual(heard, [{ type: "message", message: { channel: "C1", threadTs: "5.1", ts: "5.1", user: "U1", text: "<@UBOT> hi", addressed: true } }]);
      // Slack rotates connections: asked to, it connects again.
      fake.send({ type: "disconnect", reason: "refresh_requested" });
      await fake.until("a second socket", () => fake.sockets.length === 2 && surface.socket().connected);
      assert.ok(changes >= 3, "the socket's ups and downs are told");
      await surface.stop();
      await fake.until("the socket closed", () => fake.sockets[1]!.readyState === fake.sockets[1]!.CLOSED);
      await settle();
      assert.deepEqual([opens, fake.sockets.length], [2, 2], "stopped: not connected again");
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

  test("posts go out as written in markdown blocks, a long one in parts; files are uploaded first and shared below the text", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    const dir = mkdtempSync(join(tmpdir(), "sl-"));
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
    try {
      const thread = { channel: "C1", threadTs: "1.1" };
      const ts = await surface.post(thread, "**hello** [x](https://x)", []);
      const first = fake.calls("chat.postMessage")[0]!;
      // In a markdown block: Slack draws the agent's Markdown (tables too); the text is what notifications show.
      assert.deepEqual(first.params, { channel: "C1", thread_ts: "1.1", text: "**hello** [x](https://x)", blocks: '[{"type":"markdown","text":"**hello** [x](https://x)"}]', unfurl_links: "false" });
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

  test("where a thread stands as its agent's turn ends: under the bot's last message, else a small message of its own; gone as it works again", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE * 5 });
    const blocks = (c: { params: Record<string, string> }) => JSON.parse(c.params.blocks!);
    try {
      await surface.start(quiet);
      await fake.until("a socket", () => fake.sockets.length === 1 && surface.socket().connected);
      const thread = { channel: "C1", threadTs: "1.1" };
      // The bot's message is the thread's newest: the line goes under it, no new message (nobody is told again).
      const answer = await surface.post(thread, "讲完了", []);
      surface.standsAt(thread, { kind: "done", words: "问题已答完 <x> & y" });
      await fake.until("the line added", () => fake.calls("chat.update").length === 1);
      const added = fake.calls("chat.update")[0]!;
      assert.deepEqual([added.params.ts, added.params.text], [answer, "讲完了"]);
      assert.deepEqual(blocks(added), [
        { type: "markdown", text: "讲完了" },
        { type: "context", elements: [{ type: "mrkdwn", text: "✓ 已完成：问题已答完 &lt;x&gt; &amp; y" }] },
      ]);
      assert.equal(fake.calls("chat.postMessage").length, 1);
      // Its message changed (edit) keeps it.
      assert.equal(await surface.edit(thread, answer, "讲完了。"), true);
      assert.deepEqual(blocks(fake.calls("chat.update")[1]!).map((b: any) => b.type), ["markdown", "context"]);
      // Someone writes and the agent works again: the message as it was.
      fake.event("e1", { type: "message", channel: "C1", user: "U1", ts: "1.5", thread_ts: "1.1", text: "我试试" });
      await fake.until("acknowledged", () => fake.acks.some((a) => a.envelope_id === "e1"));
      surface.working(thread, "1.5", "正在思考…");
      await fake.until("the line taken back", () => fake.calls("chat.update").length === 3);
      assert.deepEqual(blocks(fake.calls("chat.update")[2]!), [{ type: "markdown", text: "讲完了。" }]);
      // Done saying nothing: the person's message is the newest, so the line is a small message of its own.
      surface.working(thread, null, "");
      surface.standsAt(thread, { kind: "done", words: null });
      await fake.until("said on its own", () => fake.calls("chat.postMessage").length === 2);
      const own = fake.calls("chat.postMessage")[1]!;
      assert.deepEqual([own.params.thread_ts, own.params.text, blocks(own)], ["1.1", "✓ 已完成", [{ type: "context", elements: [{ type: "mrkdwn", text: "✓ 已完成" }] }]]);
      // The next turn's end says where it stands then: the line before goes (deleted), one line at most.
      surface.standsAt(thread, { kind: "need", words: "要 Stripe 的测试 key" });
      await fake.until("said again", () => fake.calls("chat.postMessage").length === 3);
      assert.deepEqual(fake.calls("chat.delete").map((c) => [c.params.channel, c.params.ts]), [["C1", "8000002.000100"]]);
      assert.equal(fake.calls("chat.postMessage")[2]!.params.text, "🔔 需要你处理：要 Stripe 的测试 key");
      // Ended waiting: nothing is said, and what was goes.
      surface.standsAt(thread, null);
      await fake.until("taken back", () => fake.calls("chat.delete").length === 2);
      // A question at the end says what it needs itself: no line under it.
      await surface.post(thread, "选一个", [], { type: "options", options: [{ label: "合并" }] });
      surface.standsAt(thread, { kind: "need", words: "选一个" });
      surface.standsAt(thread, { kind: "done", words: "好了" });
      await fake.until("done said", () => fake.calls("chat.update").length === 4);
      assert.deepEqual(blocks(fake.calls("chat.update")[3]!).map((b: any) => b.type), ["markdown", "actions", "context"]);
      assert.equal(fake.calls("chat.postMessage").length, 4, "nothing posted for the question");
    } finally {
      await surface.stop();
      await fake.close();
    }
  });

  test("a question's card: radio buttons with the recommended one last and chosen, details under them; long ones listed whole; a field", () => {
    const q = questionBlocks("选一个", { type: "options", options: [{ label: "合并", detail: "squash 合进 main", recommended: true }, { label: "先不", detail: "留着分支" }] }, "zh");
    assert.deepEqual(q[0], { type: "markdown", text: "选一个" });
    const [pick, send] = q[1].elements;
    assert.deepEqual(
      pick.options.map((o: any) => [o.text.text, o.value, o.description?.text]),
      [
        ["先不", "0", "留着分支"],
        ["合并", "1", "squash 合进 main"],
      ],
    );
    assert.deepEqual([pick.type, pick.initial_option.value, send.text.text, send.style, JSON.parse(send.value)], ["radio_buttons", "1", "确定", "primary", { l: ["先不", "合并"] }]);
    // A detail longer than an option takes: every option listed whole above, the options their labels only.
    const long = questionBlocks("选", { type: "options", options: [{ label: "A", detail: "说".repeat(80) }, { label: "B" }] }, "zh");
    assert.equal(long[0].text, `选\n\n**A**\n${"说".repeat(80)}\n\n**B**`);
    assert.ok(long[1].elements[0].options.every((o: any) => o.description === undefined));
    assert.equal(long[1].elements[0].initial_option, undefined, "nothing recommended: nothing chosen");
    // One to write: no field, the words marked as a question, answered by a reply in the thread.
    const t = questionBlocks("写个名字", { type: "text", placeholder: "名字" }, "zh");
    assert.deepEqual(t.map((b: any) => b.type), ["header", "markdown", "context"]);
    assert.deepEqual([t[0].text.text, t[1].text, t[2].elements[0].text], ["✍️ 需要你回答", "写个名字", "在这个线程里回复作答 · 名字"]);
    assert.equal(questionBlocks("写", { type: "text" }, "zh")[2].elements[0].text, "在这个线程里回复作答");
    assert.deepEqual(answeredBlocks("选一个", "Ada", "<合并>", "zh")[1].elements[0].text, "✓ Ada 回答：&lt;合并&gt;");
  });

  test("what a card's send button answers: the option chosen by its whole label, or the field's words; other actions none", () => {
    const pressed = (state: any, value = '{"l":["先不","合并"]}') => ({ actions: [{ action_id: "sf_answer", value }], state: { values: { b1: state } } });
    assert.deepEqual(answerOf(pressed({ sf_pick: { selected_option: { value: "1", text: { text: "合…" } } } })), { said: "合并", field: false });
    assert.deepEqual(answerOf(pressed({ sf_pick: { selected_option: { value: "1", text: { text: "合…" } } } }, "{}")), { said: "合…", field: false }, "labels too long to carry: as shown");
    assert.deepEqual(answerOf(pressed({ sf_pick: { selected_option: null } })), { said: "", field: false });
    assert.deepEqual(answerOf(pressed({ sf_text: { value: "  ada  " } }, "{}")), { said: "ada", field: true });
    assert.equal(answerOf({ actions: [{ action_id: "sf_pick" }] }), null);
  });

  test("a question posts as one message with its card; its button answers as the person, once, and the card shows the answer", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), pingMs: PING, staleMs: STALE * 5 });
    const heard: ChatEvent[] = [];
    try {
      await surface.start(async (event) => void heard.push(event));
      await fake.until("a socket", () => fake.sockets.length === 1 && surface.socket().connected);
      assert.equal(surface.cards, true);
      const asked = await surface.post({ channel: "C1", threadTs: "1.1" }, "选一个", [], { type: "options", options: [{ label: "合并", recommended: true }, { label: "先不" }] });
      const post = fake.calls("chat.postMessage")[0]!.params;
      assert.deepEqual([fake.calls("chat.postMessage").length, post.text, JSON.parse(post.blocks!).map((b: any) => b.type)], [1, "选一个", ["markdown", "actions"]]);
      const press = (id: string, state: any, actionId = "sf_answer") =>
        fake.send({
          type: "interactive",
          envelope_id: id,
          payload: {
            type: "block_actions",
            user: { id: "U1" },
            channel: { id: "C1" },
            message: { ts: asked, thread_ts: "1.1", text: "选一个" },
            actions: [{ action_id: actionId, value: '{"l":["先不","合并"]}', action_ts: "9.5" }],
            state: { values: { b1: state } },
          },
        });
      // Choosing an option says nothing; sending none chosen tells only the one who pressed.
      press("i1", { sf_pick: { selected_option: { value: "0" } } }, "sf_pick");
      press("i2", { sf_pick: { selected_option: null } });
      await fake.until("told to choose", () => fake.calls("chat.postEphemeral").length === 1);
      assert.deepEqual(fake.calls("chat.postEphemeral")[0]!.params, { channel: "C1", user: "U1", thread_ts: "1.1", text: "请先选一个选项" });
      press("i3", { sf_pick: { selected_option: { value: "1" } } });
      await fake.until("the card changed", () => fake.calls("chat.update").length === 1);
      assert.deepEqual(heard, [{ type: "message", message: { channel: "C1", threadTs: "1.1", ts: "9.5", user: "U1", text: "合并", addressed: true } }]);
      const update = fake.calls("chat.update")[0]!.params;
      assert.deepEqual([update.channel, update.ts, update.text], ["C1", asked, "选一个"]);
      assert.deepEqual(JSON.parse(update.blocks!).map((b: any) => b.type), ["markdown", "context"], "nothing to press any more");
      assert.match(update.blocks!, /Ada 回答：合并/);
      // Pressed again before the card changed: not said twice.
      press("i4", { sf_pick: { selected_option: { value: "0" } } });
      await fake.until("told it was answered", () => fake.calls("chat.postEphemeral").length === 2);
      assert.equal(fake.calls("chat.postEphemeral")[1]!.params.text, "这个问题已经回答过了");
      assert.equal(heard.length, 1);
      assert.deepEqual(fake.acks.map((a) => a.envelope_id).sort(), ["i1", "i2", "i3", "i4"], "each acknowledged at once");
    } finally {
      await surface.stop();
      await fake.close();
    }
  });

  test("history pages through the thread and gives what came before, the latest at most; people and channels are named", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    fake.answer("conversations.replies", (s) =>
      s.params.cursor === undefined
        ? { ok: true, messages: [{ ts: "1.1", user: "U1", text: "a" }, { ts: "1.2", bot_id: "B9", text: "b", attachments: [{ blocks: [{ type: "table", rows: [[{ type: "raw_text", text: "k" }], [{ type: "raw_text", text: "v" }]] }] }] }], response_metadata: { next_cursor: "c2" } }
        : { ok: true, messages: [{ ts: "1.3", user: "UBOT", text: "c" }, { ts: "1.4", user: "U2", text: "d" }] },
    );
    fake.answer("conversations.info", (s) => (s.params.channel === "D1" ? { ok: true, channel: { id: "D1", is_im: true } } : { ok: true, channel: { id: "C1", name: "general" } }));
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
    try {
      await surface.start(quiet);
      const earlier = await surface.history({ channel: "C1", threadTs: "1.1" }, "1.4", 2);
      assert.deepEqual(earlier, [
        { ts: "1.2", user: "B9", text: "b\n\n| k |\n| --- |\n| v |", fromBot: true },
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

  test("a person found by their email (users.lookupByEmail), kept once found; none for one not there or deactivated", async () => {
    const fake = await FakeSlack.start();
    bot(fake);
    fake.answer("users.lookupByEmail", (s) =>
      s.params.email === "ada@example.test" ? { ok: true, user: { id: "U1" } }
        : s.params.email === "old@example.test" ? { ok: true, user: { id: "U9", deleted: true } }
        : { ok: false, error: "users_not_found" },
    );
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
    try {
      await surface.start(quiet);
      assert.deepEqual([await surface.userOf(" Ada@Example.test"), await surface.userOf("ada@example.test")], ["U1", "U1"]);
      assert.deepEqual(fake.calls("users.lookupByEmail").map((c) => c.params.email), ["ada@example.test"], "asked once, as written there");
      assert.deepEqual([await surface.userOf("old@example.test"), await surface.userOf("bo@example.test"), await surface.userOf("")], [null, null, null]);
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
      assert.deepEqual(wrong, ["Bot Token 应以 xoxb- 开头", "App-Level Token 应以 xapp- 开头"]);
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
      const time = testClock();
      const book = new NameBook(path, { learnAfterMs: 20, saveAfterMs: 60, clock: time.clock });
      let told = 0;
      let asked = 0;
      book.onLearn(() => told++);
      const ada = async () => (asked++, { name: "Ada", email: "ada@x" });
      assert.equal(book.person("u:T:U1", ada), null);
      assert.equal(book.person("u:T:U1", ada), null, "asked again while fetching: not twice");
      assert.equal(book.channel("c:T:D1", async () => null), null);
      assert.equal(book.person("u:T:U9", async () => null), null);
      await settle();
      assert.equal(asked, 1);
      assert.equal(book.person("u:T:U1", ada)?.name, "Ada");
      assert.equal(told, 0, "told once the burst is over");
      await time.adjust(20);
      await settle();
      assert.equal(told, 1, "once per burst");
      // A failed lookup is not tried again for a while.
      let again = 0;
      book.person("u:T:U9", async () => (again++, null));
      await settle();
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

  test("a person comes with their Slack picture; one kept before pictures were is looked up again, still shown meanwhile", async () => {
    const answer = (image?: string) => ({ ok: true, user: { name: "ada", profile: { display_name: "Ada", email: "Ada@x", ...(image ? { image_72: image } : {}) } } });
    assert.deepEqual(personOf(answer("https://avatars.slack-edge.com/ada_72.png")), { name: "Ada", email: "ada@x", picture: "https://avatars.slack-edge.com/ada_72.png" });
    assert.deepEqual(personOf(answer()), { name: "Ada", email: "ada@x", picture: "" });
    const dir = mkdtempSync(join(tmpdir(), "nb-"));
    const path = join(dir, "slack-names.json");
    try {
      writeFileSync(path, JSON.stringify({ "u:T:U1": { person: { name: "Ada", email: "ada@x" }, at: 1 } }));
      const book = new NameBook(path, { learnAfterMs: 20, saveAfterMs: 60, clock: testClock().clock });
      let asked = 0;
      const ada = async () => (asked++, personOf(answer("https://p/ada")));
      const stale = (known: { picture?: string }) => known.picture === undefined;
      assert.deepEqual(book.person("u:T:U1", ada, stale), { name: "Ada", email: "ada@x" });
      await settle();
      assert.equal(asked, 1);
      assert.equal(book.person("u:T:U1", ada, stale)?.picture, "https://p/ada");
      await settle();
      assert.equal(asked, 1, "known with its picture: not asked again");
      await book.close();
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
        if (fail !== null && (method === "agents.sessions.setStatus" || method === "assistant.threads.setStatus")) throw new Error(`slack ${method}: ${fail}`);
      },
      calls,
    ];
  }
  /// Runs a status line's waits as fibers of a scope the test closes: a wait still due (the next change, seconds on) ends
  /// with it, and does not hold the test's process.
  /// On a TestClock, moved on by `adjust`.
  function fibers(): { run: (effect: Effect.Effect<void>) => Promise<void>; adjust: (ms: number) => Promise<void>; close: () => Promise<void> } {
    const scope = Effect.runSync(Scope.make());
    const time = testClock();
    const runtime = Effect.runSync(Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), scope));
    const run = (effect: Effect.Effect<void>) => runtime(effect.pipe(Effect.provideService(Clock.Clock, time.clock)));
    return { run, adjust: time.adjust, close: () => Effect.runPromise(Scope.close(scope, Exit.void)) };
  }

  test("a thread's status line says what the agent does and goes when it is done", async (t) => {
    const { run, adjust, close } = fibers();
    t.after(close);
    const [call, calls] = recording(null);
    const line = new ThreadStatus(call, run, "C1", "1.1");
    line.say("正在思考…", "1.2");
    await settle();
    line.say("", null);
    await settle();
    assert.deepEqual(
      calls.map(([m, p]) => [m, p.status]),
      [
        ["agents.sessions.setStatus", "processing"],
        ["agents.sessions.setStatus", "active"],
      ],
    );
    assert.deepEqual([calls[0]![1].channel_id, calls[0]![1].thread_ts], ["C1", "1.1"]);
    // Changed at most every couple of seconds: what is said meanwhile waits, and only the latest goes.
    const [paced, sent] = recording(null);
    const busy = new ThreadStatus(paced, run, "C1", "1.1");
    busy.say("a", null);
    await settle();
    await adjust(20);
    busy.say("b", null);
    busy.say("c", null);
    await adjust(1_000);
    await settle();
    assert.deepEqual(sent.map(([, p]) => p.status), ["processing"]);
    await adjust(980);
    await settle();
    assert.deepEqual(sent.map(([, p]) => p.status), ["processing", "processing"]);
  });

  test("an app without the agent feature keeps its old status and tries agent sessions again next turn", async (t) => {
    const { run, adjust, close } = fibers();
    t.after(close);
    const calls: Calls = [];
    let enabled = false;
    const call = async (method: string, params: [string, string][]) => {
      calls.push([method, Object.fromEntries(params)]);
      if (!enabled && method === "agents.sessions.setStatus") throw new Error("slack agents.sessions.setStatus: not_authorized");
    };
    const line = new ThreadStatus(call, run, "C1", "1.1");
    line.say("thinking", "1.2");
    await settle();
    line.say("");
    await settle();
    assert.deepEqual(calls.map(([m, p]) => [m, p.status]), [
      ["agents.sessions.setStatus", "processing"],
      ["assistant.threads.setStatus", "thinking"],
      ["assistant.threads.setStatus", ""],
    ]);
    enabled = true;
    line.say("working again");
    await adjust(2_000);
    await settle();
    assert.deepEqual(calls.at(-1), ["agents.sessions.setStatus", { channel_id: "C1", thread_ts: "1.1", status: "processing" }]);
  });

  test("where Slack will not show a status, an eyes reaction stands in", async (t) => {
    const { run, close } = fibers();
    t.after(close);
    const [call, calls] = recording("missing_scope");
    const line = new ThreadStatus(call, run, "C1", "1.1");
    line.say("正在运行命令…", "1.2");
    await settle();
    line.say("", null);
    await settle();
    assert.deepEqual(
      calls.map(([m, p]) => [m, p.timestamp ?? null, p.name ?? null]),
      [
        ["agents.sessions.setStatus", null, null],
        ["assistant.threads.setStatus", null, null],
        ["reactions.add", "1.2", "eyes"],
        ["reactions.remove", "1.2", "eyes"],
      ],
    );
  });

  test("tool calls in words, by either runtime's names", () => {
    const words = ["Read", "Bash", "exec_command", "apply_patch", "WebSearch", "mcp__ember__chat_post", "mcp__stillfail__slack_api", "something"].map(toolStatus);
    assert.deepEqual(words, ["正在查看文件…", "正在运行命令…", "正在运行命令…", "正在修改文件…", "正在搜索网页…", "正在读取对话…", "正在读取 Slack…", "正在处理…"]);
  });

  test("a surface shows its status without waiting for app setup", async () => {
    const fake = await FakeSlack.start();
    let releaseSetup!: () => void;
    const setupHeld = new Promise<void>((resolve) => (releaseSetup = resolve));
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), onWorking: () => setupHeld });
    try {
      surface.working({ channel: "C1", threadTs: "1.1" }, "1.2", "正在思考…");
      await fake.until("a status", () => fake.calls("agents.sessions.setStatus").length === 1);
      assert.deepEqual(fake.calls("agents.sessions.setStatus")[0]!.params, { channel_id: "C1", thread_ts: "1.1", status: "processing" });
      assert.equal(fake.calls("agents.sessions.setStatus")[0]!.auth, "xoxb-1");
    } finally {
      releaseSetup();
      await surface.stop();
      await fake.close();
    }
  });
});
