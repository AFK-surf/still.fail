// A chat shared with another workspace, as the agents there use it (docs/chat-share.md): two stations of different
// workspaces, their hubs and chat shares wired as agents.ts wires them, the transport between them a direct call.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Refused } from "../src/jobs/remote.ts";
import { fromPeer, sender } from "../src/sessions/messages.ts";
import { chatsTouched, forPeer, READ } from "../src/sessions/others.ts";
import { FILE, fileForPeer, PUT, putForPeer } from "../src/sessions/peer-files.ts";
import { ChatShares } from "../src/xshare/index.ts";
import { Cloud } from "../src/cloud/state.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import type { Clock } from "effect";
import { XSHARE_IDLE_MS } from "../src/store/rows.ts";
import { Rig, say, settle, testClock } from "./hub-fakes.ts";

type Side = { rig: Rig; xshare: ChatShares };

function side(workspace: string, station: string, name: string, other: () => Side, clock?: Clock.Clock): Side {
  const rig = new Rig({ link: true, place: { workspace, station }, clock });
  const hub = rig.hub;
  const inbox = async (peer: string, request: any) => {
    switch (request?.method) {
      case READ:
        return forPeer(hub, peer, request);
      case FILE:
        return fileForPeer(hub, request);
      case PUT:
        return putForPeer(hub, peer, request);
      default:
        return fromPeer(hub, peer, request);
    }
  };
  const cloud: any = Object.assign(Object.create(Cloud.prototype), {
    peersCurrent: true,
    lock: null,
    state: { station, workspace, workspace_name: name, peers: [{ id: station, name }], revocations: [] },
    listen: () => () => {},
  });
  const me: Side = { rig, xshare: null as any };
  // The transport: only the other station, of another workspace, and only when this one reaches it (peer.ts).
  const ask = async (to: string, request: any) => {
    const there = other();
    if (to !== there.rig.place.station || !me.xshare.reaches(to, request?.workspace)) throw new Error("that station is of another workspace that shares no chat with this one");
    try {
      return await there.xshare.outside(station, request);
    } catch (e) {
      throw new Refused((e as Error).message);
    }
  };
  me.xshare = new ChatShares({
    data: mkdtempSync(join(tmpdir(), "xshare-hub-")),
    store: rig.store,
    cloud,
    ask,
    link: (chat) => hub.link(chat) ?? null,
    title: (chat) => sender(hub, chat)[0],
    touches: (request) => chatsTouched(hub, request),
    inbox,
    clock,
  });
  hub.onPeer((to, request) => me.xshare.send(to, request, (r) => ask(to, r)));
  hub.onOutsideChats(() => me.xshare.borrowed());
  return me;
}

test("an agent of another workspace finds, reads and (when allowed) writes to a chat shared with it, and is answered", async () => {
  let near: Side;
  const far: Side = side("W1", "far", "Team", () => near);
  near = side("W2", "near", "Home", () => far);
  const a = say("<@UBOT> the release plan");
  await far.rig.accept(a);
  const b = say("<@UBOT> something private");
  await far.rig.accept(b);
  const n = say("<@UBOT> what is the plan over there?");
  await near.rig.accept(n);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  const keyB = sessionKey("cl", "C1", b.threadTs);
  const keyN = sessionKey("cl", "C1", n.threadTs);
  const linkA = far.rig.hub.link(keyA)!;
  const linkB = far.rig.hub.link(keyB)!;

  // Nothing shared: a chat of the other workspace cannot be read.
  assert.match(await near.rig.refused(keyN, "chat_read", { chat: linkA }), /shares no chat/);

  // Shared read-only with W2, whose member said to take chats from "far".
  await far.xshare.share(keyA, [{ workspace: "W2", name: "Home", stations: [{ id: "near", name: "laptop" }] }], false, "a@example.com");
  await near.xshare.trust("W1", "Team", "far", "studio");
  await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
  await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
  const list = await near.rig.call(keyN, "chat_list", {});
  assert.ok(list.includes(`${linkA} (shared from workspace "Team", read only)`), list);
  const read = await near.rig.call(keyN, "chat_read", { chat: linkA });
  assert.ok(read.includes("the release plan"), read);
  await near.rig.call(keyN, "session_history", { chat: linkA });
  // Another chat of that station is not shared.
  assert.match(await near.rig.refused(keyN, "chat_read", { chat: linkB }), /not shared with your workspace/);
  assert.match(await near.rig.refused(keyN, "session_send", { to: linkA, text: "hello" }), /read only/);
  assert.match(await near.rig.refused(keyN, "chat_create", { key: "x", station: "far", text: "x" }), /./);

  // Writable: the message is posted there, and its agent can answer the session that wrote.
  await far.xshare.share(keyA, [{ workspace: "W2", name: "Home", stations: [{ id: "near", name: "laptop" }] }], true, "a@example.com");
  await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
  assert.ok((await near.rig.call(keyN, "chat_list", {})).includes("you may send to it"));
  await near.rig.call(keyN, "session_send", { to: linkA, text: "send me the plan" });
  const thread = far.rig.thread("C1", a.threadTs);
  const got = far.rig.letters(thread.id).at(-1)!;
  assert.ok(got.author === `near/${keyN}` && got.text.endsWith("send me the plan"), got.text);
  await far.rig.call(keyA, "session_send", { to: near.rig.hub.link(keyN)!, text: "here it is" });
  const answered = near.rig.letters(near.rig.thread("C1", n.threadTs).id).at(-1)!;
  assert.ok(answered.author === `far/${keyA}` && answered.text.endsWith("here it is"), answered.text);
  // It cannot write to another session there.
  const other = say("<@UBOT> unrelated");
  await near.rig.accept(other);
  await settle();
  assert.match(await far.rig.refused(keyA, "session_send", { to: near.rig.hub.link(sessionKey("cl", "C1", other.threadTs))!, text: "hi" }), /shares no chat/);

  // No longer shared: gone from the list, and refused.
  await far.xshare.share(keyA, [], false, "a@example.com");
  await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
  assert.ok(!(await near.rig.call(keyN, "chat_list", {})).includes("Shared with this workspace"));
  assert.match(await near.rig.refused(keyN, "chat_read", { chat: linkA }), /not shared|shares no chat/);
  await Promise.all([far.xshare.close(), near.xshare.close()]);
  await far.rig.close();
  await near.rig.close();
});

test("a share lapses once its agents have not read or written for six hours, until a person shares it again", async () => {
  const time = testClock();
  const HOUR = 60 * 60_000;
  let near: Side;
  const far: Side = side("W1", "far", "Team", () => near, time.clock);
  near = side("W2", "near", "Home", () => far, time.clock);
  far.xshare.start();
  near.xshare.start();
  const a = say("<@UBOT> the release plan");
  await far.rig.accept(a);
  const n = say("<@UBOT> what is the plan over there?");
  await near.rig.accept(n);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  const keyN = sessionKey("cl", "C1", n.threadTs);
  const linkA = far.rig.hub.link(keyA)!;
  const linkN = near.rig.hub.link(keyN)!;
  const both = async () => {
    await settle();
    await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
    await Promise.all([far.xshare.reconcile(), near.xshare.reconcile()]);
  };
  const to = [{ workspace: "W2", name: "Home", stations: [{ id: "near", name: "laptop" }] }];
  await far.xshare.share(keyA, to, true, "a@example.com");
  await near.xshare.trust("W1", "Team", "far", "studio");
  await both();

  // Each use goes on from then: read at 5 hours, written to at 10 (answered at 14), read at 15, each inside six hours of
  // the one before.
  await time.adjust(5 * HOUR);
  assert.ok((await near.rig.call(keyN, "chat_read", { chat: linkA })).includes("the release plan"));
  await time.adjust(5 * HOUR);
  await near.rig.call(keyN, "session_send", { to: linkA, text: "send me the plan" });
  await time.adjust(4 * HOUR);
  await far.rig.call(keyA, "session_send", { to: linkN, text: "here it is" });
  await time.adjust(HOUR);
  await near.rig.call(keyN, "session_history", { chat: linkA });
  assert.ok((await near.rig.call(keyN, "chat_list", {})).includes(`${linkA} (shared from`));

  // Six hours without: the chat is no longer shared with W2 (its row says so, its list no longer has it), its agents
  // are told why, and its agent no longer answers the session that wrote.
  await time.adjust(XSHARE_IDLE_MS);
  await both();
  assert.equal(far.rig.store.chatShare(keyA), null);
  assert.ok(!(await near.rig.call(keyN, "chat_list", {})).includes(`${linkA} (shared from`));
  assert.match(await near.rig.refused(keyN, "chat_read", { chat: linkA }), /lapsed, unused for 6 hours/);
  assert.match(await near.rig.refused(keyN, "session_send", { to: linkA, text: "still there?" }), /lapsed/);
  assert.match(await far.rig.refused(keyA, "session_send", { to: linkN, text: "one more thing" }), /./);

  // Shared again by a person: on for another six hours.
  await far.xshare.share(keyA, to, true, "a@example.com");
  await both();
  assert.ok((await near.rig.call(keyN, "chat_read", { chat: linkA })).includes("the release plan"));
  assert.ok((await near.rig.call(keyN, "chat_list", {})).includes(`${linkA} (shared from`));
  await Promise.all([far.xshare.close(), near.xshare.close()]);
  await far.rig.close();
  await near.rig.close();
});
