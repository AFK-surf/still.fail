// A person's own lock where a station's chain went another way than the one pinned (the stations go by the rules' fork
// choice, station/src/mesh/person-chains.ts): the device keeps what it was shown and pins the rules' choice among it
// (src/lock-keep.ts); a branch of the same lock is never taken for a lock begun anew (`replaced`), which a chain of
// another genesis still is. The lock: its genesis this device's (a), P putting a second device (b) on, then X and Y two
// entries after P: which wins is by the rules' second step (a `device.remove`, every device one vote), so no case turns
// on a hash.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, entryHash, signedBytes } from "../src/lock.ts";
import { PersonalLock } from "../src/personal-lock.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { hex, utf8 } from "../src/util.ts";

const SUB = "s1";
const STATION = "ws/st";
const short = (e: Entry) => entryHash(e).slice(0, 6);

/// A cloud that keeps one chain (down unless told).
function cloud() {
  const kept = { entries: [] as Entry[] };
  const say = { down: true };
  return {
    kept,
    say,
    call: (_sub: string, method: string, _path: string, body: unknown) =>
      Effect.suspend(() => say.down ? Effect.fail(new CoreError("network", "the cloud is down")) : Effect.sync(() => {
        if (method === "GET") return { entries: kept.entries };
        const adding = (body as { entries: Entry[] }).entries;
        kept.entries = adding[0]!.seq === 0 ? adding : [...kept.entries.slice(0, adding[0]!.seq), ...adding];
        return { entries: kept.entries };
      })) as Effect.Effect<unknown, CoreError>,
  };
}

/// The person's stations: the chains a read answers (`chains`, one a station), each brought chain taken (kept as the one
/// chain where `follow`); `taking`: what lands on the device once a station took what it was brought and before its
/// answer does (a read made meanwhile, answered first), once.
function stations() {
  const say = { chains: [] as Entry[][], follow: true, taking: null as (() => Effect.Effect<void, CoreError>) | null };
  return {
    say,
    env: {
      read: (_sub: string, _at?: string) => Effect.sync(() => say.chains.map((c) => [...c])),
      bring: (_sub: string, chain: Entry[]) =>
        Effect.suspend(() => {
          if (say.follow) say.chains = [chain];
          const taking = say.taking;
          say.taking = null;
          return taking === null ? Effect.succeed(1) : Effect.map(taking(), () => 1);
        }),
    },
  };
}

function device(c: ReturnType<typeof cloud>, name: string, at: ReturnType<typeof stations>, host = new FakeHost()) {
  const id = name.charCodeAt(0).toString(16).repeat(32);
  host.appKeys = true;
  host.randomBytes = (b: Uint8Array) => void b.fill(name.charCodeAt(0));
  const sealed = new Map<string, Uint8Array>();
  host.secureSet = (key: string, value: Uint8Array) => Effect.sync(() => void sealed.set(key, value));
  host.secureGet = (key: string) => Effect.succeed(sealed.get(key) ?? new Uint8Array(32).fill(name.charCodeAt(0)));
  host.secureAsk = () => Effect.void;
  const runner = new Runner(host.time.clock);
  const lock = new PersonalLock({ host, runner, cloud: c.call, device: () => Effect.succeed(id), label: () => name, changed: () => {}, stations: at.env });
  return { host, runner, lock, id };
}

/// An entry of `sub`'s lock after `chain`, signed with the seed of the device named `by`.
function signed(chain: Entry[], by: string, kind: string, body: unknown, at = 1_800_000_000): Entry {
  const seed = new Uint8Array(32).fill(by.charCodeAt(0));
  const last = chain.at(-1);
  const e = { v: 1 as const, ws: `person:${SUB}`, seq: chain.length, prev: last ? entryHash(last) : null, at, kind, body };
  return { ...e, sig: { key: `ed25519:${hex(ed25519.getPublicKey(seed))}`, alg: "Ed25519" as const, sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } };
}

const other = (n: string) => ({ key: `ed25519:${n.repeat(32)}`, id: n.repeat(32), label: n });
const grantBody = { station: STATION, request: "p1", session: "sess", chat: "chat", scope: "hour" as const, exp: 2_000_000_000 };

/// `xWins`: X takes b off (a removal) and Y puts c on (X wins); else the other way round. X is signed here (a's
/// `addDevice`/`removeDevice`), Y and Z as another device of a's would.
async function setUp(xWins = false) {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  await a.runner.run(a.lock.signGrant(SUB, grantBody, "why"));
  await a.runner.run(a.lock.addDevice(SUB, other("22"), "why"));
  const [g, P] = a.lock.entries(SUB) as [Entry, Entry];
  const remove = (chain: Entry[]) => signed(chain, "a", "device.remove", { key: other("22").key }, 1_800_000_100);
  const put = (chain: Entry[]) => signed(chain, "a", "device", other("33"), 1_800_000_200);
  if (xWins) await a.runner.run(a.lock.removeDevice(SUB, other("22").key, "why"));
  else await a.runner.run(a.lock.addDevice(SUB, other("33"), "why"));
  const X = a.lock.entries(SUB)[2]!;
  const Y = xWins ? put([g, P]) : remove([g, P]);
  const Z = signed([g, P, Y], "a", "device", other("44"), 1_800_000_300);
  const names = new Map([g, P, X, Y, Z].map((e, i) => [entryHash(e), ["g", "P", "X", "Y", "Z"][i]!]));
  const said = (es: readonly Entry[] | undefined | null) => (es ?? []).map((e) => names.get(entryHash(e)) ?? short(e)).join(",");
  const keyOf = (prefix: string) => `${prefix}${hex(utf8(SUB))}`;
  const stored = (prefix: string) => {
    const v = a.host.storage.get(keyOf(prefix));
    return v === undefined ? undefined : JSON.parse(new TextDecoder().decode(v));
  };
  const pins = (chain: Entry[], aside: Entry[], why: string) => {
    assert.equal(said(a.lock.entries(SUB)), said(chain), `${why}: pinned`);
    assert.equal(a.lock.standing(SUB), "member", `${why}: standing`);
    assert.equal(said(stored("personal-lock-")), said(chain), `${why}: stored`);
    assert.equal(said(stored("personal-lock-aside-")), said(aside), `${why}: kept aside`);
  };
  return { c, st, a, g, P, X, Y, Z, said, stored, pins, keyOf };
}

test("a station's chain that moved off the entry pinned for one that wins is pinned, with what came after it", async () => {
  const w = await setUp();
  w.pins([w.g, w.P, w.X], [], "X signed here");
  w.st.say.chains = [[w.g, w.P, w.Y, w.Z]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.Y, w.Z], [w.X], "after the read");
  assert.ok(!w.a.lock.chain(SUB)!.devices.has(other("22").key), "the removal gone by");
});

test("a station at the same place as the entry pinned, on one that wins, told in a refusal: the device moves to it", async () => {
  const w = await setUp();
  await w.a.runner.run(w.a.lock.heardFrom(SUB, [[w.g, w.P, w.Y]]));
  w.pins([w.g, w.P, w.Y], [w.X], "after the refusal");
});

test("a station on an entry that loses to the one pinned: the device stays and keeps it aside; read again, nothing changes", async () => {
  const w = await setUp(true);
  w.st.say.follow = false;
  w.st.say.chains = [[w.g, w.P, w.Y]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.X], [w.Y], "after the read");
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.X], [w.Y], "read again");
  w.st.say.chains = [[w.g, w.P, w.Y, w.Z]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.X], [w.Y, w.Z], "the station went on after Y");
});

for (const how of ["together", "A then S", "S then A"] as const)
  test(`two stations on two branches, read ${how}: the rules' choice is pinned`, async () => {
    const w = await setUp();
    w.st.say.follow = false;
    const onX = [w.g, w.P, w.X], onY = [w.g, w.P, w.Y, w.Z];
    for (const chains of how === "together" ? [[onX, onY]] : how === "A then S" ? [[onX], [onY]] : [[onY], [onX]]) {
      w.st.say.chains = chains;
      await w.a.runner.run(w.a.lock.refresh(SUB));
    }
    w.pins(onY, [w.X], `read ${how}`);
  });

test("a station behind, or one whose entries do not verify, changes nothing; a lock of another genesis is one begun anew", async () => {
  const w = await setUp();
  w.st.say.follow = false;
  w.st.say.chains = [[w.g, w.P]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.X], [], "behind");
  const bad = { ...w.Y, body: { key: other("55").key } } as Entry;
  w.st.say.chains = [[w.g, w.P, bad, signed([w.g, w.P, bad], "a", "device", other("44"))]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  w.pins([w.g, w.P, w.X], [], "entries that do not verify");
  // Begun anew on another device (z): the person is told, as before.
  const anew = signed([], "z", "genesis", { sub: SUB, device: { key: `ed25519:${hex(ed25519.getPublicKey(new Uint8Array(32).fill(122)))}`, id: "7a".repeat(32), label: "z" } });
  w.st.say.chains = [[anew]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  assert.equal(w.a.lock.standing(SUB), "replaced");
  assert.equal(w.said(w.a.lock.entries(SUB)), "g,P,X");
});

test("an entry signed here while a read moved the chain pinned to another branch loses its place there: the branch pinned, the entry signed again after it (personal-lock-signs-again.test.ts)", async () => {
  const w = await setUp();
  // A read lands as a station takes the entry brought: the stations moved to Y.
  w.st.say.taking = () => Effect.andThen(Effect.sync(() => { w.st.say.follow = false; w.st.say.chains = [[w.g, w.P, w.Y, w.Z]]; }), w.a.lock.refresh(SUB));
  const out = await w.a.runner.run(Effect.result(w.a.lock.addDevice(SUB, other("66"), "why")));
  assert.equal(out._tag, "Success", JSON.stringify(out));
  const pinned = w.a.lock.entries(SUB);
  assert.equal(w.said(pinned.slice(0, 4)), "g,P,Y,Z");
  assert.equal(pinned.length, 5);
  assert.deepEqual(pinned[4]!.body, other("66"));
  assert.equal(w.a.lock.standing(SUB), "member");
});

test("a device whose own entry lost its place is outside until it is put on again", async () => {
  // b's own entry (a put it on after c) loses to a's removal of c at the same place.
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  await a.runner.run(a.lock.signGrant(SUB, grantBody, "why"));
  await a.runner.run(a.lock.addDevice(SUB, other("22"), "why"));
  const b = device(c, "b", st);
  const bKey = await b.runner.run(b.lock.makeKey());
  const whole = await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: b.id, label: "b" }, "why"));
  await b.runner.run(b.lock.joined(SUB, whole));
  await b.runner.run(b.lock.refresh(SUB));
  assert.equal(b.lock.standing(SUB), "member");
  st.say.follow = false;
  const [g, Pc] = whole as [Entry, Entry];
  st.say.chains = [[g, Pc, signed([g, Pc], "a", "device.remove", { key: other("22").key }, 1_800_000_200)]];
  await b.runner.run(b.lock.refresh(SUB));
  assert.equal(b.lock.standing(SUB), "outside");
  assert.equal(b.lock.entries(SUB).at(-1)!.kind, "device.remove");
});

test("what is pinned is stored as before (the chain, an array from the genesis), what is aside beside it; one stored before reads as before", async () => {
  const w = await setUp();
  w.st.say.chains = [[w.g, w.P, w.Y, w.Z]];
  await w.a.runner.run(w.a.lock.refresh(SUB));
  const chain = w.stored("personal-lock-");
  assert.ok(Array.isArray(chain) && chain[0].seq === 0 && chain[0].prev === null, "the chain, as a reader from before reads it");
  assert.deepEqual(chain, JSON.parse(JSON.stringify([w.g, w.P, w.Y, w.Z])));
  assert.deepEqual(w.stored("personal-lock-aside-"), JSON.parse(JSON.stringify([w.X])));
  // A device whose store has the chain alone (a core from before wrote it): read as before.
  const host = new FakeHost();
  host.storage.set(w.keyOf("personal-lock-"), utf8(JSON.stringify([w.g, w.P, w.X])));
  host.storage.set("personal-signer-id", w.a.host.storage.get("personal-signer-id")!);
  const st = stations();
  st.say.chains = [[w.g, w.P, w.X]];
  const again = device(cloud(), "a", st, host);
  await again.runner.run(again.lock.refresh(SUB));
  assert.equal(w.said(again.lock.entries(SUB)), "g,P,X");
  assert.equal(again.lock.standing(SUB), "member");
  // Then a branch that wins comes: kept as on any device.
  st.say.chains = [[w.g, w.P, w.Y, w.Z]];
  await again.runner.run(again.lock.refresh(SUB));
  assert.equal(w.said(again.lock.entries(SUB)), "g,P,Y,Z");
});
