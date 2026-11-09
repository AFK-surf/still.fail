import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { Cloud } from "../src/cloud/state.ts";
import { peerRead, textOf } from "../src/comma/peer.ts";
import { CHECK_BYTES, type Bytes, bytesOf, withBytes } from "../src/mesh/bus.ts";
import { PEER_BYTES_ALPN, member, peerCall, servePeer } from "../src/mesh/peer.ts";
import { outflowMessages } from "../src/read/outflow.ts";
import * as read from "../src/read/store.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { memoryMesh } from "./memory-mesh.ts";

type Json = any;
const cloudOf = (station: string, peer: string): any => Object.assign(Object.create(Cloud.prototype), {
  state: { workspace: "old", workspace_name: "Old", name: "", station, peers: [{ id: peer }], revocations: [], joined: [] },
  lock: null, peersCurrent: true, relays: () => [],
});

test("a peer's read does not cross a home change, even if the previous home returns", async () => {
  let home = "old", version = 0, release!: () => void, entered!: () => void;
  const reached = new Promise<void>((resolve) => { entered = resolve; });
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const answer = peerRead(async () => { entered(); await gate; return "{}"; }, () => home, () => "en", () => version, () => {});
  const pending = answer("peer", { op: "outflowMessages" }, "old");
  await reached;
  home = "new"; version++;
  home = "old"; version++;
  release();
  await assert.rejects(pending, /workspace changed/);
});

test("a peer removed while a read is running or before its body is read receives nothing", async () => {
  let allowed = true, release!: () => void, entered!: () => void;
  const reached = new Promise<void>((resolve) => { entered = resolve; });
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const check = () => { if (!allowed) throw new Error("peer removed"); };
  const answer = peerRead(async () => { entered(); await gate; return "private"; }, () => "old", () => "en", () => 0, check);
  const pending = answer("peer", { op: "outflowMessages" }, "old");
  await reached;
  allowed = false;
  release();
  await assert.rejects(pending, /peer removed/);

  allowed = true;
  const ready = await answer("peer", { op: "outflowMessages" }, "old");
  allowed = false;
  await assert.rejects(() => textOf(bytesOf(ready)!), /peer removed/);
});

test("a removed peer cannot read a message created after the target changes home", async () => {
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_BYTES_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  const fromCloud = cloudOf(source.id(), target.id()), targetCloud = cloudOf(target.id(), source.id());
  const store = Store.open(":memory:");
  let release = () => {}, version = 0;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1, ws: null } as never);
    const thread = store.openThreadOf("ember", "CHAT", "100.1", "A chat", "ann@x", "a");
    store.joinThread(thread.id, "a", "ember");
    const reader = read.makeStore(store.db, ".");
    let entered!: () => void;
    const reached = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const answer = peerRead(async (_op, args: Json) => {
      entered(); await gate;
      return JSON.stringify(outflowMessages(reader, thread.id, 0, 100, args.ws));
    }, () => targetCloud.home(), () => "en", () => version, (peer, workspace) => { member(targetCloud, peer, workspace); });
    const remote: any = { handle: (workspace: string, peer: string, request: Json) => answer(peer, request, workspace) };
    void (async () => {
      for (;;) {
        const conn = await target.accept();
        if (!conn) return;
        void servePeer(conn, targetCloud, remote).catch(() => conn.close(0, "refused"));
      }
    })();
    const port = target.sockets()[0]!.split(":").at(-1);
    const call = peerCall(source, fromCloud, (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
    assert.equal(member(targetCloud, source.id(), "old"), "old");
    const pending = call(target.id(), "old", { method: "outflow.read", op: "outflowMessages", args: { thread: thread.id } });
    await reached;
    targetCloud.state = { ...targetCloud.state, workspace: "new", peers: [] }; version++;
    assert.throws(() => member(targetCloud, source.id(), "old"));
    store.insertMessage(newMessage(thread.id, "100.2", "person", "ann@x", "new home only"));
    assert.equal(outflowMessages(reader, thread.id, 0, 100, { workspace: "old", home: false }), null);
    release();
    await assert.rejects(pending, /workspace changed/);
  } finally {
    release();
    store.close();
    await Promise.all([source.close(), target.close()]);
  }
});

for (const transition of ["home", "peer"] as const) for (const timing of ["before head", "before body write"] as const) {
  test(`a ${transition} change ${timing} sends no answer body`, async () => {
    const mesh = memoryMesh();
    const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_BYTES_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
    const [source, target] = await Promise.all([bind(), bind()]);
    const fromCloud = cloudOf(source.id(), target.id()), targetCloud = cloudOf(target.id(), source.id());
    let version = 0, changed = false, received = "";
    const change = () => {
      if (transition === "home") { targetCloud.state = { ...targetCloud.state, workspace: "new", peers: [] }; version++; }
      else targetCloud.state = { ...targetCloud.state, peers: [] };
      changed = true;
    };
    const answer = peerRead(async () => JSON.stringify({ text: "private" }), () => targetCloud.home(), () => "en",
      () => version, (peer, workspace) => { member(targetCloud, peer, workspace); });
    const remote: any = { handle: async (workspace: string, peer: string, request: Json) => {
      const result = await answer(peer, request, workspace);
      if (timing === "before head") { change(); return result; }
      const original = bytesOf(result)!;
      const delayed: Bytes = { [CHECK_BYTES]: original[CHECK_BYTES]!, async *[Symbol.asyncIterator]() {
        for await (const chunk of original) { change(); yield chunk; }
      } };
      return withBytes(result, delayed);
    } };
    void (async () => {
      for (;;) {
        const conn = await target.accept();
        if (!conn) return;
        void servePeer(conn, targetCloud, remote).catch(() => conn.close(0, "refused"));
      }
    })();
    const port = target.sockets()[0]!.split(":").at(-1);
    const call = peerCall(source, fromCloud, (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
    try {
      await assert.rejects(async () => {
        const result = await call(target.id(), "old", { method: "outflow.read", op: "outflowMessages" });
        for await (const chunk of bytesOf(result)!) received += chunk.toString("utf8");
      }, /workspace changed|peer is not|stream reset/);
      assert.equal(changed, true);
      assert.equal(received, "");
    } finally { await Promise.all([source.close(), target.close()]); }
  });
}
