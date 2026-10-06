// Stations of a workspace calling each other over the mesh (peer.rs), its endpoints connected in memory
// (memory-mesh.ts): a request answered by the other's remote tasks; its refusal a Refused; who may call only the
// roster's stations, while the roster is current.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { Refused } from "../src/jobs/remote.ts";
import { PEER_ALPN, member, peerCall, servePeer } from "../src/mesh/peer.ts";
import { memoryMesh } from "./memory-mesh.ts";

const cloudOf = (station: string, peers: string[]): any => ({
  state: { workspace: "ws", station, peers: peers.map((id) => ({ id })) },
  peersCurrent: true,
  removed: () => false,
  relays: () => [],
});

test("a peer's request is answered by the other station's remote tasks", async () => {
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  const sourceCloud = cloudOf(source.id(), [target.id()]);
  const targetCloud = cloudOf(target.id(), [source.id()]);
  const asked: any[] = [];
  const remote: any = {
    handle: async (workspace: string, peer: string, request: any) => {
      asked.push([workspace, peer, request.method]);
      if (request.method === "no") throw new Error("remote tasks are not enabled");
      return { ok: request.method };
    },
  };
  void (async () => {
    for (;;) {
      const conn = await target.accept();
      if (!conn) return;
      void servePeer(conn, targetCloud, remote).catch(() => {});
    }
  })();
  const port = target.sockets()[0]!.split(":").at(-1);
  const call = peerCall(source, sourceCloud, (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
  try {
    assert.deepEqual(await call(target.id(), "ws", { method: "describe" }), { ok: "describe" });
    assert.deepEqual(await call(target.id(), "ws", { method: "task.get" }), { ok: "task.get" });
    await assert.rejects(call(target.id(), "ws", { method: "no" }), (e) => e instanceof Refused && /not enabled/.test(e.message));
    assert.deepEqual(asked.map((a) => a.slice(0, 2)), [["ws", source.id()], ["ws", source.id()], ["ws", source.id()]]);
    // The transport's own roster.
    assert.deepEqual(await call("", null, { method: "peers" }), { workspace: "ws", stations: [{ id: target.id() }], current: true });
    // Only stations of the roster, of this workspace, while the roster is current.
    await assert.rejects(call("ab".repeat(32), "ws", { method: "describe" }), /not another station/);
    await assert.rejects(call(target.id(), "other", { method: "describe" }), /outside this workspace/);
    targetCloud.state.peers = [];
    await assert.rejects(call(target.id(), "ws", { method: "describe" }), Refused);
    sourceCloud.peersCurrent = false;
    assert.throws(() => member(sourceCloud, target.id(), null), /not current/);
  } finally {
    await Promise.all([source.close(), target.close()]);
  }
});
