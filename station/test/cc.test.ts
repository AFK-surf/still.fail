// A person's message in a still.fail chat copied to the Slack or Feishu thread the chat is linked to (docs/relay.md
// "抄送"): which thread that is, what the bot says there, what is kept of it, a copy that did not go, and the page's
// side of it (the chat's `cc`, a message sent with `cc`).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { Readers } from "../src/read/pool.ts";
import { cc, ccText } from "../src/sessions/cc.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Hub } from "../src/sessions/hub.ts";
import { InternalChat } from "../src/sessions/internal.ts";
import { newSession } from "../src/sessions/lifecycle.ts";
import { Store } from "../src/store/store.ts";
import { FakeChat, FakeDriver, Rig, message, settle, testClock } from "./hub-fakes.ts";

test("a chat can be copied to every Slack thread its agents are in, the one said in last first", async () => {
  // (a clock of the test's: what is said one after another is said at times apart, never in the same millisecond)
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  const [key, chat] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  assert.deepEqual(r.store.ccThreads(chat.id), [], "a chat whose agent is in no Slack thread has none");
  const thread = (channel: string, ts: string) => {
    const t = r.store.openThread("slack:T1", channel, ts, null, "ada");
    r.store.joinThread(t.id, key, "cl");
    r.store.insertMessage({ thread: t.id, ts, authorKind: "ember", author: "ember", text: "here", attachments: [] });
    return t;
  };
  const first = thread("C1", "1700.000100");
  assert.deepEqual(r.store.ccThreads(chat.id).map((o) => [o.thread.id, o.connect]), [[first.id, "cl"]]);
  await time.adjust(1000);
  const second = thread("C2", "1700.000200");
  assert.deepEqual(r.store.ccThreads(chat.id).map((o) => o.thread.id), [second.id, first.id], "the one said in last first");
  // Something said in the first again: it comes first.
  await time.adjust(1000);
  await r.accept(message({ channel: "C1", threadTs: "1700.000100", ts: "1700.000300", user: "UBO", text: "more", addressed: false }));
  await settle();
  assert.deepEqual(r.store.ccThreads(chat.id).map((o) => o.thread.id), [first.id, second.id]);
  await r.close();
});

test("copying a message: each thread picked has the bot say who wrote it on still.fail and what, kept as the station's words, not the agent's to answer", async () => {
  const r = new Rig();
  const [key, chat] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const a = r.store.openThread("slack:T1", "C1", "1700.000100", null, "ada");
  r.store.joinThread(a.id, key, "cl");
  const b = r.store.openThread("slack:T1", "C2", "1700.000200", null, "ada");
  r.store.joinThread(b.id, key, "cl");
  const other = r.store.openThread("slack:T1", "C9", "1700.000900", null, "bo");
  const before = r.claude.sessions.length;
  // Both picked, and one that is not the chat's (left out).
  await cc(r.hub, chat.id, "Ada Lovelace", "ada@x.com", "can you look at #42?", [], [a.id, b.id, other.id]);
  const said = `${tr(stationLang(), "station.cc.said", { who: "Ada Lovelace" })}\n\ncan you look at #42?`;
  assert.equal(ccText("Ada Lovelace", "can you look at #42?"), said);
  assert.deepEqual(r.chat.posts.map((p) => p[0].channel).sort(), ["C1", "C2"]);
  assert.ok(r.chat.posts.every((p) => p[1] === said));
  assert.deepEqual(r.said(a.id).map((m) => [m.authorKind, m.text]), [["ember", said]]);
  assert.deepEqual(r.said(b.id).map((m) => [m.authorKind, m.text]), [["ember", said]]);
  await settle();
  assert.equal(r.claude.sessions.length, before, "the agent is not given the copy: it has the message from the chat");
  // One picked, only files: who sent them, and the files.
  await cc(r.hub, chat.id, "Ada", "ada@x.com", "", [{ name: "a.png", path: "/x/a.png", size: 3 }], [b.id]);
  assert.deepEqual(r.chat.posts.at(-1), [{ channel: "C2", threadTs: "1700.000200" }, tr(stationLang(), "station.cc.said", { who: "Ada" })]);
  assert.deepEqual(r.chat.files.at(-1), ["a.png"]);
  await r.close();
});

test("copying a message: the one who wrote it is mentioned as their account there, found by their email; their name where none is", async () => {
  const r = new Rig();
  const [key, chat] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const there = r.store.openThread("slack:T1", "C1", "1700.000100", null, "ada");
  r.store.joinThread(there.id, key, "cl");
  r.chat.people.set("ada@x.com", "UADA");
  await cc(r.hub, chat.id, "Ada Lovelace", "Ada@X.com", "hi", [], [there.id]);
  assert.equal(r.chat.lastText(), ccText("<@UADA>", "hi"));
  assert.deepEqual(r.said(there.id).map((m) => m.text), [ccText("<@UADA>", "hi")]);
  await cc(r.hub, chat.id, "Bo", "bo@x.com", "hi", [], [there.id]);
  assert.equal(r.chat.lastText(), ccText("Bo", "hi"));
  await r.close();
});

test("a copy that did not go is said in the chat", async () => {
  const r = new Rig();
  const [key, chat] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const there = r.store.openThread("slack:T1", "C1", "1700.000100", null, "ada");
  r.store.joinThread(there.id, key, "cl");
  Object.assign(r.chat, { post: async () => { throw new Error("not_in_channel"); } });
  await cc(r.hub, chat.id, "Ada", "ada@x.com", "hi", [], [there.id]);
  assert.deepEqual(r.said(there.id), []);
  const note = r.said(chat.id).at(-1)!;
  assert.deepEqual([note.authorKind, note.text], ["ember", tr(stationLang(), "station.cc.failed", { place: "Slack", error: "not_in_channel" })]);
  await r.close();
});

test("the pages: a chat says where it can be copied, and a message sent with cc is copied to those it names", async () => {
  const data = mkdtempSync(join(tmpdir(), "cc-"));
  const config = hubConfig({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], connects: [{ id: "cl", bind: { runtime: "claude" } }] }, data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const slack = new FakeChat("UBOT");
  const hub = new Hub({
    config: () => config, store, chats: (id) => (id === "cl" ? slack : undefined), drivers: [new FakeDriver("claude")],
    mcpUrl: "http://127.0.0.1:1/mcp", internal: new InternalChat(), runners: () => [],
  });
  const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
  hub.setJobs(jobs);
  const readers = new Readers(data, 1);
  readers.processes = () => hub.processes();
  const admin = new Admin(readers, { store, agents: { hub, jobs } as any });
  const viewer = { sub: "u", email: "a@x", name: "Ada", role: "member", workspace: "w", device: "d" };
  const ask = async (method: string, path: string, body?: unknown) => {
    const r: Request = { method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "en" };
    const a = await admin.handle(r);
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  try {
    const [, made] = await ask("POST", "/sessions", { runtime: "claude" });
    const id = made.thread.id;
    assert.equal((await ask("GET", `/threads/${id}`))[1].cc, undefined, "linked to no thread: none");
    const there = store.openThread("slack:T1", "C1", "1700.000100", null, "ada");
    store.joinThread(there.id, made.key, "cl");
    assert.deepEqual((await ask("GET", `/threads/${id}`))[1].cc, [{ thread: there.id, surface: "slack:T1", channel: "C1", threadTs: "1700.000100", channelName: null }]);
    // Without cc nothing is copied; with it, after the answer.
    assert.equal((await ask("POST", `/threads/${id}/messages`, { text: "just here" }))[0], 200);
    await settle();
    assert.deepEqual(slack.posts, []);
    assert.equal((await ask("POST", `/threads/${id}/messages`, { text: "and there", cc: [there.id] }))[0], 200);
    while (slack.posts.length === 0) await settle();
    assert.deepEqual(slack.posts, [[{ channel: "C1", threadTs: "1700.000100" }, ccText("Ada", "and there")]]);
    assert.deepEqual(store.messagesBefore(id, null, 10).filter((m) => m.authorKind === "person").map((m) => m.text), ["just here", "and there"]);
  } finally {
    await hub.shutdown();
    await jobs.shutdown();
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
