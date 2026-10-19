// The Feishu connect (docs/feishu.md): its frames, what its events say, its cards, its threads, its app registration,
// and its surface against Feishu's stand-in (test/feishu-fake.ts), through a hub with scripted runtimes.
import assert from "node:assert/strict";
import { gunzipSync } from "node:zlib";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { questionCard, textCards, took } from "../src/feishu/cards.ts";
import { CONTROL, DATA, Parts, decode, encode, header } from "../src/feishu/frame.ts";
import { messageOf, resourceOf } from "../src/feishu/parse.ts";
import { ADDONS, Registrations, encodeAddons } from "../src/feishu/register.ts";
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

test("cards: long text in several; a question's buttons with the recommended one last and filled, a text card's field", () => {
  const long = textCards(`${"字".repeat(5000)}\n\n${"字".repeat(5000)}`);
  assert.equal(long.length, 2);
  assert.equal(long[0].schema, "2.0");
  const q = questionCard("选一个", { type: "options", options: [{ label: "合并", recommended: true }, { label: "先不", detail: "留着分支" }] }, "om_t", "zh");
  const buttons = q.body.elements.filter((e: Json) => e.tag === "button");
  assert.deepEqual(buttons.map((b: Json) => [b.text.content, b.type, b.behaviors[0].value]), [
    ["先不", "default", { sf: "answer", t: "om_t", l: "先不" }],
    ["合并", "primary_filled", { sf: "answer", t: "om_t", l: "合并" }],
  ]);
  const t = questionCard("写个名字", { type: "text", placeholder: "名字" }, "om_t", "zh");
  const form = t.body.elements.find((e: Json) => e.tag === "form");
  assert.equal(form.elements[0].placeholder.content, "名字");
  assert.equal(form.elements[1].form_action_type, "submit");
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
    assert.equal(reg.take(r.id, "b@x.test"), null, "only its maker's");
    assert.deepEqual(reg.take(r.id, "a@x.test")!.app, { appId: "cli_new", appSecret: "sec", openId: "ou_me" });
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

/// A surface on Feishu's stand-in, with its threads in a temporary directory.
async function surfaceRig(o: { topics?: boolean; before?: (threads: FeishuThreads, fake: FakeFeishu) => void } = {}) {
  const fake = await FakeFeishu.start();
  if (o.topics) fake.answer("GET /open-apis/im/v1/chats/oc_t", { code: 0, data: { name: "话题群", chat_mode: "group", group_message_type: "thread" } });
  const dir = mkdtempSync(join(tmpdir(), "fs-"));
  const t = testClock();
  const threads = new FeishuThreads(join(dir, "threads.json"));
  o.before?.(threads, fake);
  const surface = new FeishuSurface({ connect: "fs", appId: "cli_test", appSecret: "s", domain: "feishu", threads, client: new FeishuClient("cli_test", "s", "feishu", fake.base), clock: t.clock });
  const events: ChatEvent[] = [];
  await surface.start(async (e) => void events.push(e));
  await fake.until("connected", () => surface.socket().connected);
  return {
    fake, surface, events, threads, t,
    close: async () => {
      await surface.stop();
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
                  { message_id: "om_old", create_time: "1000000", msg_type: "text", body: { content: JSON.stringify({ text: "已经听过" }) }, sender: { id: "ou_ada", sender_type: "user" } },
                  { message_id: "om_away", create_time: "1000500", msg_type: "text", body: { content: JSON.stringify({ text: "@_user_1 不在时说的" }) }, sender: { id: "ou_ada", sender_type: "user" }, mentions: [{ key: "@_user_1", id: "ou_bot", name: "Bot" }] },
                  { message_id: "om_mine", create_time: "1000600", msg_type: "interactive", body: { content: "{}" }, sender: { id: "cli_test", sender_type: "app" } },
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
    assert.equal(JSON.parse(reply[0]!.body.content).body.elements[0].content, "答案");
  } finally {
    await r.close();
  }
});

test("surface: posts as cards in the chat, files after them; a question's button answers as the person and the card shows the answer", async () => {
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
      ["chat_id", "oc_g", "interactive"],
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

test("surface: the status card follows the agent's steps at most once a second and ends saying how long it took, with the history's link", async () => {
  const r = await surfaceRig();
  try {
    const here = { channel: "oc_g", threadTs: "om_a" };
    r.surface.working(here, "om_a", "正在思考…", "https://still.test/o/w/s/k");
    await r.fake.until("card made", () => r.fake.calls("POST", "/open-apis/im/v1/messages").length === 1);
    assert.equal(JSON.parse(r.fake.calls("POST", "/open-apis/im/v1/messages")[0]!.body.content).type, "card");
    r.surface.working(here, "om_a", "正在运行命令…", null);
    await settle();
    assert.equal(r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length, 0, "not within the second");
    await r.t.adjust(1000);
    await r.fake.until("changed", () => r.fake.calls("PUT", /^\/open-apis\/cardkit\/v1\/cards\//).length === 1);
    await r.t.adjust(64_000);
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
    const answer = await rig.call(key, "chat_post", { to: "oc_g/om_a", text: "选哪个", card: { type: "options", options: [{ label: "A" }, { label: "B" }] }, kind: "need_human", need: "选 A 或 B" });
    assert.ok(answer.startsWith("Posted to oc_g/om_a"), answer);
    const card = r.fake.calls("POST", "/open-apis/im/v1/messages").map((c) => JSON.parse(c.body.content)).find((c) => JSON.stringify(c).includes("button"));
    assert.deepEqual(card.body.elements.filter((e: Json) => e.tag === "button").map((b: Json) => b.text.content), ["A", "B"]);
    assert.match(await rig.refused(key, "chat_post", { to: "oc_g/om_a", text: "登录", card: { type: "login", login: "abc" } }), /login card is shown only in still\.fail/);
  } finally {
    await r.close();
    await rig.close();
  }
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
  const table = feishuRoutes({ feishu, config, data, hub: () => undefined, overview: () => ({ connects: config.raw().connects }) });
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
    const { connectEdits } = await import("../src/api/routes/slack.ts");
    await connectEdits({ config, data, hub: () => undefined, overview: () => ({}) }).putConnect({ method: "PUT", path: "", query: [], headers: {}, body: Buffer.from(""), viewer, lang: "zh" }, "codex", { enabled: false });
    assert.deepEqual([config.raw().connects[0].enabled, config.raw().connects[0].feishu.appId], [false, "cli_test"]);
    const [secret] = await ask("PUT", "/feishu/connects/codex/secret", { appSecret: "s2" });
    assert.equal(secret, 200);
    assert.equal(config.raw().connects[0].feishu.appSecret, "s2");
    // Made by a scan: followed until its app came, then a connect of it.
    const [begun, reg] = await ask("POST", "/feishu/registrations", { name: "Codex 机器人" });
    assert.equal(begun, 200);
    await fake.until("registered", () => feishu.registrations.get(reg.id)?.state === "done");
    const [scanned, second] = await ask("POST", "/feishu/connects", { feishu: { registration: reg.id }, bind: { runtime: "claude" } });
    assert.equal(scanned, 200, JSON.stringify(second));
    assert.equal(second.id, "codex-2");
    assert.equal(config.raw().connects[1].feishu.appId, "cli_scan");
    assert.equal(feishu.registrations.get(reg.id), undefined, "taken");
  } finally {
    if (was === undefined) delete process.env.STILLFAIL_FEISHU_API;
    else process.env.STILLFAIL_FEISHU_API = was;
    await feishu.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});
