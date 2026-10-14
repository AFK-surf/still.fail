// The workspace lock as still.fail cloud keeps it (docs/workspace-lock.md, src/lock.ts): one chain, each entry following
// the last; carried to the stations on their presence sockets and to members; the devices that asked for credentials,
// for the owner to check; devices waiting to be confirmed. Whether an entry is signed by whom it may be is the
// stations' to check (station/test/lock.test.ts), not the cloud's.
import assert from "node:assert/strict";
import test from "node:test";
import { canonical, entryHash, shortCode, type LockEntry } from "../src/lock.ts";
import { harness } from "./harness.ts";

const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

/// An entry after `prev` (none: a genesis); the cloud does not read its signature.
async function entry(ws: string, prev: LockEntry | null, kind: string, body: unknown): Promise<LockEntry> {
  return { v: 1, ws, seq: prev ? prev.seq + 1 : 0, prev: prev ? await entryHash(prev) : null, at: 1000, kind, body, sig: { key: "ed25519:00", alg: "Ed25519", sig: "00" } };
}

test("the hash is the stations' and the core's (the same values in their tests)", async () => {
  const e = { v: 1, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字", exp: 1702592000 }, sig: {} } as LockEntry;
  assert.equal(await entryHash(e), "27e965570b626031e9640b781bdba3b5bb111ba2307b81bd9af8d14158f8578a");
  assert.equal(await shortCode("cd".repeat(32)), "UJV-HA9");
  assert.throws(() => canonical(0.5));
});

test("one chain per workspace: kept for members, carried to stations, healed by them", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const ws = (await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any).id as string;
    assert.equal((await bob("GET", `/v1/workspaces/${ws}/lock`)).status, 404, "members only");
    assert.deepEqual(await (await alice("GET", `/v1/workspaces/${ws}/lock`)).json(), { head: null, entries: [] });

    // A station, its presence socket and what it is told.
    const station = await key();
    const enrollment = await (await alice("POST", `/v1/workspaces/${ws}/enrollments`, { name: "studio" })).json() as any;
    await h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`), version: "0.1.0" }) });
    const ts = h.now();
    const socket = (await h.fetch("/v1/stations/connect", { headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`) } })).webSocket!;
    // What the station is told, as it comes: the next frame that `is` so (no deadline: it comes, or the test times out).
    const frames: any[] = [];
    let waiting: { is: (f: any) => boolean; resolve: (f: any) => void } | null = null;
    socket.addEventListener("message", (event) => {
      if (event.data === "pong") return;
      const f = JSON.parse(event.data as string);
      if (waiting?.is(f)) {
        waiting.resolve(f);
        waiting = null;
      } else frames.push(f);
    });
    socket.accept();
    const next = (is: (f: any) => boolean) => {
      const had = frames.findIndex(is);
      if (had >= 0) return Promise.resolve(frames.splice(0, had + 1).at(-1));
      return new Promise<any>((resolve) => (waiting = { is, resolve }));
    };
    const state = (lock: (l: any) => boolean) => next((f) => f.type === "state" && lock(f.lock));
    await state((l) => l === null);

    const g = await entry(ws, null, "genesis", { owner: "alice" });
    const e1 = await entry(ws, g, "member", { sub: "bob" });
    const e2 = await entry(ws, e1, "member", { sub: "carol" });
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [e1] })).status, 409, "no genesis");
    const head = (await (await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [g, e1] })).json() as any).head;
    assert.deepEqual(head, { seq: 1, hash: await entryHash(e1), genesis: await entryHash(g) });
    // The station hears the head, and asks for what it lacks.
    await state((l) => l?.hash === head.hash);
    socket.send(JSON.stringify({ type: "lock.get", after: 0 }));
    assert.deepEqual((await next((f) => f.type === "lock")).entries, [e1]);
    // What follows is kept; what it has, skipped; a fork, another genesis, or a gap, refused.
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [g, e1, e2] })).status, 200);
    const fork = await entry(ws, e1, "member", { sub: "mallory" });
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [fork] })).status, 409);
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [await entry(ws, null, "genesis", { owner: "x" })] })).status, 409);
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [{ ...(await entry(ws, e2, "member", {})), seq: 9 }] })).status, 409);
    assert.equal((await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [await entry("01HOTHERWSOTHERWSOTHERWSOT", e2, "member", {})] })).status, 400);
    // Lost (the owner cleared it): a station brings it back.
    assert.equal((await bob("DELETE", `/v1/workspaces/${ws}/lock`)).status, 404);
    assert.equal((await alice("DELETE", `/v1/workspaces/${ws}/lock`)).status, 200);
    await state((l) => l === null);
    socket.send(JSON.stringify({ type: "lock.put", entries: [g, e1, e2] }));
    await state((l) => l?.seq === 2);
    // Turned off, a new genesis starts another chain.
    const off = await entry(ws, e2, "disable", {});
    await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [off] });
    const g2 = await entry(ws, null, "genesis", { owner: "alice", again: true });
    assert.equal(((await (await alice("POST", `/v1/workspaces/${ws}/lock`, { entries: [g2] })).json()) as any).head.genesis, await entryHash(g2));
    assert.equal(((await (await alice("GET", `/v1/workspaces/${ws}`)).json()) as any).lock.seq, 0);
  } finally {
    await h.close();
  }
});

test("devices that asked for credentials, for the owner to check; devices waiting to be confirmed", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const ws = (await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any).id as string;
    const invite = await (await alice("POST", `/v1/workspaces/${ws}/invitations`, { role: "member", email: "bob@example.test" })).json() as any;
    await bob("POST", "/v1/invitations/accept", { token: invite.token });

    // An older client names only its endpoint; a newer one its base key, proving the endpoint is its own.
    const old = await key();
    const base = await key();
    const endpoint = await key();
    assert.equal((await bob("POST", `/v1/workspaces/${ws}/credential`, { device: old.id })).status, 200);
    const proof = await base.sign(`stillfail-lock-endpoint/1\0${ws}\0${endpoint.id}`);
    assert.equal((await bob("POST", `/v1/workspaces/${ws}/credential`, { device: endpoint.id, base: base.id, proof: await old.sign("x"), kind: "app" })).status, 400, "a proof by another key");
    assert.equal((await bob("POST", `/v1/workspaces/${ws}/credential`, { device: endpoint.id, base: base.id, proof, kind: "app", label: "bob's Mac" })).status, 200);
    assert.equal((await bob("GET", `/v1/workspaces/${ws}/devices`)).status, 403, "owners and admins");
    const devices = ((await (await alice("GET", `/v1/workspaces/${ws}/devices`)).json()) as any).devices;
    assert.deepEqual(devices.map((d: any) => [d.email, d.device, d.base, d.kind, d.label]).sort(), [
      ["bob@example.test", endpoint.id, base.id, "app", "bob's Mac"],
      ["bob@example.test", old.id, null, null, null],
    ].sort());

    // A device asks to be confirmed: its code, as both sides work it out; seen by owners and the member, gone once answered.
    const waiting = await key();
    const asked = await (await bob("POST", `/v1/workspaces/${ws}/lock/requests`, { base: waiting.id, kind: "web", label: "Chrome" })).json() as any;
    assert.equal(asked.code, await shortCode(waiting.id));
    assert.deepEqual(((await (await alice("GET", `/v1/workspaces/${ws}/lock/requests`)).json()) as any).requests.map((r: any) => [r.base, r.email, r.code]), [[waiting.id, "bob@example.test", asked.code]]);
    assert.equal((await alice("DELETE", `/v1/workspaces/${ws}/lock/requests/${waiting.id}`)).status, 200);
    assert.deepEqual(((await (await bob("GET", `/v1/workspaces/${ws}/lock/requests`)).json()) as any).requests, []);
  } finally {
    await h.close();
  }
});
