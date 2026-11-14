// The Feishu connect: its frames, what its events say, its cards, its threads, its app registration,
// and its surface against Feishu's stand-in (test/feishu-fake.ts), through a hub with scripted runtimes.
import assert from "node:assert/strict";
import { gunzipSync } from "node:zlib";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { questionCard, textPosts, took } from "../src/feishu/cards.ts";
import { CONTROL, DATA, Parts, decode, encode, header } from "../src/feishu/frame.ts";
import { messageOf, resourceOf } from "../src/feishu/parse.ts";
import { ADDONS, Registrations, encodeAddons } from "../src/feishu/register.ts";
import { NameBook } from "../src/connects/names.ts";
import { MEMBERS_MS } from "../src/connects/surface.ts";
import { FeishuSurface } from "../src/feishu/surface.ts";
import { FeishuThreads } from "../src/feishu/threads.ts";
import { FeishuClient } from "../src/feishu/web.ts";
import type { ChatEvent } from "../src/sessions/chat.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { FakeFeishu } from "./feishu-fake.ts";
import { Rig, settle } from "./hub-fakes.ts";

type Json = any;

const testClock = () => {
  const scope = Effect.runSync(Scope.make());
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  return { clock, adjust: (ms: number) => Effect.runPromise(clock.adjust(`${ms} millis`)), close: () => Effect.runPromise(Scope.close(scope, Exit.void)) };
};

test("frames: what is encoded decodes the same, negative ints and headers too; parts are put together once all are in", () => {
  const f = { seqId: 12345678901234n, logId: 7n, service: -3, method: DATA, headers: [["type", "event"], ["message_id", "m1"]] as [string, string][], payload: new Uint8Array([1, 2, 3]), logIdNew: "x" };
  const back = decode(encode(f));
  assert.deepEqual(back, { ...f, payload: new Uint8Array([1, 2, 3]) });
  assert.equal(header(back, "type"), "event");
  const parts = new Parts();
  const part = (seq: number, bytes: number[]) => ({ seqId: 0n, logId: 0n, service: 1, method: DATA, headers: [["message_id", "big"], ["sum", "2"], ["seq", String(seq)]] as [string, string][], payload: new Uint8Array(bytes) });
  assert.equal(parts.add(part(1, [3, 4]), 0), null);
  assert.deepEqual(parts.add(part(0, [1, 2]), 0), new Uint8Array([1, 2, 3, 4]));
  assert.equal(decode(encode({ seqId: 0n, logId: 0n, service: 0, method: CONTROL, headers: [] })).method, CONTROL);
});

test("messages: mentions as names and whether the bot was among them, rich text as Markdown with its images, files, direct messages, a new session asked for", () => {
  const ev = (message: Json, sender: Json = { sender_type: "user", sender_id: { open_id: "ou_ada" } }) => ({ sender, message: { message_id: "om_1", chat_id: "oc_g", chat_type: "group", ...message } });
  const mention = [{ key: "@_user_1", id: { open_id: "ou_bot" }, name: "Bot" }];
  const m = messageOf(ev({ message_type: "text", content: JSON.stringify({ text: "@_user_1 看下这个" }), mentions: mention }), "ou_bot")!;
  assert.deepEqual([m.text, m.addressed, m.fresh, m.topic], ["@Bot 看下这个", true, false, null]);
  assert.equal(messageOf(ev({ message_type: "text", content: JSON.stringify({ text: "随便聊" }) }), "ou_bot")!.addressed, false);
  assert.equal(messageOf(ev({ message_type: "text", content: "{}" }, { sender_type: "app", sender_id: { open_id: "ou_bot" } }), "ou_bot"), null, "an app's own");
  const post = messageOf(
    ev({ message_type: "post", content: JSON.stringify({ title: "标题", content: [[{ tag: "text", text: "粗", style: ["bold"] }, { tag: "a", text: "链接", href: "https://x.test" }], [{ tag: "img", image_key: "img_k" }], [{ tag: "code_block", language: "TS", text: "let a = 1\n" }]] }) }),
    "ou_bot",
  )!;
  assert.equal(post.text, "**标题**\n**粗**[链接](https://x.test)\n\n\n```ts\nlet a = 1\n```");
  assert.deepEqual(post.files.map((f) => [f.id, resourceOf(f.url!)]), [["img_k", { type: "image", message: "om_1", key: "img_k" }]]);
  const file = messageOf(ev({ message_type: "file", content: JSON.stringify({ file_key: "fk", file_name: "a.pdf" }) }), "ou_bot")!;
  assert.deepEqual(file.files.map((f) => [f.name, f.url]), [["a.pdf", "feishu:file:om_1:fk"]]);
  const dm = messageOf(ev({ message_type: "text", chat_type: "p2p", content: JSON.stringify({ text: "新会话" }) }), "ou_bot")!;
  assert.deepEqual([dm.addressed, dm.fresh, dm.p2p], [true, true, true]);
  assert.equal(messageOf(ev({ message_type: "sticker", content: "{}" }), "ou_bot")!.text, "[sticker]");
});

test("cards: long text in several rich-text messages, mentions as md writes them; a question's buttons with the recommended one last and filled, a text card's field", () => {
  const long = textPosts(`${"字".repeat(5000)}\n\n${"字".repeat(5000)}`);
  assert.equal(long.length, 2);
  assert.deepEqual(JSON.parse(textPosts("<at id=ou_ada></at> 好了\n\n| a |\n|---|\n| 1 |")[0]!), {
    zh_cn: { content: [[{ tag: "md", text: '<at user_id="ou_ada"></at> 好了\n\n| a |\n|---|\n| 1 |' }]] },
  });
  const q = questionCard("选一个", { type: "options", options: [{ label: "合并", recommended: true }, { label: "先不", detail: "留着分支" }] }, "om_t", "zh");
  const buttons = q.body.elements.filter((e: Json) => e.tag === "button");
  assert.deepEqual(buttons.map((b: Json) => [b.text.content, b.type, b.behaviors[0].value]), [
    ["先不", "default", { sf: "answer", t: "om_t", l: "先不" }],
    ["合并", "primary_filled", { sf: "answer", t: "om_t", l: "合并" }],
  ]);
  const t = questionCard("写个名字", { type: "text", placeholder: "名字" }, "om_t", "zh");
  // One to write: no form, an orange header marking it as a question, answered by a reply.
  assert.deepEqual([t.header.title.content, t.header.template], ["✍️ 需要你回答", "orange"]);
  assert.deepEqual(t.body.elements.map((e: Json) => e.content), ["写个名字", "<font color='grey'>直接回复作答 · 名字</font>"]);
  assert.equal(took(125_000, "zh"), "2 分 5 秒");
});

test("registration: the link carries what the app is to get; asked until its id and secret come; denied ends it", async () => {
  const t = testClock();
  const polls: Json[] = [];
  let answer: Json = { error: "authorization_pending" };
  const reg = new Registrations({
    clock: t.clock,
    post: async (domain, form) => {
      if (form.action === "init") return { supported_auth_methods: ["client_secret"] };
      if (form.action === "begin") return { device_code: "dc", verification_uri_complete: "https://accounts.feishu.cn/x?user_code=AB", interval: 5, expires_in: 600 };
      polls.push([domain, form]);
      return answer;
    },
  });
  try {
    const r = await reg.begin("a@x.test", "feishu", "Codex 机器人");
    const url = new URL(r.url);
    assert.equal(url.searchParams.get("user_code"), "AB");
    assert.equal(url.searchParams.get("name"), "Codex 机器人");
    assert.deepEqual(JSON.parse(gunzipSync(Buffer.from(url.searchParams.get("addons")!, "base64url")).toString()), ADDONS);
    assert.equal(encodeAddons({ a: 1 }).includes("="), false);
    await t.adjust(5000);
    await settle();
    assert.equal(reg.get(r.id)!.state, "waiting");
    answer = { client_id: "cli_new", client_secret: "sec", user_info: { open_id: "ou_me" } };
    await t.adjust(5000);
    await settle();
    assert.equal(reg.get(r.id)!.state, "done");
    assert.equal(await reg.complete(r.id, "b@x.test", "", async () => "wrong"), null, "only its maker's");
    assert.equal(await reg.complete(r.id, "a@x.test", "", async (made) => {
      assert.deepEqual(made.app, { appId: "cli_new", appSecret: "sec", openId: "ou_me" });
      return "saved";
    }), "saved");
    const again = await reg.begin("a@x.test", "feishu", null);
    answer = { error: "access_denied" };
    await t.adjust(5000);
    await settle();
    assert.equal(reg.get(again.id)!.state, "denied");
    assert.equal(polls.length, 3);
  } finally {
    await reg.close();
    await t.close();
  }
});

test("registration: a temporary save failure is retried with the same app while the station stays up", async () => {
  const t = testClock();
  let attempts = 0;
  const reg = new Registrations({ clock: t.clock, post: async (_domain, form) =>
    form.action === "init" ? { supported_auth_methods: ["client_secret"] }
      : form.action === "begin" ? { device_code: "dc", verification_uri_complete: "https://accounts.feishu.cn/x", interval: 5 }
      : { client_id: "cli_new", client_secret: "sec" },
  });
  reg.start(async (r) => {
    assert.equal(r.app?.appId, "cli_new");
    if (++attempts === 1) throw new Error("temporary failure");
    return "my-connect";
  });
  try {
    const viewer = { sub: "s", email: "a@x.test", name: "A", role: "owner", workspace: "w", device: "d" };
    const r = await reg.begin(viewer.email, "feishu", null, { viewer, lang: "zh", input: { bind: { runtime: "claude" } } }, viewer.workspace);
    await t.adjust(5000);
    await settle();
    assert.equal(attempts, 1);
    assert.equal(reg.get(r.id)?.app?.appSecret, "sec");
    await t.adjust(5000);
    await settle();
    assert.equal(attempts, 2);
    assert.deepEqual([reg.get(r.id)?.connectId, reg.get(r.id)?.app], ["my-connect", null]);
  } finally {
    await reg.close();
    await t.close();
  }
});

/// A surface on Feishu's stand-in, with its threads in a temporary directory.
async function surfaceRig(o: { topics?: boolean; threadMode?: boolean; names?: boolean; before?: (threads: FeishuThreads, fake: FakeFeishu) => void } = {}) {
  const fake = await FakeFeishu.start();
  if (o.topics) fake.answer("GET /open-apis/im/v1/chats/oc_t", { code: 0, data: { name: "话题群", chat_mode: "group", group_message_type: "thread" } });
  const dir = mkdtempSync(join(tmpdir(), "fs-"));
  const t = testClock();
  const threads = new FeishuThreads(join(dir, "threads.json"));
  o.before?.(threads, fake);
  const book = o.names ? new NameBook(join(dir, "names.json"), { clock: t.clock }) : null;
  const surface = new FeishuSurface({ connect: "fs", appId: "cli_test", appSecret: "s", domain: "feishu", threads, threadMode: o.threadMode, book, client: new FeishuClient("cli_test", "s", "feishu", fake.base), clock: t.clock });
  const events: ChatEvent[] = [];
  await surface.start(async (e) => void events.push(e));
  await fake.until("connected", () => surface.socket().connected);
  return {
    fake, surface, events, threads, t,
    close: async () => {
      await surface.stop();
      await book?.close();
      await fake.close();
      await t.close();
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

test("surface: the first @ begins the chat's conversation, the rest of the chat follows it without @, a new session begins another; events are acknowledged once kept", async () => {
  const r = await surfaceRig();
  try {
    assert.equal(r.surface.botUserId(), "ou_bot");
    const first = r.fake.message({ id: "om_a", text: "帮我看看", at: true });
    await r.fake.until("acked", () => r.fake.ack(first) !== undefined);
    assert.deepEqual(r.fake.ack(first), { code: 200 });
    r.fake.message({ id: "om_b", text: "补充一句" });
    r.fake.message({ id: "om_c", text: "新会话", at: true });
    r.fake.message({ id: "om_d", text: "接着说" });
    await r.fake.until("all four", () => r.events.length === 4);
    const said = r.events.map((e) => (e.type === "message" ? [e.message.threadTs, e.message.ts, e.message.addressed] : null));
    assert.deepEqual(said, [
      ["om_a", "om_a", true],
      ["om_a", "om_b", false],
      ["om_c", "om_c", true],
      ["om_c", "om_d", false],
    ]);
    assert.equal(r.threads.current("fs", "oc_g"), "om_c");
    // Chatter before anyone @s the bot begins nothing.
    r.fake.message({ id: "om_x", chat: "oc_other", text: "闲聊" });
    await r.fake.until("heard", () => r.events.length === 5);
    assert.equal(r.threads.current("fs", "oc_other"), null);
  } finally {
    await r.close();
  }
});

test("surface: what was said in a conversation's chat while the station was away is read once it connects", async () => {
  const r = await surfaceRig({
    before: (threads, fake) => {
      threads.begin("fs", "oc_g", "om_a");
      threads.heard("fs", "oc_g", 1_000_000);
      fake.answer("GET /open-apis/im/v1/messages", (s: Json) => ({
        code: 0,
        data: {
          has_more: false,
          items:
            s.query.container_id === "oc_g" && s.query.start_time === "1000"
              ? [
                  { message_id: "om_old", chat_id: "oc_g", create_time: "1000000", msg_type: "text", body: { content: JSON.stringify({ text: "已经听过" }) }, sender: { id: "ou_ada", sender_type: "user" } },
                  { message_id: "om_away", chat_id: "oc_g", create_time: "1000500", msg_type: "text", body: { content: JSON.stringify({ text: "@_user_1 不在时说的" }) }, sender: { id: "ou_ada", sender_type: "user" }, mentions: [{ key: "@_user_1", id: "ou_bot", name: "Bot" }] },
                  { message_id: "om_mine", chat_id: "oc_g", create_time: "1000600", msg_type: "interactive", body: { content: "{}" }, sender: { id: "cli_test", sender_type: "app" } },
                ]
              : [],
        },
      }));
    },
  });
  try {
    await r.fake.until("caught up", () => r.events.length === 1);
    const e = r.events[0]!;
    assert.deepEqual(e.type === "message" ? [e.message.threadTs, e.message.ts, e.message.text, e.message.addressed] : null, ["om_a", "om_away", "@Bot 不在时说的", true]);
    assert.deepEqual(r.threads.conversations("fs"), [["oc_g", 1_000_500]]);
  } finally {
    await r.close();
  }
});

test("surface: a topic group's topics are conversations of their own, answered in the topic", async () => {
  const r = await surfaceRig({ topics: true });
  try {
    r.fake.message({ id: "om_q", chat: "oc_t", text: "问题", at: true, thread: "omt_1", root: "om_root" });
    await r.fake.until("heard", () => r.events.length === 1);
    assert.equal(r.events[0]!.type === "message" && r.events[0]!.message.threadTs, "omt_1");
    await r.surface.post({ channel: "oc_t", threadTs: "omt_1" }, "答案", []);
    const reply = r.fake.calls("POST", "/open-apis/im/v1/messages/om_root/reply");
    assert.equal(reply.length, 1);
    assert.equal(reply[0]!.body.reply_in_thread, true);
    assert.deepEqual([reply[0]!.body.msg_type, JSON.parse(reply[0]!.body.content).zh_cn.content[0][0].text], ["post", "答案"]);
  } finally {
    await r.close();
  }
});

test("surface: thread mode: an @ begins a thread answered in it, a thread goes by its first message, and what calls nobody is no one's", async () => {
  const r = await surfaceRig({ threadMode: true });
  try {
    r.fake.message({ id: "om_a", text: "看看", at: true });
    r.fake.message({ id: "om_b", text: "闲聊" });
    r.fake.message({ id: "om_c", text: "接着说", thread: "omt_1", root: "om_a" });
    await r.fake.until("heard", () => r.events.length === 3);
    assert.deepEqual(r.events.map((e) => (e.type === "message" ? e.message.threadTs : null)), ["om_a", "om_b", "om_a"]);
    assert.equal(r.threads.current("fs", "oc_g"), null, "the group has no conversation of its own");
    await r.surface.post({ channel: "oc_g", threadTs: "om_a" }, "答案", []);
    const reply = r.fake.calls("POST", "/open-apis/im/v1/messages/om_a/reply");
    assert.equal(reply.length, 1);
    assert.equal(reply[0]!.body.reply_in_thread, true);
    assert.equal(r.fake.calls("POST", "/open-apis/im/v1/messages").length, 0);
    r.fake.message({ id: "om_d", text: "私聊", p2p: true });
    await r.fake.until("direct", () => r.events.length === 4);
    await r.surface.post({ channel: "oc_g", threadTs: "om_a" }, "仍在 thread", []);
    assert.equal(r.fake.calls("POST", "/open-apis/im/v1/messages/om_a/reply").length, 2);
    r.fake.answer("GET /open-apis/im/v1/messages/om_a", { code: 0, data: { items: [{ message_id: "om_a", thread_id: "omt_1" }] } });
    r.fake.answer("GET /open-apis/im/v1/messages", { code: 0, data: { items: [], has_more: false } });
    assert.deepEqual(await r.surface.history({ channel: "oc_g", threadTs: "om_a" }, "om_c", 10), []);
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages").at(-1)!.query.container_id, "omt_1");
  } finally {
    await r.close();
  }
});

test("surface: outside thread mode a group's thread is the group's conversation, answered in the group", async () => {
  const r = await surfaceRig();
  try {
    r.fake.message({ id: "om_a", text: "看看", at: true });
    r.fake.message({ id: "om_c", text: "接着说", thread: "omt_1", root: "om_a" });
    await r.fake.until("heard", () => r.events.length === 2);
    assert.deepEqual(r.events.map((e) => (e.type === "message" ? e.message.threadTs : null)), ["om_a", "om_a"]);
    await r.surface.post({ channel: "oc_g", threadTs: "om_a" }, "答案", []);
    assert.equal(r.fake.calls("POST", "/open-apis/im/v1/messages").length, 1);
  } finally {
    await r.close();
  }
});

test("surface: a turn for a message that called nobody shows no card until the agent does something, and one that says nothing takes its card back", async () => {
  const r = await surfaceRig();
  try {
    const cards = () => r.fake.calls("POST", "/open-apis/im/v1/messages").length;
    const here = { channel: "oc_g", threadTs: "om_a" };
    r.fake.message({ id: "om_a", text: "看看", at: true });
    r.fake.message({ id: "om_b", text: "闲聊" });
    await r.fake.until("heard", () => r.events.length === 2);
    // Only thought and read the chat, said nothing: no card at all.
    r.surface.working(here, "om_b", "正在思考…", null);
    await settle();
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "正在读取对话…", null);
    await settle();
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "", null);
    await settle();
    assert.equal(cards(), 0);
    // It went to work, then said nothing: the card went up, and comes down.
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "正在运行命令…", null);
    await r.fake.until("card made", () => cards() === 1);
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "", null);
    await r.fake.until("recalled", () => r.fake.calls("DELETE", /^\/open-apis\/im\/v1\/messages\//).length === 1);
    assert.equal(r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length, 0);
    // It said something: no card for thinking, and none left to change.
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "正在思考…", null);
    await settle();
    await r.surface.post(here, "补一句", []);
    await r.t.adjust(1000);
    r.surface.working(here, "om_b", "", null);
    await settle();
    assert.equal(r.fake.calls("DELETE", /^\/open-apis\/im\/v1\/messages\//).length, 1);
    assert.equal(cards(), 2, "the card before, and what it said");
    // Called by an @: the card at once; kept saying the turn is over when Feishu will not recall it.
    await r.t.adjust(1000);
    r.fake.answer("POST /open-apis/im/v1/messages", { code: 0, data: { message_id: "om_at" } });
    r.surface.working(here, "om_a", "正在思考…", null);
    await r.fake.until("card at once", () => cards() === 3);
    r.fake.answer("DELETE /open-apis/im/v1/messages/om_at", { code: 230_000, msg: "too old" });
    await r.t.adjust(1000);
    r.surface.working(here, "om_a", "", null);
    await r.fake.until("kept as done", () => r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length === 1);
  } finally {
    await r.close();
  }
});

test("surface: the people in a group, by their name in it, kept a minute", async () => {
  const r = await surfaceRig();
  try {
    r.fake.answer("GET /open-apis/im/v1/chats/oc_g/members", (seen: Json) =>
      seen.query?.page_token === "p2"
        ? { code: 0, data: { items: [{ member_id: "ou_2", name: "李四" }], has_more: false } }
        : { code: 0, data: { items: [{ member_id: "ou_1", name: "张三" }, { member_id: "ou_x", name: "" }], has_more: true, page_token: "p2" } },
    );
    const people = [{ id: "ou_1", name: "张三" }, { id: "ou_2", name: "李四" }];
    assert.deepEqual(await r.surface.peopleIn("oc_g"), people);
    assert.deepEqual(await r.surface.peopleIn("oc_g"), people);
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/chats/oc_g/members").length, 2, "asked again soon: kept");
    await r.t.adjust(MEMBERS_MS);
    await r.surface.peopleIn("oc_g");
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/chats/oc_g/members").length, 4);
  } finally {
    await r.close();
  }
});

test("surface: relaying lists the groups the bot is in, topic group or not; begins a topic in a topic group, the conversation of a group", async () => {
  const r = await surfaceRig({ topics: true });
  try {
    r.fake.answer("GET /open-apis/im/v1/chats", { code: 0, data: { items: [{ chat_id: "oc_t", name: "话题群" }, { chat_id: "oc_g", name: "项目群" }], has_more: false } });
    assert.deepEqual(await r.surface.places(), [{ id: "oc_t", name: "话题群", kind: "topics" }, { id: "oc_g", name: "项目群", kind: "group" }]);
    let n = 0;
    r.fake.answer("POST /open-apis/im/v1/messages", (seen: Json) => ({ code: 0, data: { message_id: `om_r${++n}`, ...(seen.body.receive_id === "oc_t" && n === 1 ? { thread_id: "omt_9" } : {}) } }));
    // A topic group: the message is a topic, answered in it from now on.
    assert.deepEqual(await r.surface.begin("oc_t", "接力到这里"), { thread: { channel: "oc_t", threadTs: "omt_9" }, ts: "om_r1" });
    assert.equal(r.threads.topicRoot("fs", "omt_9"), "om_r1");
    await r.surface.post({ channel: "oc_t", threadTs: "omt_9" }, "摘要", []);
    assert.equal(r.fake.calls("POST", "/open-apis/im/v1/messages/om_r1/reply").length, 1);
    // Its first message changed in place, when what it says fits in one message.
    r.fake.answer("PUT /open-apis/im/v1/messages/om_r1", { code: 0, data: {} });
    assert.equal(await r.surface.edit({ channel: "oc_t", threadTs: "omt_9" }, "om_r1", "接力到这里\n\n摘要"), true);
    const put = r.fake.calls("PUT", "/open-apis/im/v1/messages/om_r1");
    assert.equal(put[0]!.body.msg_type, "post");
    assert.equal(JSON.parse(put[0]!.body.content).zh_cn.content[0][0].text, "接力到这里\n\n摘要");
    assert.equal(await r.surface.edit({ channel: "oc_t", threadTs: "omt_9" }, "om_r1", `${"甲".repeat(6000)}\n\n乙`), false);
    assert.equal(r.fake.calls("PUT", "/open-apis/im/v1/messages/om_r1").length, 1);
    // A topic Feishu did not name in its answer is read back from the message.
    r.fake.answer("GET /open-apis/im/v1/messages/om_r2", { code: 0, data: { items: [{ message_id: "om_r2", thread_id: "omt_10" }] } });
    assert.deepEqual((await r.surface.begin("oc_t", "再接力")).thread, { channel: "oc_t", threadTs: "omt_10" });
    // A group: the chat's conversation from now on, followed without @.
    assert.deepEqual(await r.surface.begin("oc_g", "接力到这里"), { thread: { channel: "oc_g", threadTs: "om_r3" }, ts: "om_r3" });
    assert.equal(r.threads.current("fs", "oc_g"), "om_r3");
    r.fake.message({ id: "om_x", chat: "oc_g", text: "收到" });
    await r.fake.until("heard", () => r.events.length === 1);
    assert.equal(r.events[0]!.type === "message" && r.events[0]!.message.threadTs, "om_r3");
    assert.equal(r.surface.permalink({ channel: "oc_g", threadTs: "om_r3" }), "https://applink.feishu.cn/client/chat/open?openChatId=oc_g");
  } finally {
    await r.close();
  }
});

test("surface: posts as rich text in the chat, files after them; a question's button answers as the person and the card shows the answer", async () => {
  const r = await surfaceRig();
  const dir = mkdtempSync(join(tmpdir(), "fsf-"));
  try {
    writeFileSync(join(dir, "shot.png"), "png");
    writeFileSync(join(dir, "report.pdf"), "pdf");
    const ts = await r.surface.post({ channel: "oc_g", threadTs: "om_a" }, "**好了**", [
      { name: "shot.png", path: join(dir, "shot.png"), size: 3 },
      { name: "report.pdf", path: join(dir, "report.pdf"), size: 3 },
    ]);
    const sent = r.fake.calls("POST", "/open-apis/im/v1/messages");
    assert.deepEqual(sent.map((s) => [s.query.receive_id_type, s.body.receive_id, s.body.msg_type]), [
      ["chat_id", "oc_g", "post"],
      ["chat_id", "oc_g", "image"],
      ["chat_id", "oc_g", "file"],
    ]);
    assert.match(ts, /^om_bot\d+$/, "the first message's id");
    assert.equal(r.fake.calls("POST", "/open-apis/im/v1/files")[0]!.body.file_type, "pdf");
    const asked = await r.surface.post({ channel: "oc_g", threadTs: "om_a" }, "合并吗", [], { type: "options", options: [{ label: "合并", recommended: true }] });
    const frame = r.fake.event("card.action.trigger", { operator: { open_id: "ou_ada" }, action: { tag: "button", value: { sf: "answer", t: "om_a", l: "合并" } }, context: { open_message_id: asked, open_chat_id: "oc_g" } }, "ev-card");
    await r.fake.until("acked", () => r.fake.ack(frame) !== undefined);
    const e = r.events.at(-1)!;
    assert.deepEqual(e.type === "message" ? [e.message.threadTs, e.message.ts, e.message.text, e.message.user, e.message.addressed] : null, ["om_a", "card-ev-card", "合并", "ou_ada", true]);
    const answer = JSON.parse(Buffer.from(r.fake.ack(frame).data, "base64").toString());
    assert.equal(answer.toast.type, "success");
    assert.equal(answer.card.data.body.elements.some((el: Json) => el.tag === "button"), false, "nothing to press any more");
  } finally {
    rmSync(dir, { recursive: true, force: true });
    await r.close();
  }
});

test("surface: a question that stops waiting otherwise says why, nothing left to press; one its own button answered is left as it shows", async () => {
  const r = await surfaceRig();
  try {
    const here = { channel: "oc_g", threadTs: "om_a" };
    const options = { type: "options", options: [{ label: "合并", recommended: true }] };
    const asked = await r.surface.post(here, "合并吗", [], options);
    await r.surface.cardEnded(here, asked, "合并吗", options, { why: "message", by: "ou_ada", byTs: "om_m" });
    const patched = r.fake.calls("PATCH", `/open-apis/im/v1/messages/${asked}`);
    assert.equal(patched.length, 1);
    const card = JSON.parse(patched[0]!.body.content);
    assert.equal(card.body.elements.some((el: Json) => el.tag === "button"), false, "nothing to press any more");
    assert.match(JSON.stringify(card), /这张卡已关闭/);
    await r.surface.cardEnded(here, asked, "合并吗", options, { why: "withdrawn" });
    assert.equal(r.fake.calls("PATCH", `/open-apis/im/v1/messages/${asked}`).length, 1, "closed once");
    // Its button's answer is a message of its own (card-…): the card shows that answer already.
    const pressed = await r.surface.post(here, "再合并吗", [], options);
    await r.surface.cardEnded(here, pressed, "再合并吗", options, { why: "message", by: "ou_ada", byTs: "card-ev-1" });
    assert.equal(r.fake.calls("PATCH", `/open-apis/im/v1/messages/${pressed}`).length, 0);
  } finally {
    await r.close();
  }
});

test("surface: the status card follows the agent's steps at most once a second and ends saying how long it took, with the history's link", async () => {
  const r = await surfaceRig();
  try {
    const here = { channel: "oc_g", threadTs: "om_a" };
    r.fake.message({ id: "om_a", text: "看看", at: true });
    await r.fake.until("heard", () => r.events.length === 1);
    r.surface.working(here, "om_a", "正在思考…", "https://still.test/o/w/s/k");
    await r.fake.until("card made", () => r.fake.calls("POST", "/open-apis/im/v1/messages").length === 1);
    assert.equal(JSON.parse(r.fake.calls("POST", "/open-apis/im/v1/messages")[0]!.body.content).type, "card");
    r.surface.working(here, "om_a", "正在运行命令…", null);
    await settle();
    assert.equal(r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length, 0, "not within the second");
    await r.t.adjust(1000);
    await r.fake.until("changed", () => r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length === 1);
    await r.t.adjust(64_000);
    await r.surface.post(here, "好了", []);
    r.surface.working(here, "om_a", "", null);
    await r.fake.until("done", () => r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length === 2);
    const puts = r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//);
    assert.deepEqual(puts.map((p) => p.body.sequence), [1, 2]);
    const done = JSON.parse(puts[1]!.body.card.data).body.elements[0].content;
    assert.ok(done.includes("1 分 5 秒") && done.includes("(https://still.test/o/w/s/k)"), done);
  } finally {
    await r.close();
  }
});

test("hub: a Feishu connect's chat is one session, its threads on the connect's own surface; chat_post takes options cards there", async () => {
  const rig = new Rig();
  const r = await surfaceRig();
  try {
    rig.edit((raw) => raw.connects.push({ id: "fs", kind: "feishu", feishu: { appId: "cli_test", appSecret: "s" }, bind: { runtime: "claude" } }));
    await rig.hub.shutdown();
    rig.hub = rig.newHub({ chats: (id) => (id === "fs" ? r.surface : undefined) });
    assert.equal(hubConfig(rig.raw, rig.dir).connects.find((c) => c.id === "fs")!.kind, "feishu");
    await rig.accept({ channel: "oc_g", threadTs: "om_a", ts: "om_a", user: "ou_ada", text: "@Bot 帮忙", addressed: true }, "fs");
    await rig.accept({ channel: "oc_g", threadTs: "om_a", ts: "om_b", user: "ou_ada", text: "没 @ 也算", addressed: false }, "fs");
    await settle();
    const key = "fs:oc_g:om_a";
    assert.ok(rig.store.getSession(key));
    const thread = rig.store.threadAt("feishu:fs", "oc_g", "om_a")!;
    assert.deepEqual(rig.said(thread.id).map((m) => m.text), ["@Bot 帮忙", "没 @ 也算"]);
    rig.claude.last().reads();
    const answer = await rig.call(key, "chat_post", { to: "oc_g/om_a", text: "选哪个", card: { type: "options", options: [{ label: "A" }, { label: "B" }] }, kind: "need_human", need: "选 A 或 B" });
    assert.ok(answer.startsWith("Posted to oc_g/om_a"), answer);
    const card = r.fake.calls("POST", "/open-apis/im/v1/messages").map((c) => JSON.parse(c.body.content)).find((c) => JSON.stringify(c).includes("button"));
    assert.deepEqual(card.body.elements.filter((e: Json) => e.tag === "button").map((b: Json) => b.text.content), ["A", "B"]);
    const loginPost = await rig.call(key, "chat_post", { to: "oc_g/om_a", text: "登录 https://app.still.fail/w/ws/s/st/login/abc", card: { type: "login", login: "abc" } });
    assert.ok(loginPost.startsWith("Posted to oc_g/om_a"), loginPost);
    assert.deepEqual(rig.store.cardAt(thread.id, rig.store.messagesBefore(thread.id, null, 1)[0]!.ts), { type: "login", login: "abc" });
  } finally {
    await r.close();
    await rig.close();
  }
});

test("thread mode: kept in a connect's Feishu part as asked, and only where each conversation has its own session", async () => {
  const { feishuConnects } = await import("../src/feishu/index.ts");
  const { feishuEntry } = await import("../src/api/routes/feishu.ts");
  const had = { appId: "cli_1", appSecret: "s", domain: "feishu" };
  const on = feishuEntry({ threads: true }, had)!;
  assert.deepEqual(on, { ...had, threads: true });
  assert.deepEqual(feishuEntry({ appId: "cli_1" }, on), on, "an edit that does not say keeps it");
  assert.deepEqual(feishuEntry({ threads: false }, on), { ...had, threads: false });
  const of = (mode: string, feishu: Json) => feishuConnects({ connects: [{ id: "f", kind: "feishu", mode, feishu }] })[0]!.threads;
  assert.deepEqual([of("multi-session", on), of("single-session", on), of("multi-session", had)], [true, false, false]);
});

test("routes: a connect of an app given by its id and secret, or made by a scan; edits keep its app; its secret replaced once checked", async () => {
  const fake = await FakeFeishu.start();
  fake.answer("POST /oauth/v1/app/registration", (s: Json) =>
    s.body.action === "init"
      ? { supported_auth_methods: ["client_secret"] }
      : s.body.action === "begin"
        ? { device_code: "dc", verification_uri_complete: `${fake.base}/verify?code=1`, interval: 0, expires_in: 600 }
        : { client_id: "cli_scan", client_secret: "sec2" },
  );
  const was = process.env.STILLFAIL_FEISHU_API;
  process.env.STILLFAIL_FEISHU_API = fake.base;
  const data = mkdtempSync(join(tmpdir(), "fr-"));
  delete process.env.STILLFAIL_CONFIG;
  delete process.env.EMBER_CONFIG;
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], connects: [] }));
  const { ConfigFile } = await import("../src/ops/config.ts");
  const { Store } = await import("../src/store/store.ts");
  const { makeFeishu } = await import("../src/feishu/index.ts");
  const { feishuRoutes } = await import("../src/api/routes/feishu.ts");
  const config = new ConfigFile(data);
  const store = Store.open(":memory:", null);
  const feishu = makeFeishu({ data, store, config, receive: async () => {}, bound: () => true });
  const viewer = { sub: "s", email: "owner@example.com", name: "Owner", role: "owner", workspace: "ws", device: "d" } as Json;
  let failOverview = false;
  const table = feishuRoutes({ feishu, config, data, hub: () => undefined, overview: () => { if (failOverview) throw new Error("overview unavailable"); return { connects: config.raw().connects }; } });
  const ask = async (method: string, path: string, body?: unknown): Promise<[number, Json]> => {
    for (const route of table) {
      const found = route.method === method ? route.pattern.exec(path) : null;
      if (found) {
        const a = await route.handle({ method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "zh" }, found.slice(1));
        return [a.status, JSON.parse(String(a.body))];
      }
    }
    return [404, null];
  };
  try {
    const [bad, said] = await ask("POST", "/feishu/verify", { appId: "nope", appSecret: "x" });
    assert.deepEqual([bad, said.identity, said.errors], [200, null, ["App ID 应形如 cli_xxx"]]);
    const [made, answer] = await ask("POST", "/feishu/connects", { feishu: { appId: "cli_test", appSecret: "s" }, bind: { runtime: "claude" } });
    assert.equal(made, 200, JSON.stringify(answer));
    assert.equal(answer.id, "codex");
    const kept = config.raw().connects.find((c: Json) => c.id === "codex");
    assert.deepEqual([kept.kind, kept.feishu.appId, kept.feishu.appSecret, kept.feishu.botOpenId, kept.feishu.tenant, kept.bind], ["feishu", "cli_test", "s", "ou_bot", { key: "tk1", name: "Acme" }, { runtime: "claude" }]);
    await fake.until("connected", () => feishu.state("codex")?.state === "connected");
    // Its app stays through an edit of what every connect has.
    const { connectEdits } = await import("../src/api/routes/connects.ts");
    const { feishuEntry } = await import("../src/api/routes/feishu.ts");
    await connectEdits({ config, data, hub: () => undefined, overview: () => ({}), entry: (kind) => (kind === "feishu" ? feishuEntry : undefined) }).putConnect({ method: "PUT", path: "", query: [], headers: {}, body: Buffer.from(""), viewer, lang: "zh" }, "codex", { enabled: false });
    assert.deepEqual([config.raw().connects[0].enabled, config.raw().connects[0].feishu.appId], [false, "cli_test"]);
    const [secret] = await ask("PUT", "/feishu/connects/codex/secret", { appSecret: "s2" });
    assert.equal(secret, 200);
    assert.equal(config.raw().connects[0].feishu.appSecret, "s2");
    // Made by a scan: followed until its app came, then a connect of it.
    const [begun, reg] = await ask("POST", "/feishu/registrations", { name: "Codex 机器人" });
    assert.equal(begun, 200);
    await fake.until("registered", () => feishu.registrations.get(reg.id)?.state === "done");
    const [refused] = await ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "not-a-runtime" } });
    assert.equal(refused, 400);
    assert.equal(feishu.registrations.get(reg.id)?.state, "done", "a failed save keeps the app for another attempt");
    const [scanned, second] = await ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } });
    assert.equal(scanned, 200, JSON.stringify(second));
    assert.equal(second.id, "codex-2");
    assert.equal(config.raw().connects[1].feishu.appId, "cli_scan");
    assert.equal(feishu.registrations.get(reg.id)?.connectId, second.id, "the saved result makes a repeated request idempotent");
    const [again, repeated] = await ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } });
    assert.deepEqual([again, repeated.id, config.raw().connects.length], [200, second.id, 2]);
    const [, reg2] = await ask("POST", "/feishu/registrations");
    await fake.until("registered again", () => feishu.registrations.get(reg2.id)?.state === "done");
    failOverview = true;
    const [answerLost] = await ask("POST", "/feishu/connects", { feishu: { registration: reg2.id }, bind: { runtime: "claude" } });
    assert.equal(answerLost, 500, "the overview failed after the connection was written");
    assert.equal(config.raw().connects.length, 3);
    failOverview = false;
    const [retry, afterLost] = await ask("POST", "/feishu/connects", { feishu: { registration: reg2.id }, bind: { runtime: "claude" } });
    assert.deepEqual([retry, afterLost.id, config.raw().connects.length], [200, config.raw().connects[2].id, 3], "retry finds the committed connection");
  } finally {
    if (was === undefined) delete process.env.STILLFAIL_FEISHU_API;
    else process.env.STILLFAIL_FEISHU_API = was;
    await feishu.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("scan: the station resumes a waiting scan and retries a failed save after restarts, without a client or another app", async () => {
  const fake = await FakeFeishu.start();
  let confirmed = false;
  fake.answer("POST /oauth/v1/app/registration", (s: Json) =>
    s.body.action === "init" ? { supported_auth_methods: ["client_secret"] }
      : s.body.action === "begin" ? { device_code: "dc", verification_uri_complete: `${fake.base}/verify?code=1`, interval: 5, expires_in: 600 }
      : confirmed ? { client_id: "cli_scan", client_secret: "scan-secret" } : { error: "authorization_pending" },
  );
  const was = process.env.STILLFAIL_FEISHU_API;
  process.env.STILLFAIL_FEISHU_API = fake.base;
  const data = mkdtempSync(join(tmpdir(), "fr-restart-"));
  const t = testClock();
  delete process.env.STILLFAIL_CONFIG;
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [] }));
  const { ConfigFile } = await import("../src/ops/config.ts");
  const { Store } = await import("../src/store/store.ts");
  const { makeFeishu } = await import("../src/feishu/index.ts");
  const { feishuRoutes } = await import("../src/api/routes/feishu.ts");
  const config = new ConfigFile(data);
  const store = Store.open(":memory:", null);
  const viewer = { sub: "s", email: "owner@example.com", name: "Owner", role: "owner", workspace: "joined", device: "d" } as Json;
  let failures = 0;
  let failSave = true;
  config.check = () => { if (failSave) { failures++; throw new Error("injected config write failure"); } };
  let feishu = makeFeishu({ data, store, config, clock: t.clock, receive: async () => {}, bound: () => false });
  const routes = () => feishuRoutes({ feishu, config, data, hub: () => undefined, overview: () => ({ connects: config.raw().connects }), place: () => ({ origin: "x", station: "st", workspace: "home" }) });
  let table = routes();
  const ask = async (method: string, path: string, body?: unknown): Promise<[number, Json]> => {
    const route = table.find((route) => route.method === method && route.pattern.test(path))!;
    const a = await route.handle({ method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "zh" }, route.pattern.exec(path)!.slice(1));
    return [a.status, JSON.parse(String(a.body))];
  };
  try {
    const [status, reg] = await ask("POST", "/feishu/registrations", { bind: { runtime: "claude", model: "chosen-model" }, mode: "multi-session", requireMention: false, threads: true });
    assert.equal(status, 200);
    const journal = join(data, "feishu-registrations.json");
    assert.equal(statSync(journal).mode & 0o777, 0o600);
    await feishu.close();
    confirmed = true;
    feishu = makeFeishu({ data, store, config, clock: t.clock, receive: async () => {}, bound: () => false });
    table = routes();
    await t.adjust(5000);
    await fake.until("save failed", () => failures > 0);
    assert.equal(config.raw().connects.length, 0);
    assert.equal(feishu.registrations.get(reg.id)?.app?.appSecret, "scan-secret", "the app survives a rejected config write");
    assert.match(readFileSync(journal, "utf8"), /scan-secret/);
    const polls = fake.calls("POST", "/oauth/v1/app/registration").filter((c) => c.body.action === "poll").length;
    await feishu.close();
    failSave = false;
    feishu = makeFeishu({ data, store, config, clock: t.clock, receive: async () => {}, bound: () => false });
    table = routes();
    await fake.until("saved after restart", () => typeof feishu.registrations.get(reg.id)?.connectId === "string");
    const kept = config.raw().connects;
    assert.equal(kept.length, 1);
    assert.deepEqual([kept[0].feishu.appId, kept[0].feishu.appSecret, kept[0].bind, kept[0].workspace, kept[0].requireMention, kept[0].feishu.threads], ["cli_scan", "scan-secret", { runtime: "claude", model: "chosen-model" }, "joined", false, true]);
    assert.doesNotMatch(readFileSync(journal, "utf8"), /scan-secret|device_code|verify\?code/);
    const [one, two] = await Promise.all([ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } }), ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } })]);
    assert.deepEqual([one[0], two[0], one[1].id, two[1].id, config.raw().connects.length], [200, 200, kept[0].id, kept[0].id, 1]);
    viewer.workspace = "other";
    const [wrongWorkspace] = await ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } });
    assert.equal(wrongWorkspace, 400, "a registration belongs to its creator and workspace");
    viewer.workspace = "joined";
    assert.equal(fake.calls("POST", "/oauth/v1/app/registration").filter((c) => c.body.action === "begin").length, 1);
    assert.equal(fake.calls("POST", "/oauth/v1/app/registration").filter((c) => c.body.action === "poll").length, polls, "saving the app never starts another scan");
  } finally {
    if (was === undefined) delete process.env.STILLFAIL_FEISHU_API;
    else process.env.STILLFAIL_FEISHU_API = was;
    await feishu.close();
    await t.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("surface: a person known without an email is asked for again after a day, one with an email never", async () => {
  const r = await surfaceRig({ names: true });
  try {
    const known = () => r.surface.knownPerson("ou_bo");
    const asked = () => r.fake.calls("GET", "/open-apis/contact/v3/users/ou_bo").length;
    // Another person's answer: what the book would have asked about Bo by then has been asked.
    const others = (id: string) => r.fake.until(id, () => r.surface.knownPerson(id) !== null);
    let email = "";
    r.fake.answer("GET /open-apis/contact/v3/users/ou_bo", () => ({ code: 0, data: { user: { name: "Bo", email } } }));
    assert.equal(known(), null);
    await r.fake.until("Bo learned", () => known() !== null);
    assert.deepEqual(known(), { name: "Bo", email: "" });
    await others("ou_a");
    assert.equal(asked(), 1, "not again within the day");
    email = "bo@example.test";
    await r.t.adjust(24 * 60 * 60_000);
    assert.deepEqual(known(), { name: "Bo", email: "" }, "what is known answers at once");
    await r.fake.until("Bo's email", () => known()?.email === "bo@example.test");
    assert.equal(asked(), 2);
    await r.t.adjust(24 * 60 * 60_000);
    known();
    await others("ou_b");
    assert.equal(asked(), 2, "an email found stays");
  } finally {
    await r.close();
  }
});

test("surface: a person found by their email (contact batch_get_id), their open_id, kept once found; none where not found or the app may not ask", async () => {
  const r = await surfaceRig();
  try {
    let may = true;
    r.fake.answer("POST /open-apis/contact/v3/users/batch_get_id", (seen: Json) =>
      !may ? { code: 99991672, msg: "Access denied. One of the following scopes is required: [contact:user.id:readonly]" }
        : { code: 0, data: { user_list: (seen.body.emails as string[]).map((email) => (email === "ada@example.test" ? { email, user_id: "ou_ada" } : { email })) } },
    );
    assert.deepEqual([await r.surface.userOf("Ada@example.test"), await r.surface.userOf("bo@example.test")], ["ou_ada", null]);
    const asked = r.fake.calls("POST", "/open-apis/contact/v3/users/batch_get_id");
    assert.deepEqual(asked.map((s) => [s.query.user_id_type, s.body]), [["open_id", { emails: ["ada@example.test"] }], ["open_id", { emails: ["bo@example.test"] }]]);
    may = false;
    assert.deepEqual([await r.surface.userOf("ada@example.test"), await r.surface.userOf("bo@example.test")], ["ou_ada", null], "one found is kept");
    assert.equal(r.surface.mention("ou_ada"), "<at id=ou_ada></at>");
  } finally {
    await r.close();
  }
});
