// Android keeps its composer through the public draft API. Its temporary chat key and the station's session key
// must read and replace the same draft, including when the process and its in-memory drafts are gone.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { SOON_MS } from "../src/data.ts";
import { HostWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { answers, call, signIn } from "./helpers.ts";

async function setup() {
  const host = new FakeHost();
  signIn(host);
  host.onFetch((request) => {
    const path = new URL(request.url).pathname;
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: null });
    // Both stations belong to this account: normal retention must keep their drafts across restarts.
    if (path === "/v1/workspaces/ws") return jsonResponse(200, {
      id: "ws",
      stations: ["st", "other"].map((id) => ({ id, name: id, online: false, last_seen: null })),
    });
    return jsonResponse(404, { error: "not_found" });
  });
  const open = () => Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  let core = await open();
  await host.time.pass(500);
  let ui = core.connect();
  let id = 0;
  return {
    get core() { return core; },
    async ask(name: "draft.get" | "draft.put", params: unknown) {
      const at = ++id;
      call(core, ui, at, name, params);
      await host.settle();
      const answer = answers(host.takeEmitted(), at);
      assert.ok(answer && "ok" in answer, `${name} did not succeed: ${JSON.stringify(answer)}`);
      return answer.ok;
    },
    async restart() {
      await host.time.pass(SOON_MS + 50);
      await host.settle();
      await Effect.runPromise(core.inner.data.written);
      core.close();
      host.takeEmitted();
      core = await open();
      ui = core.connect();
    },
    close() { core.close(); },
  };
}

const blank = { text: "", quotes: [], files: [] };

test("android_draft_api_recovers_a_pending_chat_after_restart_and_clears_both_keys", async () => {
  const t = await setup();
  try {
    const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
    const original = `ws/st:${pending}`;
    const canonical = "ws/st:ember:made";
    const draft = {
      text: "还没发出去，重启后接着写",
      quotes: [{ author: "agent", text: "那段", comment: "为什么", ts: "1.0", role: "agent" }],
      files: [{ name: "a.png", path: "/u/a.png", size: 3 }],
    };
    await t.ask("draft.put", { key: original, ...draft });
    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    await t.restart();
    assert.deepEqual(await t.ask("draft.get", { key: canonical }), draft);
    assert.deepEqual(await t.ask("draft.get", { key: original }), draft);

    // The restarted Android page now writes under the station's key; returning to the old page sees the edit too.
    const edited = { ...draft, text: "重启后修改过" };
    await t.ask("draft.put", { key: canonical, ...edited });
    assert.deepEqual(await t.ask("draft.get", { key: original }), edited);
    await t.restart();
    assert.deepEqual(await t.ask("draft.get", { key: canonical }), edited);
    await t.ask("draft.put", { key: canonical, ...blank });
    await t.restart();
    assert.deepEqual(await t.ask("draft.get", { key: original }), blank);
    assert.deepEqual(await t.ask("draft.get", { key: canonical }), blank);
  } finally { t.close(); }
});

test("draft_api_prefers_the_canonical_copy_and_never_crosses_station_boundaries", async () => {
  const t = await setup();
  try {
    const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
    // Two copies left by an older client: the next page after restart wrote under the station key.
    const old = { ...blank, text: "创建时写的旧稿" };
    const latest = { ...blank, text: "重启后继续写的稿" };
    const other = { ...blank, text: "另一台 station 的内容" };
    await t.ask("draft.put", { station: "ws/st", chat: pending, ...old });
    await t.ask("draft.put", { station: "ws/st", chat: "ember:made", ...latest });
    await t.ask("draft.put", { station: "ws/other", chat: "ember:made", ...other });
    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    await t.restart();
    assert.deepEqual(await t.ask("draft.get", { station: "ws/st", chat: pending }), latest);
    assert.deepEqual(await t.ask("draft.get", { station: "ws/st", chat: "ember:made" }), latest);
    assert.deepEqual(await t.ask("draft.get", { station: "ws/other", chat: pending }), blank);
    assert.deepEqual(await t.ask("draft.get", { station: "ws/other", chat: "ember:made" }), other);

    await t.ask("draft.put", { station: "ws/st", chat: pending, ...blank });
    await t.restart();
    assert.deepEqual(await t.ask("draft.get", { station: "ws/st", chat: "ember:made" }), blank);
    assert.deepEqual(await t.ask("draft.get", { station: "ws/other", chat: "ember:made" }), other);
  } finally { t.close(); }
});

test("new_chat_and_thread_drafts_remain_separate_from_a_pending_sessions_draft", async () => {
  const t = await setup();
  try {
    const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    const drafts = [
      ["new:ws/st", "还没创建的新聊天"],
      ["ws/st:thread:9", "线程草稿"],
      [`ws/st:${pending}`, "已创建的聊天草稿"],
      ["ws/st:unrelated", "另一个聊天草稿"],
    ] as const;
    for (const [key, text] of drafts) await t.ask("draft.put", { key, ...blank, text });
    await t.restart();
    for (const [key, text] of drafts) assert.deepEqual(await t.ask("draft.get", { key }), { ...blank, text });
    assert.deepEqual(await t.ask("draft.get", { key: "ws/st:ember:made" }), { ...blank, text: drafts[2][1] });
  } finally { t.close(); }
});
