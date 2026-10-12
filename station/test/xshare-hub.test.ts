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
import { sessionKey } from "../src/sessions/hub.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

type Side = { rig: Rig; xshare: ChatShares };

function side(workspace: string, station: string, name: string, other: () => Side): Side {
  const rig = new Rig({ link: true, place: { workspace, station } });
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
  const cloud: any = {
    peersCurrent: true,
    state: { station, workspace, workspace_name: name, peers: [{ id: station, name }] },
    removed: () => false,
    listen: () => () => {},
  };
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
  });
  hub.onPeer((to, request) => ask(to, me.xshare.address(to, request)));
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
  const got = far.rig.said(thread.id).at(-1)!;
  assert.ok(got.author === `near/${keyN}` && got.text.endsWith("send me the plan"), got.text);
  await far.rig.call(keyA, "session_send", { to: near.rig.hub.link(keyN)!, text: "here it is" });
  const answered = near.rig.said(near.rig.thread("C1", n.threadTs).id).at(-1)!;
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
