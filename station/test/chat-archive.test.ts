import assert from "node:assert/strict";
import { test } from "node:test";
import { ARCHIVE, archiveForPeer } from "../src/sessions/chat-archive.ts";
import { archiveBy, newSession, openChat, say } from "../src/sessions/lifecycle.ts";
import { AUTO, MANUAL } from "../src/store/rows.ts";
import { Rig, settle } from "./hub-fakes.ts";

const web = (ws?: string) => ({ runtime: "claude" as const, createdBy: "ada@example.com", ws });

test("an agent archives another chat as the app does, and a repeated call leaves its archive time alone", async () => {
  const r = new Rig({ link: true });
  try {
    const [caller] = newSession(r.hub, web());
    const [other, thread] = newSession(r.hub, web());
    say(r.hub, thread.id, "ada@example.com", "keep this message");
    await settle();
    const link = r.hub.link(other)!;
    // An automatic archive must become a manual one, so a new message does not bring it back.
    archiveBy(r.hub, other, true, AUTO);
    assert.match(await r.call(caller, "chat_archive", { chat: link }), /^Archived /);
    assert.equal(r.store.getSession(other)!.archivedBy, MANUAL);
    assert.equal(r.store.getThread(thread.id)!.hiddenBy, MANUAL);
    assert.ok((await r.call(caller, "chat_read", { chat: link })).includes("keep this message"));
    const at = r.store.getSession(other)!.archivedAt;
    assert.match(await r.call(caller, "chat_archive", { chat: `CHAT/${thread.threadTs}` }), /^Already archived/);
    assert.equal(r.store.getSession(other)!.archivedAt, at);
    assert.equal(r.store.getSession(caller)!.archivedAt, null);
    assert.match(await r.refused(caller, "chat_archive", { chat: caller }), /not your own/);
    assert.match(await r.refused(caller, "chat_archive", {}), /chat is required/);
  } finally {
    await r.close();
  }
});

test("an extra chat is archived without archiving its session; Slack threads are refused", async () => {
  const r = new Rig({ link: true });
  try {
    const [caller] = newSession(r.hub, web());
    const [other] = newSession(r.hub, web());
    const extra = openChat(r.hub, other, "ada@example.com", "extra");
    assert.equal(extra.home, null);
    await r.call(caller, "chat_archive", { chat: `CHAT/${extra.threadTs}` });
    assert.equal(r.store.getThread(extra.id)!.hiddenBy, MANUAL);
    assert.equal(r.store.getSession(other)!.archivedAt, null);
    assert.match(await r.call(caller, "chat_archive", { chat: `CHAT/${extra.threadTs}` }), /^Already archived/);
    r.store.openThreadOf("slack:T1", "C1", "9.1", null, null, null);
    assert.match(await r.refused(caller, "chat_archive", { chat: "C1/9.1" }), /only still.fail chats/);
  } finally {
    await r.close();
  }
});

test("a chat page showing another session's history archives the page's chat", async () => {
  const r = new Rig({ link: true });
  try {
    const [caller] = newSession(r.hub, web());
    const [page] = newSession(r.hub, web());
    const [history] = newSession(r.hub, web());
    const link = `${r.hub.link(page)!}?history=${encodeURIComponent(history)}&entry=1`;
    await r.call(caller, "chat_archive", { chat: link });
    assert.equal(r.store.getSession(page)!.archivedBy, MANUAL);
    assert.equal(r.store.getSession(history)!.archivedAt, null);
    const own = `${r.hub.link(caller)!}?history=${encodeURIComponent(history)}`;
    assert.match(await r.refused(caller, "chat_archive", { chat: own }), /not your own/);
  } finally {
    await r.close();
  }
});

test("an agent archives a chat on another station through the workspace transport", async () => {
  const near = new Rig({ link: true, place: { workspace: "w", station: "near" }, workspaces: ["w"] });
  const far = new Rig({ link: true, place: { workspace: "w", station: "far" }, workspaces: ["w"] });
  try {
    const [caller] = newSession(near.hub, web("w"));
    const [other] = newSession(far.hub, web("w"));
    const link = far.hub.link(other)!;
    near.hub.onPeer(async (station, request) => {
      assert.equal(station, "far");
      assert.deepEqual(request, { workspace: "w", method: ARCHIVE, session: caller, chat: link });
      return archiveForPeer(far.hub, request, "w");
    });
    assert.match(await near.call(caller, "chat_archive", { chat: link }), /^Archived /);
    assert.equal(far.store.getSession(other)!.archivedBy, MANUAL);
    assert.match(await near.call(caller, "chat_archive", { chat: link }), /^Already archived/);
    near.hub.onPeer(async () => { throw new Error("connection lost"); });
    assert.match(await near.refused(caller, "chat_archive", { chat: link }), /may already be archived.*again/);
  } finally {
    await near.close();
    await far.close();
  }
});

test("a writable chat shared from another workspace cannot be archived locally or by a peer", async () => {
  const r = new Rig({ link: true, place: { workspace: "one", station: "st" }, workspaces: ["one", "two"] });
  try {
    const [caller] = newSession(r.hub, web("one"));
    const [other] = newSession(r.hub, web("two"));
    r.store.setChatShare(other, [{ workspace: "one", name: "One" }], true, "ada@example.com");
    const link = r.hub.link(other)!;
    assert.match(await r.refused(caller, "chat_archive", { chat: link }), /another workspace/);
    await assert.rejects(archiveForPeer(r.hub, { chat: link }, "one"), /another workspace/);
    assert.equal(r.store.getSession(other)!.archivedAt, null);
  } finally {
    await r.close();
  }
});
