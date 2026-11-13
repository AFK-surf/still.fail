// A Feishu reply (回复) that quotes a message brings that message to the agent with it: its words as a blockquote, its
// images and files fetched as the reply's own are. A real FeishuSurface on Feishu's stand-in, into a hub.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { FeishuSurface } from "../src/feishu/surface.ts";
import { FeishuThreads } from "../src/feishu/threads.ts";
import { FeishuClient } from "../src/feishu/web.ts";
import type { ChatEvent } from "../src/sessions/chat.ts";
import { FakeFeishu, RawAnswer } from "./feishu-fake.ts";
import { Rig, settle } from "./hub-fakes.ts";

type Json = any;

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

/// A message as `GET /im/v1/messages/:id` lists it.
const listed = (o: { id: string; type?: string; content: Json; user?: string; app?: boolean }) => ({
  code: 0,
  data: {
    items: [
      {
        message_id: o.id,
        chat_id: "oc_g",
        create_time: "1700000000000",
        msg_type: o.type ?? "text",
        body: { content: JSON.stringify(o.content) },
        sender: { id: o.app ? "cli_test" : (o.user ?? "ou_bob"), sender_type: o.app ? "app" : "user" },
      },
    ],
  },
});

/// A Feishu connect's surface on the stand-in, what it hears accepted by a hub.
async function quotedRig(o: { threadMode?: boolean } = {}) {
  const fake = await FakeFeishu.start();
  const dir = mkdtempSync(join(tmpdir(), "fsq-"));
  const scope = Effect.runSync(Scope.make());
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  const threads = new FeishuThreads(join(dir, "threads.json"));
  const surface = new FeishuSurface({ connect: "fs", appId: "cli_test", appSecret: "s", domain: "feishu", threads, threadMode: o.threadMode, client: new FeishuClient("cli_test", "s", "feishu", fake.base), clock });
  const rig = new Rig();
  rig.edit((raw) => raw.connects.push({ id: "fs", kind: "feishu", feishu: { appId: "cli_test", appSecret: "s" }, bind: { runtime: "claude" } }));
  await rig.hub.shutdown();
  rig.hub = rig.newHub({ chats: (id) => (id === "fs" ? surface : undefined) });
  const events: ChatEvent[] = [];
  await surface.start(async (e) => {
    events.push(e);
    if (e.type === "message") await rig.accept(e.message, "fs");
  });
  await fake.until("connected", () => surface.socket().connected);
  /// Sends a message and waits until the hub kept it.
  const say = async (m: Parameters<FakeFeishu["message"]>[0]) => {
    const frame = fake.message(m);
    await fake.until("kept", () => fake.ack(frame) !== undefined);
    await settle();
  };
  return {
    fake, rig, events, say,
    said: (threadTs: string) => rig.said(rig.store.threadAt("feishu:fs", "oc_g", threadTs)!.id),
    close: async () => {
      await surface.stop();
      await fake.close();
      await rig.close();
      await Effect.runPromise(Scope.close(scope, Exit.void));
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

for (const threadMode of [false, true]) {
  test(`quoted: an image posted before the bot was called, quoted with an @, comes with the reply as its file${threadMode ? " (thread mode)" : ""}`, async () => {
    const r = await quotedRig({ threadMode });
    try {
      r.fake.answer("GET /open-apis/im/v1/messages/om_img", listed({ id: "om_img", type: "image", content: { image_key: "img_k" } }));
      r.fake.answer("GET /open-apis/im/v1/messages/om_img/resources/img_k", () => new RawAnswer(JPEG, { "content-type": "image/jpeg" }));
      // Heard before anyone @s the bot: no conversation takes it.
      await r.say({ id: "om_img", user: "ou_bob", type: "image", content: { image_key: "img_k" } });
      assert.equal(r.rig.store.threadAt("feishu:fs", "oc_g", "om_img"), null);
      await r.say({ id: "om_q", text: "这张图是什么", at: true, parent: "om_img" });
      const rows = r.said(threadMode ? "om_img" : "om_q");
      assert.equal(rows.length, 1);
      assert.equal(rows[0]!.ts, "om_q");
      assert.equal(rows[0]!.text, "@Codex 机器人 这张图是什么");
      assert.deepEqual(rows[0]!.attachments.map((a) => [a.name, a.size]), [["img_k.png", JPEG.length]]);
      assert.deepEqual(new Uint8Array(await readFile(rows[0]!.attachments[0]!.path)), JPEG);
      assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages/om_img/resources/img_k").length, 1);
    } finally {
      await r.close();
    }
  });
}

test("quoted: a quoted text message comes before the reply's words as a blockquote", async () => {
  const r = await quotedRig();
  try {
    r.fake.answer("GET /open-apis/im/v1/messages/om_t", listed({ id: "om_t", content: { text: "部署失败了\n日志在群公告里" } }));
    await r.say({ id: "om_q", text: "看看这个", at: true, parent: "om_t" });
    const rows = r.said("om_q");
    assert.deepEqual(rows.map((m) => [m.ts, m.text, m.attachments.length]), [["om_q", "> 部署失败了\n> 日志在群公告里\n\n@Codex 机器人 看看这个", 0]]);
  } finally {
    await r.close();
  }
});

test("quoted: a message the conversation already has is not read again nor repeated", async () => {
  const r = await quotedRig();
  try {
    await r.say({ id: "om_a", text: "帮我看看", at: true });
    await r.say({ id: "om_b", text: "就是这条", at: true, parent: "om_a" });
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages/om_a").length, 0);
    assert.deepEqual(r.said("om_a").map((m) => [m.ts, m.text]), [
      ["om_a", "@Codex 机器人 帮我看看"],
      ["om_b", "@Codex 机器人 就是这条"],
    ]);
  } finally {
    await r.close();
  }
});

test("quoted: the bot's own message quoted brings nothing: the agent has its answers", async () => {
  const r = await quotedRig();
  try {
    r.fake.answer("GET /open-apis/im/v1/messages/om_bot9", listed({ id: "om_bot9", type: "post", content: { title: "", content: [[{ tag: "text", text: "之前的回答" }]] }, app: true }));
    await r.say({ id: "om_q", text: "再解释一下", at: true, parent: "om_bot9" });
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages/om_bot9").length, 1);
    assert.deepEqual(r.said("om_q").map((m) => [m.text, m.attachments.length]), [["@Codex 机器人 再解释一下", 0]]);
  } finally {
    await r.close();
  }
});

test("quoted: a quoted message that cannot be read leaves the reply as it is, still kept, its session begun", async () => {
  const r = await quotedRig();
  try {
    r.fake.answer("GET /open-apis/im/v1/messages/om_gone", { code: 230011, msg: "The message was recalled" });
    await r.say({ id: "om_q", text: "这个呢", at: true, parent: "om_gone" });
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages/om_gone").length, 1);
    assert.deepEqual(r.said("om_q").map((m) => [m.text, m.attachments.length]), [["@Codex 机器人 这个呢", 0]]);
    assert.ok(r.rig.store.getSession("fs:oc_g:om_q"));
  } finally {
    await r.close();
  }
});

test("quoted: replies that name the same message (a thread's first) bring it once a conversation", async () => {
  const r = await quotedRig();
  try {
    r.fake.answer("GET /open-apis/im/v1/messages/om_t", listed({ id: "om_t", content: { text: "原话" } }));
    await r.say({ id: "om_q", text: "看看这个", at: true, parent: "om_t" });
    await r.say({ id: "om_r", text: "再补一句", parent: "om_t" });
    assert.deepEqual(r.said("om_q").map((m) => m.text), ["> 原话\n\n@Codex 机器人 看看这个", "再补一句"]);
    assert.equal(r.fake.calls("GET", "/open-apis/im/v1/messages/om_t").length, 1);
  } finally {
    await r.close();
  }
});
