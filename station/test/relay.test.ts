// A chat relayed to a channel: the places a connect's bot is in, the conversation the station starts
// there, the agent going on in it, and Slack's side of it against Slack's stand-in (test/slack-fake.ts).
import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import type { Place, ThreadRef } from "../src/sessions/chat.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { newSession, say as sayIn } from "../src/sessions/lifecycle.ts";
import { mentioned, relay, relayPeople, relayPlaces } from "../src/sessions/relay.ts";
import { MEMBERS_MS } from "../src/connects/surface.ts";
import { PEOPLE_MS, SlackSurface } from "../src/slack/surface.ts";
import { SlackClient } from "../src/slack/web.ts";
import { chatTools } from "../src/tools/chat.ts";
import { Readers } from "../src/read/pool.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { Rig, message, settle, testClock, type Setup } from "./hub-fakes.ts";
import { FakeSlack } from "./slack-fake.ts";

/// Who relays the chats here.
const ADA = { name: "Ada", email: "ada@x.com" };

/// A rig whose Claude connect's bot is in #cue-dev and #design, and starts conversations as Slack would.
function relayRig(setup: Setup = {}) {
  const r = new Rig({ link: true, ...setup });
  const begun: [string, string][] = [];
  const places: Place[] = [
    { id: "C2", name: "design", kind: "channel", private: true },
    { id: "C1", name: "cue-dev", kind: "channel" },
  ];
  Object.assign(r.chat, {
    places: async () => places,
    begin: async (channel: string, text: string) => {
      begun.push([channel, text]);
      return { thread: { channel, threadTs: "1700.000100" }, ts: "1700.000100" };
    },
    threadOf: (link: string) => (link.startsWith("https://acme.slack.com/archives/C1/p1650000000000100") ? { channel: "C1", threadTs: "1650000000.000100" } : null),
    permalink: (t: ThreadRef) => `https://acme.slack.com/archives/${t.channel}/p${t.threadTs.replace(".", "")}`,
  });
  return { r, begun };
}

test("a chat's places: the connects that can start a conversation, each bot's channels by name", async () => {
  const { r } = relayRig();
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const connects = await relayPlaces(r.hub, thread);
  assert.deepEqual(connects, [
    {
      id: "cl", kind: "slack", name: "ember", team: null, botImage: null, preferred: true,
      places: [{ id: "C1", name: "cue-dev", kind: "channel" }, { id: "C2", name: "design", kind: "channel", private: true }],
    },
  ], "the connects whose surface cannot start one (gpt, team here) are not offered");
  // One whose places cannot be read says why, the rest still offered.
  Object.assign(r.gptChat, { places: async () => { throw new Error("missing_scope"); }, begin: async () => { throw new Error("no"); } });
  const again = await relayPlaces(r.hub, thread);
  assert.deepEqual(again.map((c) => [c.id, c.places.length, c.error ?? null]), [["cl", 2, null], ["gpt", 0, "missing_scope"]]);
  await r.close();
});

test("a chat's places: every bot, the one running what the chat's agent runs preferred", async () => {
  const { r } = relayRig();
  const preferred = async (thread: Parameters<typeof relayPlaces>[1]) => (await relayPlaces(r.hub, thread)).filter((c) => c.preferred).map((c) => c.id);
  Object.assign(r.gptChat, { places: async () => [{ id: "C1", name: "cue-dev", kind: "channel" }], begin: async (channel: string) => ({ thread: { channel, threadTs: "1700.000200" }, ts: "1700.000200" }) });
  const [, claude] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const [, codex] = newSession(r.hub, { runtime: "codex", createdBy: "ada@x.com" });
  assert.deepEqual((await relayPlaces(r.hub, claude)).map((c) => c.id), ["cl", "gpt"]);
  assert.deepEqual(await preferred(claude), ["cl"]);
  assert.deepEqual(await preferred(codex), ["gpt"]);
  // Of the bots running its runtime, the one bound to the profile it runs on (cc).
  r.config.connects.find((c) => c.id === "gpt")!.bind = { runtime: "claude", profile: "cc" };
  assert.deepEqual(await preferred(claude), ["gpt"]);
  // Another bot can be picked all the same.
  const done = await relay(r.hub, claude, ADA, { connect: "gpt", channel: "C1" }, "");
  assert.equal(done.place, "#cue-dev");
  await r.close();
});

test("a chat's places: those relayed to before come first, the latest first, the rest by name", async () => {
  const time = testClock();
  const { r } = relayRig({ clock: time.clock });
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const order = async () => (await relayPlaces(r.hub, thread))[0]!.places.map((p) => [p.id, p.used ?? null]);
  assert.deepEqual(await order(), [["C1", null], ["C2", null]]);
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C2" }, "");
  const first = r.store.now();
  assert.deepEqual(await order(), [["C2", first], ["C1", null]]);
  await time.adjust(1000);
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "");
  assert.deepEqual(await order(), [["C1", first + 1000], ["C2", first]]);
  await r.close();
});

test("relaying starts the conversation there, makes it the agent's, says so where the chat came from and tells the agent", async () => {
  const { r, begun } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  // Each turn ends with a state, as an agent's does (else it is nudged).
  const end = async () => {
    await r.call(key, "chat_state", { kind: "all_done", done: "answered" });
    r.claude.last().complete();
    await settle();
  };
  sayIn(r.hub, thread.id, "ada@x.com", "plan the relay feature");
  await settle();
  await end();
  const done = await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, " @Bo could you look? ");
  assert.deepEqual(done, { thread: r.thread("C1", "1700.000100").id, to: "C1/1700.000100", place: "#cue-dev", link: "https://acme.slack.com/archives/C1/p1700000100" });
  // The station's first message there: who, which chat (linked), the note.
  assert.equal(begun.length, 1);
  assert.equal(begun[0]![0], "C1");
  assert.ok(begun[0]![1].includes("Ada") && begun[0]![1].includes(`(https://ember.test/o/ws/st/${key.replaceAll(":", "%3A")})`) && begun[0]![1].endsWith("\n\n@Bo could you look?"), begun[0]![1]);
  // The new thread is the session's, through the connect; its first message is the station's.
  const there = r.thread("C1", "1700.000100");
  assert.deepEqual(r.store.threadSessions(there.id).map((m) => [m.session, m.connect]), [[key, "cl"]]);
  assert.deepEqual(r.said(there.id).map((m) => [m.authorKind, m.ts]), [["ember", "1700.000100"]]);
  // Said in the chat it came from, with a link there.
  const back = r.said(thread.id).at(-1)!;
  assert.equal(back.authorKind, "ember");
  assert.ok(back.text.startsWith("↗ ") && back.text.includes("Ada") && back.text.includes("[#cue-dev](https://acme.slack.com/archives/C1/p1700000100)"), back.text);
  // The agent is told, and posts there with chat_post.
  await settle();
  const told = r.claude.last().prompts.at(-1)!;
  assert.ok(told.includes("C1/1700.000100") && told.includes("chat_post") && told.includes("@Bo could you look?"), told);
  assert.ok(told.includes("first message"), told);
  // Its first post there goes into the station's first message, which people see without opening the thread.
  const posts = r.chat.posts.length;
  assert.equal(
    await r.call(key, "chat_post", { to: "C1/1700.000100", text: "Context: …" }),
    "Posted to C1/1700.000100 (added to the station's first message there, ts 1700.000100).",
  );
  assert.equal(r.chat.posts.length, posts, "not a reply");
  assert.deepEqual(r.chat.edits, [[{ channel: "C1", threadTs: "1700.000100" }, "1700.000100", `${begun[0]![1]}\n\nContext: …`]]);
  assert.deepEqual(r.said(there.id).map((m) => [m.authorKind, m.text]), [["ember", `${begun[0]![1]}\n\nContext: …`]]);
  // The next is a reply.
  assert.equal(await r.call(key, "chat_post", { to: "C1/1700.000100", text: "More" }), "Posted to C1/1700.000100.");
  assert.deepEqual(r.chat.posts.at(-1), [{ channel: "C1", threadTs: "1700.000100" }, "More"]);
  assert.equal(r.chat.edits.length, 1);
  await end();
  // A reply there reaches the agent, without mentioning it; the chat it came from still takes messages.
  await r.accept(message({ channel: "C1", threadTs: "1700.000100", ts: "1700.000200", user: "UBO", text: "looks fine", addressed: false }));
  await settle();
  assert.ok(r.claude.last().prompts.at(-1)!.includes("looks fine"));
  await end();
  sayIn(r.hub, thread.id, "ada@x.com", "and here too");
  await settle();
  assert.ok(r.claude.last().prompts.at(-1)!.includes("and here too"));
  await r.close();
});

test("the bot mentioned in a thread a chat was relayed to brings back that chat's agent, never a second one", async () => {
  const { r } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "");
  await settle();
  await r.call(key, "chat_state", { kind: "all_done", done: "relayed" });
  r.claude.last().complete();
  await settle();
  const before = r.store.sessionKeys().length;
  const there = r.thread("C1", "1700.000100");
  await r.accept(message({ channel: "C1", threadTs: "1700.000100", ts: "1700.000200", user: "UBO", text: "<@UBOT> can we open the MR now?", addressed: true }));
  await settle();
  assert.equal(r.store.sessionKeys().length, before, "no session of the connect's own is made for the thread");
  assert.deepEqual(r.store.threadSessions(there.id).map((m) => [m.session, m.connect]), [[key, "cl"]]);
  assert.ok(r.claude.last().prompts.at(-1)!.includes("can we open the MR now?"));
  // Left, the mention brings it back.
  await r.call(key, "chat_state", { kind: "all_done", done: "answered" });
  r.claude.last().complete();
  await settle();
  r.store.leaveThread(there.id, key);
  await r.accept(message({ channel: "C1", threadTs: "1700.000100", ts: "1700.000300", user: "UBO", text: "<@UBOT> and the build?", addressed: true }));
  await settle();
  assert.equal(r.store.sessionKeys().length, before);
  assert.ok(r.claude.last().prompts.at(-1)!.includes("and the build?"));
  await r.close();
});

test("in a thread with two agents of the same bot, the one that left stays out when the bot is mentioned", async () => {
  const { r } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "");
  await settle();
  await r.call(key, "chat_state", { kind: "all_done", done: "relayed" });
  r.claude.last().complete();
  await settle();
  // As stations before the fix did: the bot mentioned there made a session of the connect's own for the thread.
  const there = r.thread("C1", "1700.000100");
  const own = "cl:C1:1700.000100";
  r.hub.createSession(r.hub.config(), own, r.config.connects.find((c) => c.id === "cl")!, "thread", null, null, "slack:cl:UBO");
  r.store.joinThread(there.id, own, "cl");
  r.store.leaveThread(there.id, own);
  const before = r.store.sessionKeys().length;
  await r.accept(message({ channel: "C1", threadTs: "1700.000100", ts: "1700.000200", user: "UBO", text: "<@UBOT> status?", addressed: true }));
  await settle();
  assert.equal(r.store.sessionKeys().length, before);
  assert.deepEqual(r.store.threadSessions(there.id).map((m) => [m.session, m.leftAt === null]).sort(), [[key, true], [own, false]].sort());
  assert.ok(r.claude.last().prompts.at(-1)!.includes("status?"));
  await r.close();
});

test("a relayed chat's first post is a reply where it would not fit in the station's first message, carries files, or is not the relaying agent's", async () => {
  const { r } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "");
  await settle();
  const long = "x".repeat(3500);
  assert.equal(await r.call(key, "chat_post", { to: "C1/1700.000100", text: long }), "Posted to C1/1700.000100.");
  assert.equal(r.chat.lastText(), long);
  assert.equal(r.chat.edits.length, 0);
  assert.equal(r.hub.openings.size, 0, "only the first post is taken");
  // Another agent's post there is its own.
  r.hub.openings.set(r.thread("C1", "1700.000100").id, { session: "someone-else", ts: "1700.000100" });
  await r.call(key, "chat_post", { to: "C1/1700.000100", text: "short" });
  assert.equal(r.chat.lastText(), "short");
  assert.equal(r.chat.edits.length, 0);
  await r.close();
});

test("the station's first message there mentions who relayed it, where the platform has an account with their email", async () => {
  const { r, begun } = relayRig();
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  r.chat.people.set("ada@x.com", "UADA");
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "");
  assert.equal(begun[0]![1], tr(stationLang(), "station.relay.opening", { who: "<@UADA>", chat: begun[0]![1].match(/\[.*\]\(.*\)/)![0] }));
  // The chat it came from names them as still.fail does.
  assert.ok(r.said(thread.id).at(-1)!.text.includes("Ada"));
  // One the platform has no account for is named.
  r.chat.people.clear();
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C2" }, "");
  assert.ok(begun[1]![1].includes("Ada") && !begun[1]![1].includes("<@"), begun[1]![1]);
  await r.close();
});

test("a note's @names of the people there are mentioned as the platform mentions them", async () => {
  const people = [{ id: "UANN", name: "Ann" }, { id: "UANNA", name: "Anna Li" }, { id: "UZS", name: "张三" }];
  const at = (id: string) => `<@${id}>`;
  assert.equal(mentioned("@Anna Li and @Ann, look", people, at), "<@UANNA> and <@UANN>, look", "the longest name first");
  assert.equal(mentioned("@张三帮看下", people, at), "<@UZS>帮看下", "a name in a script without spaces runs on into the words");
  assert.equal(mentioned("@Annie, @Bo, mail x@Ann.c", people, at), "@Annie, @Bo, mail x@Ann.c", "one going on into more of a word is not theirs; nobody's left as written");
  assert.equal(mentioned("@Ann", [], at), "@Ann");
  assert.equal(mentioned("@Peng Xiao look", [{ id: "UPX", name: "pengxiao", aka: "Peng Xiao" }], at), "<@UPX> look", "by their other name too");
  // Relayed: the station's first message there mentions them; who is there is asked of the platform only for an @.
  const { r, begun } = relayRig();
  const asked: string[] = [];
  Object.assign(r.chat, { peopleIn: async (channel: string) => (asked.push(channel), people) });
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  assert.deepEqual(await relayPeople(r.hub, thread, { connect: "cl", channel: "C1" }), people);
  assert.deepEqual(await relayPeople(r.hub, thread, { link: "https://acme.slack.com/archives/C1/p1650000000000100" }), people);
  await assert.rejects(relayPeople(r.hub, thread, { connect: "cl", channel: "C9" }), /not in C9/);
  assert.deepEqual(asked, ["C1", "C1"]);
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C2" }, "no one");
  assert.deepEqual(asked, ["C1", "C1"], "not asked without an @");
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C1" }, "@张三 could you look?");
  assert.deepEqual(asked, ["C1", "C1", "C1"]);
  assert.ok(begun[1]![1].endsWith("\n\n<@UZS> could you look?"), begun[1]![1]);
  // Where they cannot be read, the note goes as written.
  Object.assign(r.chat, { peopleIn: async () => { throw new Error("missing_scope"); } });
  await relay(r.hub, thread, ADA, { connect: "cl", channel: "C2" }, "@张三 look");
  assert.ok(begun[2]![1].endsWith("\n\n@张三 look"), begun[2]![1]);
  await r.close();
});

test("relaying is refused where the bot is not, through a connect that cannot, and for a chat with no agent", async () => {
  const { r, begun } = relayRig();
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  await assert.rejects(relay(r.hub, thread, ADA, { connect: "cl", channel: "C9" }, ""), /not in C9/);
  await assert.rejects(relay(r.hub, thread, ADA, { connect: "gpt", channel: "C1" }, ""), /cannot take this chat/);
  const lone = r.store.openThread("ember", "CHAT", "1.5", null, "ada@x.com");
  await assert.rejects(relay(r.hub, lone, ADA, { connect: "cl", channel: "C1" }, ""), /no agent/);
  assert.equal(begun.length, 0, "nothing was started");
  await assert.rejects(relay(r.hub, thread, ADA, { link: "https://other.slack.com/archives/C1/p1650000000000100" }, ""), /not a link/);
  // A thread another chat's agent is in stays that one's.
  const other = r.store.openThread("slack:T1", "C1", "1650000000.000100", null, null);
  const [elsewhere] = newSession(r.hub, { runtime: "claude", createdBy: "bo@x.com" });
  r.store.joinThread(other.id, elsewhere, "cl");
  await assert.rejects(relay(r.hub, thread, ADA, { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, ""), /another chat's agent/);
  assert.equal(r.chat.posts.length, 0, "nothing was said there");
  await r.close();
});

test("relaying to a Slack thread by a message's link joins that thread: the station says so in it, and the agent reads it first", async () => {
  const { r, begun } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const done = await relay(r.hub, thread, ADA, { link: "https://acme.slack.com/archives/C1/p1650000000000100?thread_ts=1650000000.000100&cid=C1" }, "");
  assert.equal(begun.length, 0, "no new thread");
  assert.equal(done.to, "C1/1650000000.000100");
  assert.deepEqual(r.chat.posts.map(([at]) => at), [{ channel: "C1", threadTs: "1650000000.000100" }]);
  assert.deepEqual(r.store.threadSessions(r.thread("C1", "1650000000.000100").id).map((m) => m.session), [key]);
  const back = r.said(thread.id).at(-1)!.text;
  assert.ok(back.includes(`[${tr(stationLang(), "station.relay.threadIn", { place: "#cue-dev" })}](https://acme.slack.com/archives/C1/p1650000000000100)`), back);
  await settle();
  assert.ok(r.claude.last().prompts.at(-1)!.includes("conversations.replies"), "told to read what was said there");
  await assert.rejects(relay(r.hub, thread, ADA, { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, ""), /in that thread already/);
  await r.close();
});

test("a relay's first post waits for old edits without scanning the thread on the station", async () => {
  const { r } = relayRig(), release = Promise.withResolvers<void>();
  let post: Promise<string> | undefined;
  try {
    const [key, source] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    const old = r.store.openThread("slack:T1", "C1", "1650000000.000100", null, null);
    const db = r.store.db;
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other',?)");
    for (let n = 1; n <= 150; n++) put.run(old.id, n, n + 10000, n);
    installLegacyEdits(db);
    addClientColumn(db);
    const done = await relay(r.hub, source, ADA, { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, "");
    await settle();
    const opening = r.hub.openings.get(old.id)!;
    const original = r.store.messageAt(old.id, opening.ts)!.text;
    let started = 0;
    r.hub.prepareLegacyEdits = async () => {
      started++;
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    post = r.call(key, "chat_post", { to: done.to, text: "Context" });
    void post.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(started, 1, "old edits are prepared off the station thread");
    assert.equal(r.chat.edits.length, 0, "nothing is changed on Slack before preparation finishes");
    release.resolve();
    assert.match(await post, /added to the station's first message/);
    assert.equal(r.chat.edits[0]![2], `${original}\n\nContext`);
    assert.equal(r.store.messageAt(old.id, opening.ts)!.text, `${original}\n\nContext`);
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

async function relayIntoOldThread(disk = false) {
  const { r } = relayRig();
  if (disk) {
    await r.hub.shutdown();
    r.store.close();
    r.store = Store.open(join(r.dir, "stillfail.db"));
    r.hub = r.newHub({ chats: (id) => id === "cl" ? r.chat : undefined, link: true });
  }
  const [key, source] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const old = r.store.openThread("slack:T1", "C1", "1650000000.000100", null, null);
  const db = r.store.db;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other',?)");
  for (let n = 1; n <= 150; n++) put.run(old.id, n, n + 10000, n);
  installLegacyEdits(db);
  addClientColumn(db);
  const done = await relay(r.hub, source, ADA, { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, "");
  await settle();
  return { r, key, old, db, done, opening: r.hub.openings.get(old.id)! };
}

test("a relay's first post prepares old edits through the background worker", async () => {
  const { r, key, old, db, done, opening } = await relayIntoOldThread(true);
  const readers = new Readers(r.dir, 1, undefined, 1);
  try {
    let preparations = 0;
    r.hub.prepareLegacyEdits = (signal) => { preparations++; return readers.prepareLegacyEdits(signal); };
    assert.match(await r.call(key, "chat_post", { to: done.to, text: "Context" }), /added to the station's first message/);
    assert.equal(preparations, 1);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 1);
    assert.ok(r.store.messageAt(old.id, opening.ts)!.text.endsWith("\n\nContext"));
  } finally { readers.close(); await r.close(); }
});

for (const failed of [false, true]) {
  test(`a second relay post is a reply while the first ${failed ? "fails preparation" : "waits for preparation"}`, async () => {
    const { r, key, db, done } = await relayIntoOldThread();
    const started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
    let first: Promise<string> | undefined;
    try {
      r.hub.prepareLegacyEdits = async () => {
        started.resolve();
        await release.promise;
        if (failed) throw new Error("synthetic preparation failure");
        while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
        while (legacyEditDrain(db)) { /* reconcile writes */ }
      };
      first = r.call(key, "chat_post", { to: done.to, text: "First" });
      void first.catch(() => {});
      await started.promise;
      assert.match(await r.call(key, "chat_post", { to: done.to, text: "Second" }), /Posted to C1\/1650000000\.000100\./);
      assert.equal(r.chat.edits.length, 0);
      release.resolve();
      if (failed) {
        await assert.rejects(first, /synthetic preparation failure/);
        assert.match(await r.call(key, "chat_post", { to: done.to, text: "Retry" }), /Posted to C1\/1650000000\.000100\./);
        assert.equal(r.chat.edits.length, 0, "the failed first post cannot reclaim the opening after another post");
      } else {
        assert.match(await first, /added to the station's first message/);
        assert.equal(r.chat.edits.length, 1);
      }
    } finally { release.resolve(); await Promise.allSettled(first ? [first] : []); await r.close(); }
  });
}

test("a relay's first post rechecks archiving after old edits are prepared", async () => {
  const { r, key, old, db, done } = await relayIntoOldThread(), release = Promise.withResolvers<void>();
  let post: Promise<string> | undefined;
  try {
    r.hub.prepareLegacyEdits = async () => {
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    post = r.call(key, "chat_post", { to: done.to, text: "Context" });
    void post.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    r.store.setThreadHidden(old.id, true, "manual");
    release.resolve();
    await assert.rejects(post, /archived/);
    assert.equal(r.chat.edits.length, 0);
    r.store.setThreadHidden(old.id, false, "manual");
    assert.match(await r.call(key, "chat_post", { to: done.to, text: "Context" }), /added to the station's first message/);
    assert.equal(r.chat.edits.length, 1);
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

test("a relay's waiting question is not posted if its turn ends during old edit preparation", async () => {
  const { r, key, db, done } = await relayIntoOldThread();
  const started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  let post: Promise<string> | undefined;
  try {
    const actor = r.hub.actors.get(key)!;
    const turn = actor.currentTurnId();
    assert.ok(turn, "the relay has started an agent turn");
    r.hub.statePendingCard = async () => null;
    r.hub.prepareLegacyEdits = async () => {
      started.resolve();
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    post = r.call(key, "chat_post", { to: done.to, text: "May I continue?", kind: "need_human", need: "permission" });
    void post.catch(() => {});
    await started.promise;
    r.claude.last().end({ kind: "aborted" });
    await settle();
    r.hub.notify(key, "a background job ended");
    await settle();
    assert.notEqual(actor.currentTurnId(), turn, "the original turn ended while waiting");
    release.resolve();
    const result = await Promise.allSettled([post]);
    assert.equal(r.chat.edits.length, 0, "the ended turn did not change the platform message");
    assert.equal(r.chat.posts.length, 1, "the ended turn did not post a reply");
    assert.equal(result[0]!.status, "rejected");
    if (result[0]!.status === "rejected") assert.match(String(result[0]!.reason), /turn ended.*no message was posted/);
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

for (const changed of [false, true]) {
  test(`a relay question's turn ends while the platform ${changed ? "changes" : "declines"} its opening`, async () => {
    const { r, key, old, db, done, opening } = await relayIntoOldThread();
    const started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
    let post: Promise<string> | undefined;
    try {
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
      const actor = r.hub.actors.get(key)!, turn = actor.currentTurnId();
      assert.ok(turn);
      r.hub.statePendingCard = async () => null;
      const edit = r.chat.edit.bind(r.chat);
      r.chat.edit = async (...args) => {
        started.resolve();
        await release.promise;
        return changed ? edit(...args) : false;
      };
      post = r.call(key, "chat_post", { to: done.to, text: "May I continue?", kind: "need_human", need: "permission" });
      void post.catch(() => {});
      await started.promise;
      r.claude.last().end({ kind: "aborted" });
      await settle();
      r.hub.notify(key, "a background job ended");
      await settle();
      assert.notEqual(actor.currentTurnId(), turn);
      release.resolve();
      if (changed) {
        assert.match(await post, /turn ended before its state was recorded/);
        assert.equal(r.chat.edits.length, 1);
        assert.ok(r.store.messageAt(old.id, opening.ts)!.text.endsWith("\n\nMay I continue?"));
      } else {
        await assert.rejects(post, /turn ended.*no message was posted/);
        assert.equal(r.chat.edits.length, 0);
      }
      assert.equal(r.chat.posts.length, 1, "no additional reply was posted");
    } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
  });
}

test("handover cancels a relay's first post before old edit preparation finishes", async () => {
  const { r, key, db, done } = await relayIntoOldThread(), release = Promise.withResolvers<void>();
  let post: Promise<string> | undefined;
  try {
    r.hub.prepareLegacyEdits = async () => {
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    post = r.call(key, "chat_post", { to: done.to, text: "Context" });
    void post.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    await r.hub.handOver();
    release.resolve();
    await assert.rejects(post, { name: "AbortError" });
    assert.equal(r.chat.edits.length, 0);
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

test("a relay post already accepted continues if its tool connection goes away", async () => {
  const { r, key, db, done } = await relayIntoOldThread(), release = Promise.withResolvers<void>();
  const controller = new AbortController();
  let post: Promise<string> | undefined;
  try {
    r.hub.prepareLegacyEdits = async () => {
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    const tool = chatTools(r.hub).find((t) => t.name === "chat_post")!;
    post = tool.run(key, { to: done.to, text: "Context" }, controller.signal);
    void post.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    controller.abort();
    release.resolve();
    assert.match(await post, /added to the station's first message/);
    assert.equal(r.chat.edits.length, 1);
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

test("a relay's first post is recorded after the platform changed it, even through handover", async () => {
  const { r, key, old, db, done, opening } = await relayIntoOldThread(), release = Promise.withResolvers<void>();
  let post: Promise<string> | undefined;
  try {
    while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
    while (legacyEditDrain(db)) { /* reconcile writes */ }
    const edit = r.chat.edit.bind(r.chat);
    r.chat.edit = async (...args) => {
      const changed = await edit(...args);
      const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other',?)");
      const first = Number(db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread=?").get(old.id)!.n) + 1;
      for (let n = first; n < first + 65; n++) put.run(old.id, n, n + 10000, n);
      return changed;
    };
    let started = 0;
    r.hub.prepareLegacyEdits = async (signal) => {
      assert.equal(signal, undefined, "the already visible change must still be recorded");
      started++;
      await release.promise;
      while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
      while (legacyEditDrain(db)) { /* reconcile writes */ }
    };
    post = r.call(key, "chat_post", { to: done.to, text: "Context" });
    void post.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(started, 1);
    assert.equal(r.chat.edits.length, 1);
    await r.hub.handOver();
    release.resolve();
    assert.match(await post, /added to the station's first message/);
    assert.equal(r.chat.edits.length, 1, "the platform edit is not repeated");
    assert.ok(r.store.messageAt(old.id, opening.ts)!.text.endsWith("\n\nContext"));
  } finally { release.resolve(); await Promise.allSettled(post ? [post] : []); await r.close(); }
});

test("a failed recording after the platform edit says the message was already updated", async () => {
  const { r, key, old, db, done } = await relayIntoOldThread();
  try {
    while (!legacyEditStep(db).ready) { /* bounded worker steps */ }
    while (legacyEditDrain(db)) { /* reconcile writes */ }
    const edit = r.chat.edit.bind(r.chat);
    r.chat.edit = async (...args) => {
      const changed = await edit(...args);
      const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other',?)");
      const first = Number(db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread=?").get(old.id)!.n) + 1;
      for (let n = first; n < first + 65; n++) put.run(old.id, n, n + 10000, n);
      return changed;
    };
    r.hub.prepareLegacyEdits = async () => { throw new Error("synthetic preparation failure"); };
    await assert.rejects(r.call(key, "chat_post", { to: done.to, text: "Context" }), /updated on the platform, but could not be recorded here: synthetic preparation failure/);
    assert.equal(r.chat.edits.length, 1);
    assert.equal(r.chat.posts.length, 1, "no extra reply was posted");
  } finally { await r.close(); }
});

test("Slack: the channels the bot is in, page by page; a conversation begins with a message, what is too long going on in its thread", async () => {
  const fake = await FakeSlack.start();
  try {
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base) });
    fake.answer("users.conversations", (seen: { params: Record<string, string> }) =>
      seen.params.cursor === "n2"
        ? { ok: true, channels: [{ id: "C3", name: "ops", is_private: true }], response_metadata: { next_cursor: "" } }
        : { ok: true, channels: [{ id: "C1", name: "cue-dev" }, { id: "" }], response_metadata: { next_cursor: "n2" } },
    );
    assert.deepEqual(await surface.places(), [{ id: "C1", name: "cue-dev", kind: "channel" }, { id: "C3", name: "ops", kind: "channel", private: true }]);
    assert.deepEqual(fake.calls("users.conversations").map((c) => [c.params.types, c.params.exclude_archived, c.params.cursor ?? null]), [
      ["public_channel,private_channel", "true", null],
      ["public_channel,private_channel", "true", "n2"],
    ]);
    let n = 0;
    fake.answer("chat.postMessage", () => ({ ok: true, ts: `1800.00000${++n}` }));
    const long = `${"a".repeat(3000)}\n\n${"b".repeat(3000)}`;
    assert.deepEqual(await surface.begin("C1", long), { thread: { channel: "C1", threadTs: "1800.000001" }, ts: "1800.000001" });
    const posted = fake.calls("chat.postMessage");
    assert.deepEqual(posted.map((p) => [p.params.channel, p.params.thread_ts ?? null, p.params.text?.[0]]), [["C1", null, "a"], ["C1", "1800.000001", "b"]]);
    // Its first message changed in place, when what it says fits in one message.
    fake.answer("chat.update", { ok: true });
    assert.equal(await surface.edit({ channel: "C1", threadTs: "1800.000002" }, "1800.000002", "opening\n\nsummary"), true);
    assert.deepEqual(fake.calls("chat.update").map((p) => [p.params.channel, p.params.ts, p.params.text, JSON.parse(p.params.blocks!)[0].text]), [["C1", "1800.000002", "opening\n\nsummary", "opening\n\nsummary"]]);
    assert.equal(await surface.edit({ channel: "C1", threadTs: "1800.000002" }, "1800.000002", long), false);
    assert.equal(fake.calls("chat.update").length, 1);
    assert.equal(surface.permalink({ channel: "C1", threadTs: "1800.000001" }), null, "not before its workspace is known");
    assert.equal(surface.threadOf("https://acme.slack.com/archives/C1/p1800000001000100"), null);
    fake.answer("auth.test", { ok: true, url: "https://acme.slack.com/", team: "Acme", team_id: "T1", user_id: "UBOT" });
    await surface.refreshIdentity();
    assert.equal(surface.permalink({ channel: "C1", threadTs: "1800.000001" }), "https://acme.slack.com/archives/C1/p1800000001");
    // A message's own link, a reply's (the thread in thread_ts), another workspace's, not a message.
    assert.deepEqual(surface.threadOf("https://acme.slack.com/archives/C1/p1800000001000100"), { channel: "C1", threadTs: "1800000001.000100" });
    assert.deepEqual(surface.threadOf(" https://acme.slack.com/archives/C1/p1800000009000200?thread_ts=1800000001.000100&cid=C1 "), { channel: "C1", threadTs: "1800000001.000100" });
    assert.equal(surface.threadOf("https://other.slack.com/archives/C1/p1800000001000100"), null);
    assert.equal(surface.threadOf("https://acme.slack.com/client/T1/C1"), null);
    assert.equal(surface.threadOf("not a link"), null);
  } finally {
    await fake.close();
  }
});

test("Slack: the people in a channel, named as users.list names them, bots and deactivated accounts left out; kept a while", async () => {
  const fake = await FakeSlack.start();
  const time = testClock();
  try {
    const surface = new SlackSurface({ appToken: "xapp-1", botToken: "xoxb-1", client: new SlackClient(fake.base), clock: time.clock });
    fake.answer("conversations.members", (seen: { params: Record<string, string> }) =>
      seen.params.cursor === "m2" ? { ok: true, members: ["UBOT", "UOLD", "UZW"], response_metadata: { next_cursor: "" } } : { ok: true, members: ["UANN", "UBO"], response_metadata: { next_cursor: "m2" } },
    );
    fake.answer("users.list", (seen: { params: Record<string, string> }) =>
      seen.params.cursor === "u2"
        ? { ok: true, members: [{ id: "UBO", real_name: "Bo", profile: { display_name: "", real_name: "Bo" } }, { id: "UBOT", is_bot: true, profile: { real_name: "Bot" } }, { id: "UOLD", deleted: true, profile: { real_name: "Old" } }], response_metadata: { next_cursor: "" } }
        : { ok: true, members: [{ id: "UANN", profile: { display_name: "ann", real_name: "Ann Lee", image_72: "https://img/ann.png" } }, { id: "UZW", profile: { display_name: "zanwei.guo", real_name: "Zanwei.Guo " } }, { id: "UOUT", profile: { real_name: "Not there" } }], response_metadata: { next_cursor: "u2" } },
    );
    assert.deepEqual(await surface.peopleIn("C1"), [
      { id: "UANN", name: "ann", aka: "Ann Lee", picture: "https://img/ann.png" },
      { id: "UBO", name: "Bo" },
      { id: "UZW", name: "zanwei.guo" },
    ]);
    assert.deepEqual(fake.calls("conversations.members").map((c) => [c.params.channel, c.params.cursor ?? null]), [["C1", null], ["C1", "m2"]]);
    const asked = () => [fake.calls("conversations.members").length, fake.calls("users.list").length];
    assert.deepEqual(asked(), [2, 2]);
    // Asked again soon (the note's @, then relaying): nothing asked of Slack.
    assert.equal((await surface.peopleIn("C1")).length, 3);
    assert.deepEqual(asked(), [2, 2]);
    // Who is in the channel, read again after a minute; the workspace's people kept.
    await time.adjust(MEMBERS_MS);
    await surface.peopleIn("C1");
    assert.deepEqual(asked(), [4, 2]);
    // Someone the workspace's people did not have: those read again (once a minute at most).
    fake.answer("conversations.members", { ok: true, members: ["UANN", "UNEW"], response_metadata: { next_cursor: "" } });
    fake.answer("users.list", { ok: true, members: [{ id: "UANN", profile: { display_name: "ann" } }, { id: "UNEW", profile: { real_name: "New" } }], response_metadata: { next_cursor: "" } });
    await time.adjust(MEMBERS_MS);
    assert.deepEqual((await surface.peopleIn("C1")).map((p) => p.id), ["UANN", "UNEW"]);
    assert.deepEqual(asked(), [5, 3]);
    // And after PEOPLE_MS in any case.
    await time.adjust(PEOPLE_MS);
    await surface.peopleIn("C1");
    assert.deepEqual(asked(), [6, 4]);
  } finally {
    await fake.close();
  }
});
