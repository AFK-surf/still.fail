// A chat relayed to a channel (docs/relay.md): the places a connect's bot is in, the conversation the station starts
// there, the agent going on in it, and Slack's side of it against Slack's stand-in (test/slack-fake.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Place, ThreadRef } from "../src/sessions/chat.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { newSession, say as sayIn } from "../src/sessions/lifecycle.ts";
import { relay, relayPlaces } from "../src/sessions/relay.ts";
import { SlackSurface } from "../src/slack/surface.ts";
import { SlackClient } from "../src/slack/web.ts";
import { Rig, message, settle, testClock, type Setup } from "./hub-fakes.ts";
import { FakeSlack } from "./slack-fake.ts";

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
  const done = await relay(r.hub, claude, "Ada", { connect: "gpt", channel: "C1" }, "");
  assert.equal(done.place, "#cue-dev");
  await r.close();
});

test("a chat's places: those relayed to before come first, the latest first, the rest by name", async () => {
  const time = testClock();
  const { r } = relayRig({ clock: time.clock });
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const order = async () => (await relayPlaces(r.hub, thread))[0]!.places.map((p) => [p.id, p.used ?? null]);
  assert.deepEqual(await order(), [["C1", null], ["C2", null]]);
  await relay(r.hub, thread, "Ada", { connect: "cl", channel: "C2" }, "");
  const first = r.store.now();
  assert.deepEqual(await order(), [["C2", first], ["C1", null]]);
  await time.adjust(1000);
  await relay(r.hub, thread, "Ada", { connect: "cl", channel: "C1" }, "");
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
  const done = await relay(r.hub, thread, "Ada", { connect: "cl", channel: "C1" }, " @Bo could you look? ");
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
  assert.equal(await r.call(key, "chat_post", { to: "C1/1700.000100", text: "Context: …" }), "Posted to C1/1700.000100.");
  assert.deepEqual(r.chat.posts.at(-1), [{ channel: "C1", threadTs: "1700.000100" }, "Context: …"]);
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

test("relaying is refused where the bot is not, through a connect that cannot, and for a chat with no agent", async () => {
  const { r, begun } = relayRig();
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  await assert.rejects(relay(r.hub, thread, "Ada", { connect: "cl", channel: "C9" }, ""), /not in C9/);
  await assert.rejects(relay(r.hub, thread, "Ada", { connect: "gpt", channel: "C1" }, ""), /cannot take this chat/);
  const lone = r.store.openThread("ember", "EMBER", "1.5", null, "ada@x.com");
  await assert.rejects(relay(r.hub, lone, "Ada", { connect: "cl", channel: "C1" }, ""), /no agent/);
  assert.equal(begun.length, 0, "nothing was started");
  await assert.rejects(relay(r.hub, thread, "Ada", { link: "https://other.slack.com/archives/C1/p1650000000000100" }, ""), /not a link/);
  // A thread another chat's agent is in stays that one's.
  const other = r.store.openThread("slack:T1", "C1", "1650000000.000100", null, null);
  const [elsewhere] = newSession(r.hub, { runtime: "claude", createdBy: "bo@x.com" });
  r.store.joinThread(other.id, elsewhere, "cl");
  await assert.rejects(relay(r.hub, thread, "Ada", { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, ""), /another chat's agent/);
  assert.equal(r.chat.posts.length, 0, "nothing was said there");
  await r.close();
});

test("relaying to a Slack thread by a message's link joins that thread: the station says so in it, and the agent reads it first", async () => {
  const { r, begun } = relayRig();
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
  const done = await relay(r.hub, thread, "Ada", { link: "https://acme.slack.com/archives/C1/p1650000000000100?thread_ts=1650000000.000100&cid=C1" }, "");
  assert.equal(begun.length, 0, "no new thread");
  assert.equal(done.to, "C1/1650000000.000100");
  assert.deepEqual(r.chat.posts.map(([at]) => at), [{ channel: "C1", threadTs: "1650000000.000100" }]);
  assert.deepEqual(r.store.threadSessions(r.thread("C1", "1650000000.000100").id).map((m) => m.session), [key]);
  const back = r.said(thread.id).at(-1)!.text;
  assert.ok(back.includes(`[${tr(stationLang(), "station.relay.threadIn", { place: "#cue-dev" })}](https://acme.slack.com/archives/C1/p1650000000000100)`), back);
  await settle();
  assert.ok(r.claude.last().prompts.at(-1)!.includes("conversations.replies"), "told to read what was said there");
  await assert.rejects(relay(r.hub, thread, "Ada", { link: "https://acme.slack.com/archives/C1/p1650000000000100" }, ""), /in that thread already/);
  await r.close();
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
