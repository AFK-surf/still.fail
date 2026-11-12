// The cloud's copy of a lock follows its stations (src/lock.ts `keepLockAt`, src/personal-lock.ts
// `extendPersonalKept`): what another keeper took (a station's `lock.put` with `keep`, a device's post with `keep`) is
// kept by the rules' fork choice, the chain gone by being what every reader reads and the rest kept aside, at most
// ASIDE_MOST; what a device brings itself goes on from the head or is refused, as before. Two entries after one parent:
// one signed by the owner, one by an admin, the rules choosing between them (whichever, `branches`).
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import { type Entry, lockChain, personChain, signedBytes, entryHash as stationHash } from "../../station/src/cloud/lock.ts";
import { entryHash, type LockEntry } from "../src/lock.ts";
import type { PersonalEntry } from "../src/personal-lock.ts";

/// The most a lock keeps off its chain (station/src/cloud/log-keep.ts, as the stations).
const ASIDE_MOST = 256;
import { harness } from "./harness.ts";
import { signer } from "./lock-signer.ts";

const member = (sub: string) => ({ sub, email: `${sub}@example.test`, role: "member" });

/// A lock of `ws` with alice the owner and bob an admin, each with an app that signs; `win` and `lose` two entries after
/// its genesis, as the rules choose between them.
async function branches(ws: string) {
  const owner = signer("alice");
  const admin = signer("bob");
  const g = await owner.genesis(ws, {
    members: [{ sub: "alice", email: "alice@example.test", role: "owner" }, { sub: "bob", email: "bob@example.test", role: "admin" }],
    devices: [{ id: owner.key.slice(8), sub: "alice", kind: "app", label: "", sign_key: owner.key }, { id: admin.key.slice(8), sub: "bob", kind: "app", label: "", sign_key: admin.key }],
  });
  const x = await owner.entry(ws, g, "member", member("carol"));
  const y = await admin.entry(ws, g, "member", member("dave"));
  const won = lockChain([g, x, y] as unknown as Entry[], entryHash(g)).hashes[1];
  const [win, lose] = won === entryHash(x) ? [x, y] : [y, x];
  return { owner, admin, g, win, lose, signerOf: (e: LockEntry) => (e === x ? owner : admin) };
}

/// A workspace of alice's with a station on its presence socket, and what it is told (as test/lock.test.ts).
async function world() {
  const h = await harness();
  const alice = h.as(await h.login("alice"));
  const ws = (await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any).id as string;
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = Buffer.from((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer).toString("hex");
  const signs = async (m: string) => Buffer.from(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(m))).toString("hex");
  const enrollment = await (await alice("POST", `/v1/workspaces/${ws}/enrollments`, { name: "willow" })).json() as any;
  await h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: enrollment.token, station: id, signature: await signs(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${id}`), version: "0.1.0" }) });
  const ts = h.now();
  const socket = (await h.fetch("/v1/stations/connect", { headers: { upgrade: "websocket", "x-stillfail-station": id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await signs(`stillfail-station-connect-v1:${h.origin}:${id}:${ts}`) } })).webSocket!;
  const frames: any[] = [];
  let waiting: { is: (f: any) => boolean; resolve: (f: any) => void } | null = null;
  socket.addEventListener("message", (event) => {
    if (event.data === "pong") return;
    const f = JSON.parse(event.data as string);
    if (waiting?.is(f)) {
      waiting.resolve(f);
      waiting = null;
    } else if (!waiting) frames.push(f);
  });
  socket.accept();
  const next = (is: (f: any) => boolean) => {
    const had = frames.findIndex(is);
    if (had >= 0) return Promise.resolve(frames.splice(0, had + 1).at(-1));
    frames.length = 0;
    return new Promise<any>((resolve) => (waiting = { is, resolve }));
  };
  const state = (lock: (l: any) => boolean) => next((f) => f.type === "state" && lock(f.lock));
  await state((l) => l === null);
  const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
  const directory = directories.get(directories.idFromName("primary"));
  const post = (entries: LockEntry[], keep?: boolean) => alice("POST", `/v1/workspaces/${ws}/lock`, { entries, ...(keep === undefined ? {} : { keep }) });
  const head = async () => ((await (await alice("GET", `/v1/workspaces/${ws}`)).json()) as any).lock;
  const chain = async () => ((await (await alice("GET", `/v1/workspaces/${ws}/lock`)).json()) as any).entries.map((e: LockEntry) => entryHash(e));
  return { h, alice, ws, socket, next, state, directory, post, head, chain };
}

test("a device's post of what a station took (`keep`), of a branch that wins: the copy moves to it, the entry it had aside; what follows is taken (it was 409)", async () => {
  const w = await world();
  try {
    const b = await branches(w.ws);
    assert.equal((await w.post([b.g, b.lose])).status, 200);
    // Brought by a device itself, a fork: refused as before, nothing kept.
    assert.equal((await w.post([b.g, b.win])).status, 409, "a plain post of a fork");
    const kept = await w.post([b.g, b.win], true);
    assert.equal(kept.status, 200, "kept: what a station took");
    assert.equal(((await kept.json()) as any).head.hash, entryHash(b.win));
    assert.deepEqual(await w.directory.lockAside(w.ws), [entryHash(b.lose)], "the entry it had, aside");
    assert.equal((await w.head()).hash, entryHash(b.win), "the view's head is the stations'");
    assert.deepEqual(await w.chain(), [b.g, b.win].map(entryHash), "GET /lock reads the chain gone by");
    const after = await b.owner.entry(w.ws, b.win, "member", member("erin"));
    assert.equal((await w.post([after])).status, 200, "an entry after the head that won");
    assert.equal((await w.head()).hash, entryHash(after));
  } finally {
    await w.h.close();
  }
});

test("a branch that loses, brought with `keep`: kept aside, the head unmoved; brought again, nothing changes", async () => {
  const w = await world();
  try {
    const b = await branches(w.ws);
    assert.equal((await w.post([b.g, b.win])).status, 200);
    assert.equal((await w.post([b.g, b.lose], true)).status, 200);
    assert.equal((await w.head()).hash, entryHash(b.win));
    assert.deepEqual(await w.directory.lockAside(w.ws), [entryHash(b.lose)]);
    assert.equal((await w.post([b.g, b.lose], true)).status, 200);
    assert.deepEqual(await w.directory.lockAside(w.ws), [entryHash(b.lose)], "once");
  } finally {
    await w.h.close();
  }
});

test("a station's `lock.put` with `keep` of the branch that won: its head named to every station; one from before (no `keep`) answered as before", async () => {
  const w = await world();
  try {
    const b = await branches(w.ws);
    assert.equal((await w.post([b.g, b.lose])).status, 200);
    await w.state((l) => l?.hash === entryHash(b.lose));
    // A station from before brings its chain: refused, the head said again.
    w.socket.send(JSON.stringify({ type: "lock.put", entries: [b.g, b.win] }));
    await w.state((l) => l?.hash === entryHash(b.lose));
    assert.deepEqual(await w.directory.lockAside(w.ws), []);
    w.socket.send(JSON.stringify({ type: "lock.put", entries: [b.g, b.win], keep: true }));
    await w.state((l) => l?.hash === entryHash(b.win));
    assert.equal((await w.head()).hash, entryHash(b.win));
    assert.deepEqual(await w.directory.lockAside(w.ws), [entryHash(b.lose)]);
  } finally {
    await w.h.close();
  }
});

test("a record from before (its chain alone) reads as before, and follows a station's branch as one of today's", async () => {
  const w = await world();
  try {
    const b = await branches(w.ws);
    await w.directory.keepLockUnchecked(w.ws, [b.g, b.lose].map((e) => ({ seq: e.seq, entry: e, hash: entryHash(e) })));
    assert.deepEqual(await w.chain(), [b.g, b.lose].map(entryHash));
    assert.equal((await w.head()).hash, entryHash(b.lose));
    assert.equal((await w.post([b.g, b.win], true)).status, 200);
    assert.deepEqual(await w.chain(), [b.g, b.win].map(entryHash));
  } finally {
    await w.h.close();
  }
});

test("bounded: at most ASIDE_MOST entries kept aside, the chain untouched", async () => {
  const w = await world();
  try {
    const b = await branches(w.ws);
    assert.equal((await w.post([b.g, b.win])).status, 200);
    // (entries after the genesis by the signer of the one that lost, each losing to the one that won there)
    const losers: LockEntry[] = [];
    for (let i = 0; losers.length < ASIDE_MOST + 8; i++) {
      const e = await b.signerOf(b.lose).entry(w.ws, b.g, "member", member(`m${i}`));
      if (lockChain([b.g, b.win, e] as unknown as Entry[], entryHash(b.g)).hashes[1] === entryHash(b.win)) losers.push(e);
    }
    // (a few at a time: a device's post is of 8 KB at most, api.ts `body`)
    for (let i = 0; i < losers.length; i += 8) {
      const r = await w.post(losers.slice(i, i + 8), true);
      assert.equal(r.status, 200, await r.text());
    }
    assert.equal((await w.directory.lockAside(w.ws)).length, ASIDE_MOST);
    assert.deepEqual(await w.chain(), [b.g, b.win].map(entryHash));
  } finally {
    await w.h.close();
  }
});

// ── a person's own lock ──

function key() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  return { id: `ed25519:${raw.toString("hex")}`, privateKey };
}
function personal(sub: string, by: ReturnType<typeof key>, seq: number, prev: string | null, kind: string, body: unknown): PersonalEntry {
  const e = { v: 1 as const, ws: `person:${sub}`, seq, prev, at: 1, kind, body };
  return { ...e, sig: { key: by.id, alg: "Ed25519", sig: sign(null, signedBytes(stationHash(e as unknown as Entry)), by.privateKey).toString("hex") } };
}
const ph = (e: PersonalEntry) => stationHash(e as unknown as Entry);

test("a person's own lock: a branch brought with `keep` is kept by the rules' fork choice (the one that lost does not replace the chain); without it, as before", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const sub = ((await (await alice("GET", "/v1/me")).json()) as any).user.sub as string;
    const a = key(), b = key(), c = key(), d = key();
    const first = personal(sub, a, 0, null, "genesis", { sub, device: { key: a.id, id: "aa".repeat(32), label: "a" } });
    const added = personal(sub, a, 1, ph(first), "device", { key: b.id, id: "bb".repeat(32), label: "b" });
    const x = personal(sub, a, 2, ph(added), "device", { key: c.id, id: "cc".repeat(32), label: "c" });
    const y = personal(sub, b, 2, ph(added), "device", { key: d.id, id: "dd".repeat(32), label: "d" });
    const won = personChain([first, added, x, y], ph(first)).hashes[2];
    const [win, lose] = won === ph(x) ? [x, y] : [y, x];
    const chain = async () => ((await (await alice("GET", "/v1/me/personal-lock")).json()) as any).entries.map(ph);
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [first, added, win] })).status, 200);
    // What a station took of the branch that lost: kept aside, the chain the one that won.
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [first, added, lose], keep: true })).status, 200);
    assert.deepEqual(await chain(), [first, added, win].map(ph), "the chain the rules choose");
    // ...and a station's of the one that won, once the other is the chain (as a device from before brought it): back.
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [first, added, lose] })).status, 200, "without keep, as before");
    assert.deepEqual(await chain(), [first, added, lose].map(ph));
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [first, added, win], keep: true })).status, 200);
    assert.deepEqual(await chain(), [first, added, win].map(ph));
  } finally {
    await h.close();
  }
});
