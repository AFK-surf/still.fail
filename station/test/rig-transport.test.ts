// A rig on the station transport (rig/module.ts, mesh/peer.ts; a station that only runs tasks), its endpoints connected in memory
// (memory-mesh.ts): a station asks it as it asks another station, and what starts or writes something there needs the
// chat's grant; the rig asks nothing of a station, and only tells of itself; in security mode a rig the control plane
// names is asked nothing but what its person signed for it, until that holds.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, randomBytes, sign as nodeSign } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type GrantBody, latest, signedBytes } from "../../client/core-ts/src/rig-form.ts";
import { type Entry, entryHash, signedBytes as entryBytes } from "../src/cloud/lock.ts";
import { Cloud } from "../src/cloud/state.ts";
import { PeerBus, Refused } from "../src/mesh/bus.ts";
import { PEER_ALPN, PEER_BYTES_ALPN, peerCall, servePeer } from "../src/mesh/peer.ts";
import { Rig } from "../src/rig/module.ts";
import { memoryMesh } from "./memory-mesh.ts";

const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest();

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Uint8Array) => nodeSign(null, bytes, privateKey).toString("hex") };
}

/// A person's own lock of one device, and what that device signs.
function person(sub: string) {
  const key = ed();
  const e = { v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub, device: { key: key.id, id: ed().hex, label: "first" } } } as Omit<Entry, "sig">;
  const chain = [{ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(entryBytes(entryHash(e as Entry))) } } as Entry];
  return { chain, genesis: entryHash(chain[0]!), says: <B>(kind: "grant" | "revoke" | "settings" | "add", body: B) => ({ body, sig: { key: key.id, sig: key.sign(signedBytes(kind, body, sha256)) } }) };
}

/// A machine's cloud.json in memory, read as the station reads it: in workspace "ws" with `peers`; a station names the
/// workspace's `rigs`, a rig says whose it is (`rig`).
const cloudOf = (station: string, peers: string[], more: Record<string, unknown> = {}): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name: "", station, peers: peers.map((id) => ({ id })), revocations: [], ...more },
    lock: null,
    peersCurrent: true,
    listeners: new Set(),
    relays: () => [],
  });

async function world() {
  const dir = mkdtempSync(join(tmpdir(), "rig-transport-"));
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_BYTES_ALPN, PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [station, rig] = await Promise.all([bind(), bind()]);
  const owner = person("pat");
  const rigCloud = cloudOf(rig.id(), [station.id()], { rig: { owner: "pat", owner_email: "pat@example.com", owner_name: "Pat", person: owner.genesis } });
  const stationCloud = cloudOf(station.id(), [], { rigs: [{ id: rig.id(), name: "build-box", owner: "pat", owner_email: "pat@example.com", owner_name: "Pat" }] });
  const sleep = () => new Promise<void>(() => {});
  const rigBus = new PeerBus({ sleep });
  const stationBus = new PeerBus({ sleep });
  // The rig's tasks (jobs/remote.ts there): whatever passes its grants.
  const ran: string[] = [];
  rigBus.on("describe", async () => ({ protocol: 1, tasks: true, ...made.described() }));
  rigBus.otherwise(async (_peer, request) => {
    ran.push(`${request.method} ${request.session ?? ""}`);
    return { ok: request.method };
  });
  // What the rig tells the station.
  const told: any[] = [];
  let hello!: () => void;
  const greeted = new Promise<void>((resolve) => (hello = resolve));
  stationBus.on(["rig.hello", "rig.changed"], async (peer, request) => {
    told.push({ peer, method: request.method, open: request.rig?.open, grants: request.rig?.grants.map((g: any) => g.request), ended: request.ended ?? null });
    hello();
    return { ok: true };
  });
  stationBus.otherwise(async (_peer, request) => ({ answered: request.method }));
  const made = new Rig({ data: dir, cloud: rigCloud, bus: rigBus, busy: () => false, stop: () => {}, running: () => [] });
  const serve = (endpoint: typeof station, cloud: any, bus: PeerBus) =>
    void (async () => {
      for (;;) {
        const conn = await endpoint.accept();
        if (!conn) return;
        void servePeer(conn, cloud, bus).catch(() => conn.close(0, "refused"));
      }
    })();
  serve(rig, rigCloud, rigBus);
  serve(station, stationCloud, stationBus);
  const at = (endpoint: typeof station) => (id: string) => ({ id, ips: [`127.0.0.1:${endpoint.sockets()[0]!.split(":").at(-1)}`] });
  const toRig = peerCall(station, stationCloud, at(rig));
  const toStation = peerCall(rig, rigCloud, at(station));
  stationBus.attach(toRig);
  return {
    station, rig, owner, stationCloud, rigCloud, made, ran, told, greeted, toRig, toStation,
    attachRig: () => rigBus.attach(toStation),
    grant: (request: string, session: string) => {
      const now = Math.floor(Date.now() / 1000);
      const timeout = { kind: "fixed" as const, seconds: 3600 };
      return owner.says("grant", { v: 1, sub: "pat", ws: "ws", rig: rig.id(), station: station.id(), session, chat: `CHAT/${session}`, request, title: "a chat", by: "lee@example.com", timeout, at: now, exp: latest(now, timeout) } as GrantBody);
    },
    close: async () => {
      await made.close();
      await Promise.all([station.close(), rig.close()]);
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

test("a station asks a rig as a station; what starts or writes something there needs the chat's grant", async () => {
  const w = await world();
  try {
    // How it is, and who may use it: asked with no grant.
    const described = await w.toRig(w.rig.id(), "ws", { method: "describe" });
    assert.deepEqual([described.tasks, described.sessions, described.chats, described.rig.owner, described.rig.open, described.rig.grants], [true, false, false, "pat", false, []]);
    // The transport's roster names the rigs beside the stations.
    assert.deepEqual((await w.toRig("", "ws", { method: "peers" })).rigs.map((r: any) => [r.id, r.name, r.owner]), [[w.rig.id(), "build-box", "pat"]]);

    const prepare = { method: "task.prepare", session: "s1", key: "k", spec: { name: "build", command: "make -j8" } };
    await assert.rejects(w.toRig(w.rig.id(), "ws", prepare), (e) => e instanceof Refused && /no grant of this station, which only runs tasks: ask for one with station_use/.test(e.message));
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "file.put", session: "s1", key: "k" }), Refused);
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "vault.run", session: "s1", id: "x", command: "deploy" }), Refused);
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "session.create" }), (e) => e instanceof Refused && /no session named/.test(e.message));
    assert.deepEqual(w.ran, [], "nothing reached its tasks");

    // The grant its person signed, brought by the chat's station with that person's lock.
    // (signed once: a grant's times are the clock's as it is signed, and a second one signed for the comparison was a
    // second later whenever the two straddled a second's edge)
    const granted = w.grant("r1", "s1");
    assert.deepEqual(await w.toRig(w.rig.id(), "ws", { method: "rig.grant", signed: granted, chain: w.owner.chain }), { until: granted.body.exp });
    assert.deepEqual(await w.toRig(w.rig.id(), "ws", prepare), { ok: "task.prepare" });
    await assert.rejects(w.toRig(w.rig.id(), "ws", { ...prepare, session: "s2" }), Refused, "the chat it names, and no other");
    // What it was told to run is kept on the rig, read back through a station.
    const log = await w.toRig(w.rig.id(), "ws", { method: "rig.log", limit: 10 });
    assert.deepEqual(log.commands.map((c: any) => [c.station, c.session, c.key, c.name, c.command, c.kind]), [[w.station.id(), "s1", "k", "build", "make -j8", "task"]]);

    // Given back: the chat starts nothing more, and still reads what it ran and stops it.
    assert.deepEqual(await w.toRig(w.rig.id(), "ws", { method: "rig.release", request: "r1" }), { released: true });
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "task.start", session: "s1", key: "k" }), Refused);
    for (const method of ["task.get", "task.log", "task.stop", "task.files", "file.get", "sync.changes", "session.close"]) {
      assert.deepEqual(await w.toRig(w.rig.id(), "ws", { method, session: "s1", key: "k" }), { ok: method });
    }
  } finally {
    await w.close();
  }
});

test("a rig asks nothing of a station: it tells of itself, and of the tasks it was sent", async () => {
  const w = await world();
  try {
    // On the mesh: every station of the workspace told it is here, with how it is.
    w.attachRig();
    await w.greeted;
    assert.deepEqual(w.told, [{ peer: w.rig.id(), method: "rig.hello", open: false, grants: [], ended: null }]);
    // What became of a task a station sent it, and of a command run with a secret.
    for (const method of ["task.changed", "vault.used", "vault.done"]) assert.deepEqual(await w.toStation(w.station.id(), "ws", { method }), { answered: method });
    // Nothing else: not how the station is, its chats, its files, its tasks.
    for (const method of ["describe", "session.read", "session.create", "task.prepare", "drive.list", "share.list", "search", "lock.person.get"]) {
      await assert.rejects(w.toStation(w.station.id(), "ws", { method, session: "s" }), (e) => e instanceof Refused && /a rig asks nothing of a station/.test(e.message), method);
    }
    // Another rig is no station to it: asked nothing, told nothing.
    await assert.rejects(w.toStation("ab".repeat(32), "ws", { method: "rig.hello" }), /not another station/);
  } finally {
    await w.close();
  }
});

test("in security mode a rig the control plane names is asked only what its person signed for it, until a station takes it", async () => {
  const w = await world();
  try {
    // The workspace locked on the station: the rig counts once `rigVouched` says its person signed for it.
    w.stationCloud.lock = { entries: [], state: { disabled: false, stations: new Map([[w.station.id(), {}]]) } };
    w.stationCloud.rigVouched = () => false;
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "describe" }), /not another station/);
    await assert.rejects(w.toRig(w.rig.id(), "ws", { method: "task.prepare", session: "s1", key: "k", spec: { command: "x" } }), /not another station/);
    assert.equal((await w.toRig("", "ws", { method: "peers" })).rigs, undefined, "and is none of the workspace's to its agents");
    assert.deepEqual(await w.toRig(w.rig.id(), "ws", { method: "rig.proof" }), { add: null });
    // One the plane does not name is asked nothing at all.
    await assert.rejects(w.toRig("ab".repeat(32), "ws", { method: "rig.proof" }), /not another station/);
    // What it tells is not heard either, until it is taken: a stranger's connection, ended as it comes.
    await assert.rejects(w.toStation(w.station.id(), "ws", { method: "rig.hello" }));
    w.stationCloud.rigVouched = () => true;
    assert.equal((await w.toRig(w.rig.id(), "ws", { method: "describe" })).rig.owner, "pat");
    assert.deepEqual(await w.toStation(w.station.id(), "ws", { method: "rig.hello" }), { ok: true });
  } finally {
    await w.close();
  }
});
