// A person's plugins (views/plugins.ts, docs/client-plugins.md): read from the station as it connects and kept up by
// its events; those whose share entry takes what is shared; a use sending what is shared into the plugin's chat, or
// putting it in its composer; one deleted.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Core } from "../src/core.ts";
import type { FakeHost } from "../src/testing.ts";
import { takes } from "../src/views/plugins.ts";
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

const sent = (host: FakeHost, method: string, path: string) =>
  host.requests.filter((r) => r.method === method && r.url.endsWith(`/admin/api${path}`)).map((r) => (r.body && r.body.length > 0 ? JSON.parse(new TextDecoder().decode(r.body)) : null));

const row = (id: string, thread: number, title: string, at: number) =>
  ({ id, session: id, thread, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null });

const DOUYIN = { id: "douyin", name: "抖音下载", entries: [{ kind: "share", match: "v\\.douyin\\.com" }], action: { kind: "chat", session: "k7", send: "auto" }, at: 1 };
const NOTES = { id: "notes", name: "存笔记", entries: [{ kind: "share" }], action: { kind: "chat", session: "k8", send: "composer" }, at: 1 };

function answers(): J {
  return {
    ...base(),
    "GET /overview": overview,
    "GET /threads": [threadView(7, 3), threadView(8, 1)],
    "GET /chats": [row("k8", 8, "读书笔记", 20), row("k7", 7, "抖音视频下载", 10)],
    "GET /plugins": { plugins: [DOUYIN, NOTES, { id: "later", name: "以后的", entries: [], action: { kind: "module" } }] },
    "POST /threads/7/messages": { n: 4 },
    "DELETE /plugins/notes": { ok: true },
  };
}

test("a share entry takes what its expression finds, in any case, or anything without one", () => {
  assert.equal(takes(DOUYIN as J, "复制打开抖音 https://V.DOUYIN.com/abc/"), true);
  assert.equal(takes(DOUYIN as J, "https://youtu.be/x"), false);
  assert.equal(takes(NOTES as J, "anything"), true);
  assert.equal(takes({ ...DOUYIN, entries: [{ kind: "share", match: "(" }] } as J, "("), false);
});

test("the plugins a station keeps for this person: listed with their chats, matched, run, deleted, kept up by its events", async () => {
  const { host, core, push } = await started(answers());
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "plugins", scope: "ws" });
  await host.settle();
  apply(host, values);
  // A kind this core does not know is left out; by name (as code points: no Intl in Hermes), each with its chat's title.
  assert.deepEqual(v(values, 1).items.map((p: J) => [p.id, p.station, p.chat]), [["notes", "ws/st", "读书笔记"], ["douyin", "ws/st", "抖音视频下载"]]);

  const shared = "7.10 复制打开抖音，看看【昔年的作品】 https://v.douyin.com/0LYqjyDj3Q0/ RKj:/";
  subscribe(core, ui, 2, { topic: "plugins", scope: "ws", source: shared });
  subscribe(core, ui, 3, { topic: "plugins", scope: "ws", source: "https://youtu.be/x" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2).items.map((p: J) => p.id), ["notes", "douyin"]);
  assert.deepEqual(v(values, 3).items.map((p: J) => p.id), ["notes"]);

  // Sent at once, as the person's message, the whole of what was shared.
  const ran = await ask(host, core, ui, 4, "plugins.run", { scope: "ws", station: "ws/st", id: "douyin", source: ` ${shared} ` });
  assert.deepEqual(ran, { station: "ws/st", session: "k7", key: "ws/st:k7", title: "抖音视频下载", sent: true });
  await host.settle();
  assert.deepEqual(sent(host, "POST", "/threads/7/messages").map((m) => m.text), [shared]);

  // Into the composer: nothing sent, the link as an attachment there.
  const put = await ask(host, core, ui, 5, "plugins.run", { scope: "ws", station: "ws/st", id: "notes", source: "https://a.com/x" });
  assert.equal(put.sent, false);
  subscribe(core, ui, 6, { topic: "composer", key: "ws/st:k8" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 6).files.map((f: J) => f.link?.url), ["https://a.com/x"]);
  assert.equal(sent(host, "POST", "/threads/8/messages").length, 0);
  await assert.rejects(ask(host, core, ui, 7, "plugins.run", { scope: "ws", station: "ws/st", id: "douyin", source: "  " }));

  // The agent changes one and saves another; one goes.
  push("plugin", { ...DOUYIN, name: "抖音" });
  push("plugin", { id: "bili", name: "B 站", entries: [{ kind: "share", match: "b23\\.tv" }], action: { kind: "chat", session: "k7", send: "auto" }, at: 2 });
  push("plugin-gone", { id: "notes" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).items.map((p: J) => p.name), ["B 站", "抖音"]);

  // Deleted from here: asked of the station, gone at once.
  push("plugin", NOTES);
  await host.settle();
  await ask(host, core, ui, 8, "plugins.delete", { scope: "ws", station: "ws/st", id: "notes" });
  apply(host, values);
  assert.equal(sent(host, "DELETE", "/plugins/notes").length, 1);
  assert.deepEqual(v(values, 1).items.map((p: J) => p.id), ["bili", "douyin"]);
  await assert.rejects(ask(host, core, ui, 9, "plugins.run", { scope: "ws", station: "ws/st", id: "notes", source: "x" }));
  core.close();
});
