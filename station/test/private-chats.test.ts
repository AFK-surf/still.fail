// Chats private to some people (docs/private-chats.md): a direct message's chat is its people's alone. The hub makes it
// so as the message comes (their emails, as the platform shares them); the pages, the events, search and the agents'
// tools show it to no one else, a manager included; what an agent of it reads and opens stays with them too.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { elsewhere, sessionSeen, threadSeen } from "../src/api/seen.ts";
import { openStore } from "../src/read/store.ts";
import { session, sessions, threads } from "../src/read/sessions.ts";
import { chats } from "../src/read/views.ts";
import { pick } from "../src/search/match.ts";
import { threadDocs } from "../src/search/sources.ts";
import { toEvent } from "../src/slack/surface.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { newSession } from "../src/sessions/lifecycle.ts";
import { opensTo, privateToAll, seesChat, seesMembers } from "../src/store/rows.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

const PX = "pengxiao@cue.surf";
const ZZ = "zz@cue.surf";
const viewerOf = (email: string, role = "member") => ({ sub: email, email, name: email, role, workspace: "w", device: "d" });

test("whom a private chat opens to: its people, and a reader all of whose audience is among them", () => {
  assert.equal(opensTo(null, null), true);
  assert.equal(opensTo(null, [PX]), false);
  assert.equal(opensTo([], [PX]), false);
  assert.equal(opensTo(["PengXiao@Cue.Surf"], [PX]), true);
  assert.equal(opensTo([PX, ZZ], [PX]), false);
  assert.equal(opensTo([PX], [PX, ZZ]), true);
  assert.equal(opensTo([PX], []), false);
  assert.deepEqual(privateToAll([{ ws: null }, { ws: null, privateTo: [PX, ZZ] }, { ws: null, privateTo: [ZZ, "x@y"] }]), [ZZ]);
  assert.equal(privateToAll([{ ws: null }]), null);
  const px = { workspace: "w", email: PX };
  assert.equal(seesChat(px, { ws: null, privateTo: [PX] }), true);
  assert.equal(seesChat({ workspace: "w", email: ZZ }, { ws: null, privateTo: [PX] }), false);
  // A viewer said without who they are sees no private chat.
  assert.equal(seesChat({ workspace: "w" }, { ws: null, privateTo: [PX] }), false);
  // Of another workspace: not seen, private to them or not.
  assert.equal(seesChat({ workspace: "w", home: false, email: PX }, { ws: null, privateTo: [PX] }), false);
  // A thread with a private session among its own is that session's people's.
  assert.equal(seesMembers({ workspace: "w", email: ZZ }, [{ ws: null }, { ws: null, privateTo: [PX] }]), false);
  assert.equal(seesMembers({ workspace: "w", email: PX }, [{ ws: null }, { ws: null, privateTo: [PX] }]), true);
});

test("Slack says which messages are direct ones", () => {
  const one = toEvent({ type: "message", channel: "D1", channel_type: "im", user: "U1", text: "hi", ts: "1.1" }, "UBOT", "BBOT");
  const group = toEvent({ type: "message", channel: "G1", channel_type: "mpim", user: "U1", text: "hi", ts: "1.2" }, "UBOT", "BBOT");
  const channel = toEvent({ type: "message", channel: "C1", channel_type: "channel", user: "U1", text: "<@UBOT> hi", ts: "1.3" }, "UBOT", "BBOT");
  assert.deepEqual([one, group, channel].map((e) => (e?.type === "message" ? (e.message.direct ?? null) : "?")), ["one", "group", null]);
});

test("a direct message's chat is private to its people as the platform says their emails; a channel's to no one", async () => {
  const rig = new Rig();
  try {
    rig.chat.emails.set("U1", "PengXiao@cue.surf");
    rig.chat.emails.set("U2", ZZ);
    rig.chat.groups.set("G1", ["U1", "U2", "U3"]);
    const dm = say("hello", { channel: "D1", direct: "one" });
    const group = say("hello all", { channel: "G1", direct: "group", user: "U2" });
    // A group direct message whose people the platform will not say: its sender's alone.
    const unsaid = say("hello", { channel: "G2", direct: "group" });
    const open = say("<@UBOT> hello channel");
    for (const m of [dm, group, unsaid, open]) await rig.accept(m);
    await settle();
    assert.deepEqual(rig.session(sessionKey("cl", "D1", dm.threadTs)).privateTo, [PX]);
    // U3 shares no email: left out.
    assert.deepEqual(rig.session(sessionKey("cl", "G1", group.threadTs)).privateTo, [ZZ, PX]);
    assert.deepEqual(rig.session(sessionKey("cl", "G2", unsaid.threadTs)).privateTo, [PX]);
    assert.equal(rig.session(sessionKey("cl", "C1", open.threadTs)).privateTo, null);
    // A single-session connect's one session is everyone's, a direct message said to it too.
    await rig.accept(say("hi", { channel: "D2", direct: "one" }), "team");
    await settle();
    assert.equal(rig.store.listSessions().find((s) => s.connect === "team")!.privateTo, null);
  } finally {
    await rig.close();
  }
});

test("the pages show a private chat to its people only, a manager not among them neither", () => {
  const data = mkdtempSync(join(tmpdir(), "private-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  try {
    const at = 1_000;
    const row = (key: string, privateTo: string[] | null) => ({ key, connect: "cl", runtime: "claude", profile: "cc", workspace: join(data, key), token: `t-${key}`, createdAt: at, lastActiveAt: at, privateTo });
    store.insertSession(row("cl:D1:1.1", [PX]));
    store.insertSession(row("cl:C1:2.1", null));
    const dm = store.openThread("slack:T1", "D1", "1.1", null, "slack:cl:U1");
    const open = store.openThread("slack:T1", "C1", "2.1", null, "slack:cl:U1");
    store.joinThread(dm.id, "cl:D1:1.1", "cl");
    store.joinThread(open.id, "cl:C1:2.1", "cl");
    store.insertMessage(newMessage(dm.id, "1.1", "person", "U1", "secret plan"));
    store.insertMessage(newMessage(open.id, "2.1", "person", "U1", "public plan"));
    const reader = openStore(data);
    const px = viewerOf(PX);
    const admin = viewerOf(ZZ, "admin");
    const keys = (list: any[]) => list.map((x: any) => x.key ?? x.id).sort();
    assert.deepEqual(keys(sessions(reader, null, false, "en", px)), ["cl:C1:2.1", "cl:D1:1.1"]);
    assert.deepEqual(keys(sessions(reader, null, false, "en", admin)), ["cl:C1:2.1"]);
    assert.deepEqual(threads(reader, px, null, "en").map((t: any) => t.channel).sort(), ["C1", "D1"]);
    assert.deepEqual(threads(reader, admin, null, "en").map((t: any) => t.channel), ["C1"]);
    assert.ok(chats(reader, px, false).some((c: any) => c.id === "cl:D1:1.1"));
    assert.ok(!chats(reader, admin, false).some((c: any) => c.id === "cl:D1:1.1"));
    assert.throws(() => session(reader, "cl:D1:1.1", admin, "en"), /unknown session/);
    assert.equal(session(reader, "cl:D1:1.1", px, "en").session.key, "cl:D1:1.1");
    // What names it is answered as naming nothing, for anyone else.
    assert.equal(sessionSeen(store, admin, "cl:D1:1.1"), false);
    assert.equal(threadSeen(store, admin, dm.id), false);
    assert.equal(threadSeen(store, px, dm.id), true);
    assert.equal(elsewhere(store, `/sessions/${encodeURIComponent("cl:D1:1.1")}/timeline`, admin), "unknown session cl:D1:1.1");
    assert.equal(elsewhere(store, `/threads/${dm.id}/messages`, admin), `unknown thread ${dm.id}`);
    assert.equal(elsewhere(store, `/threads/${dm.id}/messages`, px), null);
    // Search: its chat and messages are found for its people alone.
    const docs = [...threadDocs(reader, dm.id), ...threadDocs(reader, open.id)];
    const found = (reader: string[] | undefined) => pick(docs, ["plan"], { workspace: "w", home: true, scopes: ["write"], reader }).filter((g) => g.kind === "message").flatMap((g) => g.hits.map((h) => h.text));
    assert.deepEqual(found([PX]).sort(), ["public plan", "secret plan"]);
    assert.deepEqual(found([ZZ]), ["public plan"]);
    // Another station's search, or a chat everyone sees: no one's private chat.
    assert.deepEqual(found(undefined), ["public plan"]);
    assert.deepEqual(found([PX, ZZ]), ["public plan"]);
    reader.db.close();
  } finally {
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("an agent reads a private chat only from a chat private to its people; what it opens stays private", async () => {
  const rig = new Rig({ link: true });
  try {
    rig.chat.emails.set("U1", PX);
    const dm = say("hello", { channel: "D1", direct: "one" });
    await rig.accept(dm);
    await settle();
    const mine = sessionKey("cl", "D1", dm.threadTs);
    const open = say("<@UBOT> hello channel");
    await rig.accept(open);
    await settle();
    const theirs = sessionKey("cl", "C1", open.threadTs);
    const [other] = newSession(rig.hub, { runtime: "claude", createdBy: ZZ, title: "another chat" });
    // Not listed, nor read by its key, its address or its link, by a chat everyone sees.
    for (const reader of [theirs, other]) {
      const list = await rig.call(reader, "chat_list", {});
      assert.ok(!list.includes(mine) && !list.includes("D1/"), list);
      for (const chat of [mine, `D1/${dm.threadTs}`, rig.hub.link(mine)!]) {
        assert.match(await rig.refused(reader, "chat_read", { chat }), /direct message, private/);
        assert.match(await rig.refused(reader, "session_history", { chat }), /direct message, private/);
      }
      // Nor through the platform's API.
      assert.match(await rig.refused(theirs, "slack_api", { method: "conversations.history", params: { channel: "D1" } }), /direct message, private/);
    }
    // Its own agent reads it, and the chats everyone sees.
    assert.ok((await rig.call(mine, "chat_list", {})).includes(mine));
    assert.ok((await rig.call(mine, "chat_read", { chat: mine })).startsWith("Conversation"));
    assert.ok((await rig.call(mine, "chat_read", { chat: theirs })).startsWith("Conversation"));
    assert.equal((await rig.call(mine, "slack_api", { method: "conversations.history", params: { channel: "D1" } })).startsWith("{"), true);
    // A letter to it is taken: what it is told shows nothing of it.
    assert.match(await rig.call(other, "session_send", { to: mine, text: "a question" }), /^Sent to/);
    // A chat it opens is private to its people too, and is opened on this station only.
    const made = await rig.call(mine, "chat_create", { key: "side", text: "look into it", title: "side work" });
    const child = rig.store.listSessions().find((s) => s.title === "side work")!;
    assert.deepEqual(child.privateTo, [PX], made);
    assert.match(await rig.refused(other, "chat_read", { chat: child.key }), /direct message, private/);
    assert.ok((await rig.call(mine, "chat_read", { chat: child.key })).startsWith("Conversation"));
  } finally {
    await rig.close();
  }
});
