// What another app shares into still.fail (share-in.ts): where it can go, where it goes by default (the chat a thing
// from the same site went to last), and sending it there, into a chat or a new one.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Core } from "../src/core.ts";
import { messageOf, siteOf } from "../src/share-in.ts";
import type { FakeHost } from "../src/testing.ts";
import { PENDING_PREFIX } from "../src/views/local.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { base, overview, started, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

async function ask(host: FakeHost, core: Core, ui: number, id: number, name: string, params: unknown): Promise<J> {
  call(core, ui, id, name, params);
  await host.settle();
  let out: { ok: J } | { error: J } | null = null;
  const rest: typeof host.emitted = [];
  for (const [c, m] of host.takeEmitted()) {
    const x = m as J;
    if (x.id === id && "ok" in x) out = { ok: x.ok };
    else if (x.id === id && "error" in x) out = { error: x.error };
    else rest.push([c, m]);
  }
  host.emitted.push(...rest);
  if (!out) throw new Error(`${name} not answered`);
  if ("error" in out) throw Object.assign(new Error(out.error.message), out.error);
  return out.ok;
}

const posted = (host: FakeHost, path: string) =>
  host.requests.filter((r) => r.method === "POST" && r.url.endsWith(`/admin/api${path}`)).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));

const row = (id: string, thread: number, title: string, at: number, extra: J = {}) =>
  ({ id, session: id, thread, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null, ...extra });

const profile = {
  id: "p1", name: "p1@x.com", runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null,
  models: ["claude-opus-5-5"], env: [], usedBy: [], loginCommand: "", check: { state: "ok", detail: "", checkedAt: 1 },
  quota: { state: "ok", windows: [], detail: null, checkedAt: 1 },
};

function answers(): J {
  return {
    ...base(),
    "GET /overview": { ...overview, profiles: [profile] },
    "GET /threads": [threadView(7, 3), threadView(8, 1), threadView(9, 1)],
    "GET /chats": [
      row("k9", 9, "Slack 里的", 30, { origin: { channel: "C1", threadTs: "1.0" }, connect: "slack" }),
      row("k8", 8, "读书笔记", 20),
      row("k7", 7, "视频管理", 10),
    ],
    "POST /threads/7/messages": { n: 4 },
    "POST /threads/8/messages": { n: 2 },
    "POST /sessions": { key: "k10", thread: { id: 10 } },
    "POST /threads/10/messages": { n: 1 },
  };
}

test("a_link_shared_goes_where_one_from_its_site_went_last_and_a_new_chat_is_one_of_the_places", async () => {
  const { host, core } = await started(answers());
  const ui = core.connect();
  const values = new Map();
  const yt = "https://www.youtube.com/watch?v=abc";
  subscribe(core, ui, 1, { topic: "shareIn", scope: "ws", source: yt });
  await host.settle();
  apply(host, values);
  let view = v(values, 1);
  // Only still.fail's chats (a Slack chat takes no message from here), newest first; the latest picked.
  assert.deepEqual(view.items.map((i: J) => i.title), ["读书笔记", "视频管理"]);
  assert.equal(view.site, "youtube.com");
  assert.equal(view.kept ?? null, null);
  assert.deepEqual(view.picked, { station: "ws/st", id: "k8" });
  assert.deepEqual(view.stations, [{ station: "ws/st", name: "studio" }]);

  // Picked and sent: in that chat at once, what was added first, and the site remembered.
  await ask(host, core, ui, 2, "shareIn.pick", { scope: "ws", source: yt, station: "ws/st", id: "k7" });
  apply(host, values);
  assert.deepEqual(v(values, 1).picked, { station: "ws/st", id: "k7" });
  const sent = await ask(host, core, ui, 3, "shareIn.send", { scope: "ws", source: yt, text: "下到 station 上" });
  assert.deepEqual(sent, { station: "ws/st", session: "k7", thread: 7, title: "视频管理" });
  await host.settle();
  assert.equal(posted(host, "/threads/7/messages").at(-1)?.text, `下到 station 上\n\n${yt}`);

  // Another link from the site, by its short host: that chat first, saying why, and picked.
  const short = "看看这个 https://youtu.be/xyz";
  subscribe(core, ui, 4, { topic: "shareIn", scope: "ws", source: short });
  await host.settle();
  apply(host, values);
  view = v(values, 4);
  assert.deepEqual(view.items.map((i: J) => i.title), ["视频管理", "读书笔记"]);
  assert.deepEqual(view.kept, { station: "ws/st", id: "k7", text: "youtube.com 的链接上次发到这里" });
  assert.deepEqual(view.picked, { station: "ws/st", id: "k7" });
  // What is typed narrows the list; the one picked is still where it goes.
  subscribe(core, ui, 5, { topic: "shareIn", scope: "ws", source: short, query: "读书" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 5).items.map((i: J) => i.title), ["读书笔记"]);

  // Text from another app (no link) goes to a new chat, made on the station: the message waits in it meanwhile.
  const text = "一段笔记";
  subscribe(core, ui, 6, { topic: "shareIn", scope: "ws", source: text });
  await ask(host, core, ui, 7, "shareIn.pick", { scope: "ws", source: text, station: "ws/st" });
  apply(host, values);
  assert.deepEqual(v(values, 6).picked, { station: "ws/st" });
  const made = await ask(host, core, ui, 8, "shareIn.send", { scope: "ws", source: text, title: "标题" });
  assert.ok(String(made.session).startsWith(PENDING_PREFIX), JSON.stringify(made));
  assert.equal(made.title, "新 chat");
  await host.settle();
  assert.equal(posted(host, "/sessions").length, 1);
  assert.equal(posted(host, "/threads/10/messages").at(-1)?.text, "标题\n一段笔记");
  core.close();
});

test("a_shared_things_site_and_message", () => {
  assert.equal(siteOf("https://m.bilibili.com/video/BV1"), "bilibili.com");
  assert.equal(siteOf("【标题】 https://b23.tv/abc"), "bilibili.com");
  assert.equal(siteOf("https://youtu.be/x"), "youtube.com");
  assert.equal(siteOf("没有链接"), null);
  assert.equal(messageOf("https://a.com/x", "A 的标题", null), "A 的标题\nhttps://a.com/x");
  assert.equal(messageOf("A 的标题 https://a.com/x", "A 的标题", " 说一句 "), "说一句\n\nA 的标题 https://a.com/x");
});
