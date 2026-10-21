// Stations of a workspace calling each other over the mesh (peer.rs), its endpoints connected in memory
// (memory-mesh.ts): a request answered by the other's remote tasks; its refusal a Refused; who may call only the
// roster's stations, while the roster is current.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { Refused } from "../src/jobs/remote.ts";
import { PEER_ALPN, member, peerCall, servePeer } from "../src/mesh/peer.ts";
import { memoryMesh } from "./memory-mesh.ts";
import { Cloud, type Joined } from "../src/cloud/state.ts";

/// A station's cloud.json in memory, read as the station reads it (Cloud's own memberships): in workspace "ws", and in
/// those of `joined` too.
const cloudOf = (station: string, peers: string[], joined: Joined[] = []): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name: "", station, peers: peers.map((id) => ({ id })), revocations: [], joined },
    lock: null,
    peersCurrent: true,
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

test("a slow request holds up no other on the same connection", async () => {
  // Answered one after another, one slow request (a sync on a loaded station) held up all the caller's others: every
  // chat of a station asking another shares one connection, and each timed out (2026-10-20, ccvm to Studio).
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  let release!: () => void;
  const released = new Promise<void>((resolve) => (release = resolve));
  const remote: any = {
    handle: async (_workspace: string, _peer: string, request: any) => {
      if (request.method === "slow") await released;
      return { ok: request.method };
    },
  };
  const conns: any[] = [];
  void (async () => {
    for (;;) {
      const conn = await target.accept();
      if (!conn) return;
      conns.push(conn);
      void servePeer(conn, cloudOf(target.id(), [source.id()]), remote).catch(() => {});
    }
  })();
  const port = target.sockets()[0]!.split(":").at(-1);
  const call = peerCall(source, cloudOf(source.id(), [target.id()]), (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
  try {
    assert.deepEqual(await call(target.id(), "ws", { method: "describe" }), { ok: "describe" });
    const slow = call(target.id(), "ws", { method: "slow" });
    const quick = await Promise.race([call(target.id(), "ws", { method: "task.get" }), slow.then(() => "slow first")]);
    assert.deepEqual(quick, { ok: "task.get" });
    release();
    assert.deepEqual(await slow, { ok: "slow" });
    assert.equal(conns.length, 1, "all on the one connection");
  } finally {
    await Promise.all([source.close(), target.close()]);
  }
});

test("requests asked while no connection is open share the one dialed; one answered late leaves it to the others", async () => {
  // Each request dialed its own, and one that timed out dropped the connection for the next to dial another while the
  // old one's requests were still answered: dozens of a station's followed tasks, each round (2026-10-21, ccvm to Studio).
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  let release!: () => void;
  const released = new Promise<void>((resolve) => (release = resolve));
  const remote: any = {
    handle: async (_workspace: string, _peer: string, request: any) => {
      if (request.method === "slow") await released;
      return { ok: request.method };
    },
  };
  const conns: any[] = [];
  void (async () => {
    for (;;) {
      const conn = await target.accept();
      if (!conn) return;
      conns.push(conn);
      void servePeer(conn, cloudOf(target.id(), [source.id()]), remote).catch(() => {});
    }
  })();
  const port = target.sockets()[0]!.split(":").at(-1);
  // Answers waited for 50 ms: the slow one is never answered in time, however fast the machine.
  const call = peerCall(source, cloudOf(source.id(), [target.id()]), (id) => ({ id, ips: [`127.0.0.1:${port}`] }), undefined, 50);
  try {
    const answers = await Promise.all(Array.from({ length: 10 }, (_, i) => call(target.id(), "ws", { method: `m${i}` })));
    assert.deepEqual(answers.map((a: any) => a.ok), Array.from({ length: 10 }, (_, i) => `m${i}`));
    assert.equal(conns.length, 1, "dialed once");
    await assert.rejects(call(target.id(), "ws", { method: "slow" }), /timed out/);
    assert.deepEqual(await call(target.id(), "ws", { method: "after" }), { ok: "after" });
    assert.equal(conns.length, 1, "its peer heard: the connection kept");
    // Its peer no longer heard: the connection closed, the next request dials again.
    conns[0].silent = true;
    await assert.rejects(call(target.id(), "ws", { method: "slow" }), /timed out/);
    await conns[0].closed();
    assert.deepEqual(await call(target.id(), "ws", { method: "again" }), { ok: "again" });
    assert.equal(conns.length, 2);
  } finally {
    release();
    await Promise.all([source.close(), target.close()]);
  }
});

test("a station of another workspace is asked only when chats are shared with it, and heard only for them", async () => {
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target, closed] = await Promise.all([bind(), bind(), bind()]);
  const sourceCloud = cloudOf(source.id(), []);
  sourceCloud.state.workspace = "home";
  const targetCloud = cloudOf(target.id(), []);
  const heard: any[] = [];
  const remote: any = {
    handle: async () => ({ inside: true }),
    hearsOutside: () => true,
    handleOutside: async (peer: string, request: any) => (heard.push([peer, request.method]), { outside: request.method }),
  };
  const serve = (endpoint: typeof target, cloud: any, r: any) =>
    void (async () => {
      for (;;) {
        const conn = await endpoint.accept();
        if (!conn) return;
        // As the mesh does (mesh.ts): a connection that is not served is closed.
        void servePeer(conn, cloud, r).catch(() => conn.close(0, "refused"));
      }
    })();
  serve(target, targetCloud, remote);
  // A station that hears no other workspace (none shares chats there): not even connected to.
  serve(closed, cloudOf(closed.id(), []), { handle: async () => ({}) });
  const ports = new Map([target, closed].map((e) => [e.id(), e.sockets()[0]!.split(":").at(-1)]));
  let reaches = false;
  const call = peerCall(source, sourceCloud, (id) => ({ id, ips: [`127.0.0.1:${ports.get(id)}`] }), { reaches: (_t, w) => reaches && w === "ws" });
  try {
    await assert.rejects(call(target.id(), "ws", { method: "session.read" }), /shares no chat/);
    reaches = true;
    assert.deepEqual(await call(target.id(), "ws", { method: "session.read" }), { outside: "session.read" });
    assert.deepEqual(heard, [[source.id(), "session.read"]]);
    // Its requests must name the workspace they are heard in.
    const wrong = peerCall(source, sourceCloud, (id) => ({ id, ips: [`127.0.0.1:${ports.get(id)}`] }), { reaches: () => true });
    await assert.rejects(wrong(target.id(), "elsewhere", { method: "session.read" }), (e) => e instanceof Refused && /outside this workspace/.test(e.message));
    await assert.rejects(wrong(closed.id(), "ws", { method: "session.read" }), (e) => !(e instanceof Refused));
  } finally {
    await Promise.all([source.close(), target.close(), closed.close()]);
  }
});

test("a station in two workspaces asks and hears each one's stations in that workspace only", async () => {
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [both, homeMate, joinedMate] = await Promise.all([bind(), bind(), bind()]);
  // `both` is in "ws" with homeMate and in "w2" with joinedMate; each of those is in its own workspace only.
  const bothCloud = cloudOf(both.id(), [homeMate.id()], [{ workspace: "w2", workspace_name: "W2", name: "both", peers: [{ id: joinedMate.id() }], revocations: [] }]);
  const asked: any[] = [];
  const remote: any = { handle: async (workspace: string, peer: string, request: any) => (asked.push([workspace, peer, request.method]), { ok: workspace }) };
  void (async () => {
    for (;;) {
      const conn = await both.accept();
      if (!conn) return;
      void servePeer(conn, bothCloud, remote).catch(() => conn.close(0, "refused"));
    }
  })();
  const port = both.sockets()[0]!.split(":").at(-1);
  const at = (id: string) => ({ id, ips: [`127.0.0.1:${port}`] });
  const fromHome = peerCall(homeMate, cloudOf(homeMate.id(), [both.id()]), at);
  const joinedCloud = cloudOf(joinedMate.id(), [both.id()]);
  joinedCloud.state.workspace = "w2";
  const fromJoined = peerCall(joinedMate, joinedCloud, at);
  try {
    assert.deepEqual(await fromHome(both.id(), "ws", { method: "describe" }), { ok: "ws" });
    assert.deepEqual(await fromJoined(both.id(), "w2", { method: "describe" }), { ok: "w2" });
    assert.deepEqual(asked, [["ws", homeMate.id(), "describe"], ["w2", joinedMate.id(), "describe"]]);
    // Each is heard in its own workspace only: the joined one's station is no station of the home one's.
    const sneaky = cloudOf(joinedMate.id(), [both.id()]);
    await assert.rejects(peerCall(joinedMate, sneaky, at)(both.id(), "ws", { method: "describe" }), (e) => e instanceof Refused && /not another station/.test(e.message));
    // Asking: each workspace's roster, by the workspace asked in.
    assert.equal(member(bothCloud, joinedMate.id(), "w2"), "w2");
    assert.throws(() => member(bothCloud, joinedMate.id(), "ws"), /not another station/);
    assert.equal(member(bothCloud, joinedMate.id(), null), "w2");
    const call = peerCall(both, bothCloud, at);
    assert.deepEqual(await call("", "w2", { method: "peers" }), { workspace: "w2", stations: [{ id: joinedMate.id() }], current: true });
    assert.deepEqual(await call("", null, { method: "peers" }), { workspace: "ws", stations: [{ id: homeMate.id() }], current: true });
    // A station of the home workspace asking in the joined one: no station of it, heard as one of another workspace
    // (chats shared there) when the station hears those.
    remote.hearsOutside = () => true;
    remote.handleOutside = async (_peer: string, request: any, workspace: string) => (asked.push(["outside", workspace, request.method]), { outside: workspace });
    await assert.rejects(fromHome(both.id(), "w2", { method: "session.read" }), /outside this workspace/);
    const sharing = peerCall(homeMate, cloudOf(homeMate.id(), [both.id()]), at, { reaches: (_t, w) => w === "w2" });
    assert.deepEqual(await sharing(both.id(), "w2", { method: "session.read" }), { outside: "w2" });
    assert.deepEqual(asked.at(-1), ["outside", "w2", "session.read"]);
  } finally {
    await Promise.all([both.close(), homeMate.close(), joinedMate.close()]);
  }
});

test("a connection made before the roster is current is heard as the workspace's once it is", async () => {
  // A station just started (an update) with chats shared across workspaces: its roster comes a little after the first
  // connection. That connection was taken for an outsider's for its whole life (2026-10-17: station_task refused as
  // sharing no chat until it idled out).
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  const sourceCloud = cloudOf(source.id(), [target.id()]);
  const targetCloud = cloudOf(target.id(), [source.id()]);
  targetCloud.peersCurrent = false;
  const remote: any = {
    handle: async (workspace: string) => ({ inside: workspace }),
    hearsOutside: () => true,
    handleOutside: async () => {
      throw new Error("this station shares no chat with your workspace");
    },
  };
  void (async () => {
    for (;;) {
      const conn = await target.accept();
      if (!conn) return;
      void servePeer(conn, targetCloud, remote).catch(() => conn.close(0, "refused"));
    }
  })();
  const port = target.sockets()[0]!.split(":").at(-1);
  const call = peerCall(source, sourceCloud, (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
  try {
    await assert.rejects(call(target.id(), "ws", { method: "describe" }), (e) => e instanceof Refused && /not current/.test(e.message));
    targetCloud.peersCurrent = true;
    assert.deepEqual(await call(target.id(), "ws", { method: "describe" }), { inside: "ws" });
  } finally {
    await Promise.all([source.close(), target.close()]);
  }
});
