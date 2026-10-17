// What another app shares into still.fail (share-in.ts): where it can go, the chat a thing from the same site went to
// last first, and into the composer of the one picked (a chat's, or a new chat's).
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Core } from "../src/core.ts";
import { messageOf, siteOf } from "../src/share-in.ts";
import type { FakeHost } from "../src/testing.ts";
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

test("a_link_shared_goes_into_the_composer_of_the_chat_picked_and_that_chat_comes_first_for_its_site", async () => {
  const { host, core } = await started(answers());
  const ui = core.connect();
  const values = new Map();
  const yt = "https://www.youtube.com/watch?v=abc";
  subscribe(core, ui, 1, { topic: "shareIn", scope: "ws", source: yt });
  await host.settle();
  apply(host, values);
  let view = v(values, 1);
  // Only still.fail's chats (a Slack chat takes no message from here), newest first; a new chat on the station.
  assert.deepEqual(view.items.map((i: J) => i.title), ["读书笔记", "视频管理"]);
  assert.equal(view.site, "youtube.com");
  assert.equal(view.kept ?? null, null);
  assert.deepEqual(view.stations, [{ station: "ws/st", name: "studio" }]);
  assert.equal(view.newOn, "ws/st");

  // Into that chat's composer, after what is written there already; nothing is sent.
  await ask(host, core, ui, 2, "composer.text", { key: "ws/st:k7", text: "先看这个" });
  const opened = await ask(host, core, ui, 3, "shareIn.open", { scope: "ws", source: yt, station: "ws/st", id: "k7" });
  assert.deepEqual(opened, { station: "ws/st", key: "ws/st:k7", session: "k7", thread: 7, title: "视频管理" });
  subscribe(core, ui, 4, { topic: "composer", key: "ws/st:k7" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 4).text, `先看这个\n${yt}`);
  // Shared again: in it once.
  await ask(host, core, ui, 5, "shareIn.open", { scope: "ws", source: yt, station: "ws/st", id: "k7" });
  apply(host, values);
  assert.equal(v(values, 4).text, `先看这个\n${yt}`);
  assert.equal(posted(host, "/threads/7/messages").length, 0);

  // Another link from the site, by its short host: that chat first, saying why.
  const short = "看看这个 https://youtu.be/xyz";
  subscribe(core, ui, 6, { topic: "shareIn", scope: "ws", source: short });
  await host.settle();
  apply(host, values);
  view = v(values, 6);
  assert.deepEqual(view.items.map((i: J) => i.title), ["视频管理", "读书笔记"]);
  assert.deepEqual(view.kept, { station: "ws/st", id: "k7", text: "youtube.com 的链接上次发到这里" });
  // What is typed narrows the list.
  subscribe(core, ui, 7, { topic: "shareIn", scope: "ws", source: short, query: "读书" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 7).items.map((i: J) => i.title), ["读书笔记"]);

  // Text from another app, into a new chat's composer on the station, with the title the app gave.
  const made = await ask(host, core, ui, 8, "shareIn.open", { scope: "ws", source: "一段笔记", title: "标题", station: "ws/st" });
  assert.deepEqual(made, { station: "ws/st", key: "new:ws/st" });
  subscribe(core, ui, 9, { topic: "composer", key: "new:ws/st" });
  subscribe(core, ui, 10, { topic: "newChat", scope: "ws" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 9).text, "标题\n一段笔记");
  assert.equal(v(values, 10).kept, "st");
  assert.equal(posted(host, "/sessions").length, 0);
  // A page that keeps a new chat's words by a key of its own (the phone web's, before its station): there.
  await ask(host, core, ui, 11, "shareIn.open", { scope: "ws", source: "另一段", station: "ws/st", key: "new:" });
  subscribe(core, ui, 12, { topic: "composer", key: "new:" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 12).text, "另一段");
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
