// Every person in safe mode comes to have a lock of their own (views/lock.ts `ownLockFor`, `ownStandings`,
// `approvedIn`, `vouchersIn`, `personalStations`; personal-lock.ts `beginQuietly`, `#addApproved`, `#putOnBy`), nobody
// asked: the person's devices trusted only in workspaces' locks say there the key they would be on it with; the one to
// begin (first in every lock of theirs, the smallest id of such) begins it once each other one that came lately said
// its key and every station of theirs seen lately answered; it puts on it those below it in their lineage, matched by
// the key that signed; each takes the lock a device up its lineage signed; and then the workspace's lock is bound to
// it. A member's devices as an owner's. Never by a device id alone, never one taken off again, never a chain other
// than the one pinned, never begun where the key was made before (its seed is not in hand).
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import type { Inner } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Signer, entryHash, next, signedBytes } from "../src/lock.ts";
import { type PersonalEnv, PersonalLock, checkChain } from "../src/personal-lock.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { FakeHost } from "../src/testing.ts";
import { hex } from "../src/util.ts";
import { ancestors, approvedIn, bindPerson, fold, held, ownLockEnv, ownLockFor, ownStandings, personalStations, read, signerOf, vouchersIn } from "../src/views/lock.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";

const SUB = "s1";
const S2 = "s2";
const NOW = 2_000_000_000;

/// A key a workspace's lock knows a device by, of nobody's on a core here.
type Key = { id: string; signBytes(b: Uint8Array): string };
const wsKey = (n: number): Key => {
  const seed = new Uint8Array(32).fill(n);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b) => hex(ed25519.sign(b, seed)) };
};
/// `chain` and one entry more, signed with `by`.
function then(chain: Entry[], by: Key, kind: string, body: unknown, at = 2000): Entry[] {
  const last = chain[chain.length - 1]!;
  const e = next(last.ws, { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, at, kind, body);
  return [...chain, { ...e, sig: { key: by.id, alg: "Ed25519", sig: by.signBytes(signedBytes(entryHash(e))) } }];
}
/// An app device of `sub`'s in a workspace's lock, signing with `key`.
const app = (id: string, label: string, key: Key, more: Record<string, unknown> = {}, sub = SUB) => ({ id, sub, kind: "app", label, sign_key: key.id, ...more });
const personKey = (b: string) => `ed25519:${b.repeat(32)}`;
/// The key a device made by `device(name)` is on its person's lock with (its host's random bytes are its name's).
const keyOf = (name: string) => `ed25519:${hex(ed25519.getPublicKey(new Uint8Array(32).fill(name.charCodeAt(0))))}`;

/// A cloud that keeps one chain of a person's lock, as cloud/src/personal-lock.ts does.
function personCloud() {
  const kept = { entries: [] as Entry[] };
  return {
    kept,
    call: (_sub: string, method: string, _path: string, body: unknown) =>
      Effect.sync(() => {
        if (method === "GET") return { entries: kept.entries };
        const adding = (body as { entries: Entry[] }).entries;
        kept.entries = adding[0]!.seq === 0 ? adding : [...kept.entries.slice(0, adding[0]!.seq), ...adding];
        return { entries: kept.entries };
      }) as Effect.Effect<unknown, CoreError>,
  };
}

/// The person's stations, as station/src/mesh/person-chains.ts keeps their lock: each chain by its first entry, the
/// longer taken where it goes on from the one kept, one at odds refused. `answered`: whether every one of them
/// answered a read this run (views/lock.ts `personalStations` `answered`).
function stations(answeredAtFirst = true) {
  const kept = new Map<string, Entry[]>();
  const root = (c: Entry[]) => JSON.stringify(c[0]);
  const answered = { value: answeredAtFirst };
  return {
    kept,
    root,
    answered,
    env: {
      read: (_sub: string, _at?: string) => Effect.sync(() => [...kept.values()]),
      bring: (_sub: string, chain: Entry[]) =>
        Effect.suspend(() => {
          const had = kept.get(root(chain)) ?? [];
          const [short, long] = had.length <= chain.length ? [had, chain] : [chain, had];
          if (!short.every((e, i) => JSON.stringify(e) === JSON.stringify(long[i]))) return Effect.fail(new CoreError("lock_refused", "at odds with the one kept", 409));
          kept.set(root(chain), long);
          return Effect.succeed(1);
        }),
      answered: (_sub: string) => answered.value,
    },
  };
}

/// A device of the person's with a lock of theirs only (no core): its id by its name, its host's secure storage
/// FakeHost's (each read that asks the person noted in `host.secureAsked`), its hooks as `hooks` says for its id.
const idOf = (name: string) => name.charCodeAt(0).toString(16).repeat(32);
function device(name: string, c: ReturnType<typeof personCloud>, st: ReturnType<typeof stations>, hooks: (id: string) => Partial<PersonalEnv> = () => ({})) {
  const id = idOf(name);
  const host = new FakeHost();
  host.appKeys = true;
  // (each device's keys its own)
  host.randomBytes = (b: Uint8Array) => void b.fill(name.charCodeAt(0));
  const runner = new Runner(host.time.clock);
  const lock = new PersonalLock({ host, runner, cloud: c.call, device: () => Effect.succeed(id), label: () => name, changed: () => {}, stations: st.env, ...hooks(id) });
  return { host, runner, lock, id };
}
const idsOn = (entries: Entry[], sub = SUB) => [...(checkChain(entries, sub)?.devices.values() ?? [])].map((d) => d.id).sort();
/// What `approved` would be given of a chain (personal-lock.ts `#addApproved`).
const chainOf = (signers: string[], signed: string[], ids: string[] = [], keys: string[] = []) => ({ signers: new Set(signers), signed: new Set(signed), ever: { ids: new Set(ids), keys: new Set(keys) } });

/// The testing core as this person's device ME, its lock of their own a PersonalLock at the person's stations (`st`)
/// and cloud (`pc`), wired to the workspaces' locks as core.ts wires it. `locks`: the workspaces' locks (ME the
/// genesis's signer in `ws` unless said); `prepare`, what is put in them (and which devices came lately) before both
/// workspaces (ws, w2) are read, as they are before it returns: read, this device does its part, and is not to say its
/// key before a test has put what it puts. The stations answer as `st.answered` says, not at first.
type Prepare = (at: { A: Key; put: (by: Key, kind: string, body: unknown, ws?: string) => void; cloud: { devices: Map<string, Record<string, unknown>[]> } }) => void;
async function first(locks?: (me: Key, keys: unknown) => Record<string, Entry>, prepare?: Prepare) {
  const g = grant();
  let signer!: Signer;
  const r = await rig((me) => {
    signer = me;
    const key: Key = { id: me.id, signBytes: (b) => me.signBytes(b) };
    return locks ? locks(key, g.keys) : { ws: genesis("ws", me, true, [], g.keys, ME) };
  });
  const inner = r.core.inner;
  const st = stations(false);
  const pc = personCloud();
  const personal = new PersonalLock({ host: r.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {}, signKey: () => signerOf(inner), cloud: pc.call, stations: st.env, ...ownLockEnv(inner) });
  inner.adb.personal = () => personal;
  const A: Key = { id: signer.id, signBytes: (b) => signer.signBytes(b) };
  const chain = (ws = "ws") => r.cloud.chains.get(ws)!;
  const put = (by: Key, kind: string, body: unknown, ws = "ws") => r.cloud.chains.set(ws, then(chain(ws), by, kind, body, Math.floor(r.host.nowMs() / 1000)));
  const until = async (ok: () => boolean, what: string) => {
    await r.host.time.passUntil(10000, () => ok());
    assert.ok(ok(), what);
  };
  /// An effect run on the core's runner, on its clock, waited for.
  const run = async <X>(e: Effect.Effect<X, unknown>): Promise<X | undefined> => {
    const out: { done: boolean; value?: X } = { done: false };
    inner.runner.fork(Effect.ensuring(Effect.map(Effect.ignore(Effect.map(e, (v) => void (out.value = v))), () => {}), Effect.sync(() => void (out.done = true))));
    await until(() => out.done, "no answer");
    return out.value;
  };
  prepare?.({ A, put, cloud: r.cloud });
  // (the other workspace first: read after, this device would for a moment see another as the one to begin there)
  await run(read(inner, "w2"));
  await run(read(inner, "ws"));
  assert.ok(held(inner, "ws") !== null && held(inner, "w2") !== null, "both workspaces' locks read");
  const standing = (ws = "ws") => ownStandings(chain(ws), SUB, NOW);
  /// Whatever is put meanwhile read, the stations answering, and this device's part done.
  const go = async (...wss: string[]) => {
    st.answered.value = true;
    for (const ws of wss.length > 0 ? wss : ["ws"]) await run(read(inner, ws));
    await run(ownLockFor(inner, "ws"));
  };
  // (what the start asked of the host, if anything: nothing more is to be asked from here)
  const asked = r.host.secureAsked.length;
  return { r, inner, st, pc, personal, A, chain, put, until, run, standing, go, asked };
}

test("the owner's devices: B (put in by A) and C (put in by B) say their keys, A begins with them on it, they take it, and it is bound; nobody asked", async () => {
  const kB = wsKey(2), kC = wsKey(3);
  const B = idOf("b"), C = idOf("c");
  const s = await first(undefined, ({ A, put }) => {
    put(A, "device", app(B, "b", kB));
    put(kB, "device", app(C, "c", kC));
    put(kB, "device", app(B, "b", kB, { person_key: keyOf("b") }));
    put(kC, "device", app(C, "c", kC, { person_key: keyOf("c") }));
  });
  const vouched = (id: string) => ({ vouchers: () => vouchersIn([ownStandings(s.chain(), SUB, NOW)], SUB, id) });
  const b = device("b", s.pc, s.st, vouched);
  const c = device("c", s.pc, s.st, vouched);
  try {
    assert.equal(await b.runner.run(b.lock.makeKey()), keyOf("b"));
    assert.equal(await c.runner.run(c.lock.makeKey()), keyOf("c"));
    assert.equal(s.st.kept.size, 0, "nothing begun while the stations have not answered");
    assert.deepEqual([ME, b.id, c.id].map((id) => s.standing().devices.get(id)?.by), [null, ME, b.id], "B put in by A, C by B");
    await s.go();
    // Begun here, B and C on it (C after B, which put it in), and this device says its own key there next.
    await s.until(() => s.standing().devices.get(ME)?.said != null, "this device said its key there");
    const mine = s.personal.entries(SUB);
    assert.equal(mine[0]!.kind, "genesis");
    assert.equal(mine.filter((e) => e.kind === "genesis").length, 1, "begun once");
    assert.deepEqual(idsOn(mine), [ME, b.id, c.id].sort());
    assert.equal(s.standing().devices.get(ME)?.said, [...checkChain(mine, SUB)!.devices.values()].find((d) => d.id === ME)?.key);
    assert.deepEqual([...s.personal.signKeys(SUB)].map(([id, d]) => [id, d.sign_key]).sort(), [[ME, s.A.id], [b.id, kB.id], [c.id, kC.id]].sort(), "with the keys they sign the workspaces' locks with");
    assert.deepEqual([...s.st.kept.values()], [mine], "at the person's stations");
    // B and C take it as they hear it of the stations: A, up the lineage of each, signed it (C was put on by A, not B).
    await b.runner.run(b.lock.refresh(SUB));
    await c.runner.run(c.lock.refresh(SUB));
    assert.equal(b.lock.standing(SUB), "member");
    assert.equal(c.lock.standing(SUB), "member");
    assert.deepEqual(b.lock.entries(SUB), mine);
    assert.deepEqual(c.lock.entries(SUB), mine);
    // Every app device of theirs on it: the workspace's lock is bound to it.
    await s.run(bindPerson(s.inner, "ws"));
    await s.run(read(s.inner, "ws"));
    await s.until(() => fold(held(s.inner, "ws")!.entries).persons.get(SUB) === s.personal.root(SUB), "bound");
    assert.equal(s.r.host.secureAsked.length, s.asked, "nothing asked here");
    assert.deepEqual([b.host.secureAsked, c.host.secureAsked], [[], []], "nor there");
  } finally {
    b.runner.shutdown();
    c.runner.shutdown();
  }
});

test("bound before the one that began said its key: it says it there all the same, and the one it put on takes the lock", async () => {
  const kB = wsKey(2);
  const B = idOf("b");
  const s = await first(undefined, ({ A, put }) => {
    put(A, "device", app(B, "b", kB));
    put(kB, "device", app(B, "b", kB, { person_key: keyOf("b") }));
  });
  const b = device("b", s.pc, s.st, (id) => ({ vouchers: () => vouchersIn([ownStandings(s.chain(), SUB, NOW)], SUB, id) }));
  try {
    assert.equal(await b.runner.run(b.lock.makeKey()), keyOf("b"));
    // Begun here with B on it, and the workspace's lock bound to it before this device's key was said there (as when
    // the entry that binds is taken first, and the one saying the key refused for it): written as the cloud keeps it.
    s.st.answered.value = true;
    assert.equal(await s.run(s.personal.beginQuietly(SUB)), true);
    assert.deepEqual(idsOn(s.personal.entries(SUB)), [ME, B].sort());
    s.put(s.A, "person", { sub: SUB, person: s.personal.root(SUB) });
    assert.equal(s.standing().devices.get(ME)?.said ?? null, null, "not said yet");
    // B hears the chain and cannot know it theirs: no key said up its lineage signed it.
    await b.runner.run(b.lock.refresh(SUB));
    assert.equal(b.lock.standing(SUB), "outside");
    await s.go();
    assert.equal(fold(held(s.inner, "ws")!.entries).persons.get(SUB), s.personal.root(SUB), "bound, as read");
    await s.until(() => s.standing().devices.get(ME)?.said != null, "this device said its key there, bound as it is");
    await b.runner.run(b.lock.refresh(SUB));
    assert.equal(b.lock.standing(SUB), "member", "and the one it put on takes the lock");
    assert.equal(s.r.host.secureAsked.length, s.asked, "nothing asked here");
    assert.deepEqual(b.host.secureAsked, [], "nor there");
  } finally {
    b.runner.shutdown();
  }
});

test("the one to begin waits while a device of theirs that came lately has not said its key; begins once it did, or where it is not listed as come; one first but not come lately is passed over", async () => {
  const kB = wsKey(2), kC = wsKey(3);
  const seenRow = (base: string) => ({ sub: SUB, email: "a@x.com", device: base, base, kind: "app", label: "x", first_seen: 1, last_seen: 1 });
  {
    const B = idOf("b"), C = idOf("c");
    const s = await first(undefined, ({ A, put, cloud }) => {
      put(A, "device", app(B, "b", kB));
      put(A, "device", app(C, "c", kC));
      put(kC, "device", app(C, "c", kC, { person_key: keyOf("c") }));
      cloud.devices.set("ws", [seenRow(B), seenRow(C)]);
    });
    const b = device("b", s.pc, s.st);
    const c = device("c", s.pc, s.st);
    try {
      const pB = await b.runner.run(b.lock.makeKey());
      await c.runner.run(c.lock.makeKey());
      await s.go();
      await s.r.host.time.pass(2_000);
      assert.equal(s.st.kept.size, 0, "not begun while B, come lately, has not said its key");
      assert.equal(s.personal.standing(SUB), "none");
      assert.equal(s.personal.mayBeginQuietly(SUB), true, "nor its key made: it may still begin");
      assert.equal(s.chain().length, 4, "nor its own key said meanwhile");
      // B says it: begun, with both on it.
      s.put(kB, "device", app(b.id, "b", kB, { person_key: pB }));
      await s.go();
      await s.until(() => s.standing().devices.get(ME)?.said != null, "begun, and its key said");
      assert.equal(s.personal.standing(SUB), "member");
      assert.deepEqual(idsOn(s.personal.entries(SUB)), [ME, b.id, c.id].sort());
      assert.equal(s.r.host.secureAsked.length, s.asked);
    } finally {
      b.runner.shutdown();
      c.runner.shutdown();
    }
  }
  {
    // B never said its key, and the stations do not list it as come (in SEEN_SECS): begun without it.
    const C = idOf("c");
    const s = await first(undefined, ({ A, put, cloud }) => {
      put(A, "device", app(idOf("b"), "b", kB));
      put(A, "device", app(C, "c", kC));
      put(kC, "device", app(C, "c", kC, { person_key: keyOf("c") }));
      cloud.devices.set("ws", [seenRow(C)]);
    });
    const c = device("c", s.pc, s.st);
    try {
      await s.go();
      await s.until(() => s.standing().devices.get(ME)?.said != null, "begun, and its key said");
      assert.equal(s.personal.standing(SUB), "member");
      assert.deepEqual(idsOn(s.personal.entries(SUB)), [ME, c.id].sort(), "B, with no key said, not on it");
      assert.equal(s.r.host.secureAsked.length, s.asked);
    } finally {
      c.runner.shutdown();
    }
  }
  // X, an old machine of theirs, signed the genesis (first, the smaller id) with this device in it.
  const kX = wsKey(0x11);
  const X = "11".repeat(32);
  const withX = (me: Key, keys: unknown) => ({ ws: genesis("ws", kX, true, [], keys, X, [app(ME, "this", me)]) });
  {
    // Not come to the stations lately: passed over, this device the one to begin.
    const s = await first(withX, ({ cloud }) => cloud.devices.set("ws", [seenRow(ME)]));
    assert.equal(s.standing().devices.get(ME)?.since, s.standing().devices.get(X)?.since, "both the genesis's");
    await s.go();
    await s.until(() => s.standing().devices.get(ME)?.said != null, "begun, and its key said");
    assert.equal(s.personal.standing(SUB), "member");
    assert.deepEqual(idsOn(s.personal.entries(SUB)), [ME], "X, with no key said, not on it");
    assert.equal(s.r.host.secureAsked.length, s.asked);
  }
  {
    // Come lately: X is the one to begin, and this device only says its key.
    const s = await first(withX, ({ cloud }) => cloud.devices.set("ws", [seenRow(ME), seenRow(X)]));
    await s.go();
    await s.until(() => s.standing().devices.get(ME)?.said != null, "its key said");
    assert.equal(s.st.kept.size, 0, "not begun here");
    assert.equal(s.personal.standing(SUB), "none");
    assert.equal(s.personal.mayBeginQuietly(SUB), false, "its key made, as it said it");
    assert.equal(s.r.host.secureAsked.length, s.asked);
  }
});

test("a member's devices, the first put in by an owner's device: it begins, puts on those it approved and those they approved, and they take it; nobody asked", async () => {
  const pc = personCloud();
  const st = stations();
  const kA = wsKey(1), kF = wsKey(6), kG = wsKey(7), kH = wsKey(8);
  const A = "a1".repeat(32);
  let ch: Entry[] = [];
  const vouched = (id: string) => ({ vouchers: (sub: string) => vouchersIn([ownStandings(ch, sub, NOW)], sub, id) });
  const f = device("f", pc, st, (id) => ({ signKey: () => kF.id, approved: (sub, chain) => approvedIn([ownStandings(ch, sub, NOW)], sub, { id, signKey: kF.id }, chain) }));
  const g = device("g", pc, st, vouched);
  const h = device("h", pc, st, vouched);
  try {
    // The owner's device (A, s1's) puts F in as s2's first; F puts G in, G puts H in; each says its key.
    ch = [genesis("ws", kA, true, [], {}, A)];
    ch = then(ch, kA, "device", app(f.id, "f", kF, {}, S2));
    ch = then(ch, kF, "device", app(g.id, "g", kG, {}, S2));
    ch = then(ch, kG, "device", app(h.id, "h", kH, {}, S2));
    ch = then(ch, kF, "device", app(f.id, "f", kF, { person_key: keyOf("f") }, S2));
    ch = then(ch, kG, "device", app(g.id, "g", kG, { person_key: keyOf("g") }, S2));
    ch = then(ch, kH, "device", app(h.id, "h", kH, { person_key: keyOf("h") }, S2));
    const own = ownStandings(ch, S2, NOW);
    assert.deepEqual([own.devices.get(f.id)?.by, own.devices.get(f.id)?.bySub], [A, SUB], "F put in by someone else");
    assert.deepEqual(ancestors(own, h.id).map((d) => d.id), [g.id, f.id]);
    // F begins s2's lock: G and H are put on it, with the keys they sign the workspace's lock with.
    await f.runner.run(f.lock.refresh(S2));
    assert.equal(await f.runner.run(f.lock.beginQuietly(S2)), true);
    const mine = f.lock.entries(S2);
    assert.deepEqual(idsOn(mine, S2), [f.id, g.id, h.id].sort());
    assert.deepEqual([...f.lock.signKeys(S2)].map(([id, d]) => [id, d.sign_key]).sort(), [[f.id, kF.id], [g.id, kG.id], [h.id, kH.id]].sort());
    // G and H take it: F, up the lineage of each, signed it.
    assert.deepEqual(vouchersIn([own], S2, h.id), new Set([keyOf("g"), keyOf("f")]));
    assert.equal(await g.runner.run(g.lock.makeKey()), keyOf("g"));
    assert.equal(await h.runner.run(h.lock.makeKey()), keyOf("h"));
    await g.runner.run(g.lock.refresh(S2));
    await h.runner.run(h.lock.refresh(S2));
    assert.deepEqual([g.lock.standing(S2), h.lock.standing(S2)], ["member", "member"]);
    assert.deepEqual(g.lock.entries(S2), mine);
    assert.deepEqual(h.lock.entries(S2), mine);
    assert.deepEqual([f.host.secureAsked, g.host.secureAsked, h.host.secureAsked], [[], [], []], "nothing asked");
  } finally {
    f.runner.shutdown();
    g.runner.shutdown();
    h.runner.shutdown();
  }
});

test("a device id that is on the person's lock, written in a workspace's lock under another key, puts no one on it", () => {
  const kA = wsKey(1), kB = wsKey(2), kM = wsKey(4), kY = wsKey(5);
  const A = "a1".repeat(32), B = "b1".repeat(32), Y = "e5".repeat(32);
  const PB = personKey("0b"), PY = personKey("0e");
  // s2's lock of their own holds B (signing with kB). In this workspace the owner writes B's id under a key of their
  // own (kM) as s2's first, and with it puts Y in, which says a key.
  let ch: Entry[] = [genesis("ws", kA, true, [], {}, A)];
  ch = then(ch, kA, "device", app(B, "b", kM, {}, S2));
  ch = then(ch, kM, "device", app(Y, "y", kY, {}, S2));
  ch = then(ch, kY, "device", app(Y, "y", kY, { person_key: PY }, S2));
  const own = ownStandings(ch, S2, NOW);
  const y = own.devices.get(Y)!;
  assert.deepEqual([y.by, y.byKey], [B, kM.id], "put in under B's id, by another key");
  assert.deepEqual(approvedIn([own], S2, { id: B, signKey: kB.id }, chainOf([kB.id], [PB], [B], [PB])), [], "not by B's id");
  // (the same lock, where the chain recorded kM for B: put on, the key being what is matched)
  assert.deepEqual(approvedIn([own], S2, { id: B, signKey: kM.id }, chainOf([kM.id], [PB], [B], [PB])).map((d) => d.id), [Y]);
});

test("one taken off the lock is not put back by what a workspace's lock says; one with a chain pinned takes no other; one whose key was made before does not begin quietly", async () => {
  {
    const pc = personCloud();
    const st = stations();
    const kA = wsKey(1), kB = wsKey(2);
    const B = "b2".repeat(32), PB = personKey("0b");
    let ch: Entry[] = [];
    const a = device("a", pc, st, (id) => ({ signKey: () => kA.id, approved: (sub, chain) => approvedIn([ownStandings(ch, sub, NOW)], sub, { id, signKey: kA.id }, chain) }));
    try {
      ch = [genesis("ws", kA, true, [], {}, a.id)];
      ch = then(ch, kA, "device", app(B, "b", kB));
      ch = then(ch, kB, "device", app(B, "b", kB, { person_key: PB }));
      await a.runner.run(a.lock.refresh(SUB));
      assert.equal(await a.runner.run(a.lock.beginQuietly(SUB)), true);
      assert.deepEqual(idsOn(a.lock.entries(SUB)), [a.id, B].sort(), "put on as A put it in");
      assert.deepEqual(a.host.secureAsked, [], "nothing asked for that");
      // Taken off by the person (who is asked for that, once): the workspace's lock, not bound, still has it, said and
      // put in by A. Not put back as the seed is in hand then, nor at the next act.
      await a.runner.run(a.lock.removeDevice(SUB, PB, "why"));
      assert.deepEqual(idsOn(a.lock.entries(SUB)), [a.id]);
      await a.runner.run(a.lock.signGrant(SUB, { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: NOW }, "why"));
      assert.deepEqual(idsOn(a.lock.entries(SUB)), [a.id], "still off");
      assert.equal(a.host.secureAsked.length, 2, "asked only for the two acts");
    } finally {
      a.runner.shutdown();
    }
  }
  {
    const pc = personCloud();
    const st = stations();
    const a = device("a", pc, st);
    const fromA = () => ({ vouchers: () => new Set([keyOf("a")]) });
    const b = device("b", pc, st, fromA);
    const n = device("n", pc, st, fromA);
    try {
      // B began a lock of its own (P1), nobody asked; the stations lost it.
      await b.runner.run(b.lock.refresh(SUB));
      assert.equal(await b.runner.run(b.lock.beginQuietly(SUB)), true);
      const p1 = b.lock.entries(SUB);
      st.kept.delete(st.root(p1));
      // A begins another (P2, the person asked there) and puts B and N on it.
      const bKey = await b.runner.run(b.lock.makeKey());
      const nKey = await n.runner.run(n.lock.makeKey());
      await a.runner.run(a.lock.signGrant(SUB, { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: NOW }, "why"));
      assert.equal(await a.runner.run(a.lock.makeKey()), keyOf("a"));
      await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: b.id, label: "b" }, "why"));
      await a.runner.run(a.lock.addDevice(SUB, { key: nKey, id: n.id, label: "n" }, "why"));
      const p2 = a.lock.entries(SUB);
      // B keeps P1 (the other told of, as it is), N takes P2.
      await b.runner.run(b.lock.refresh(SUB));
      assert.deepEqual(b.lock.entries(SUB), p1);
      assert.equal(b.lock.standing(SUB), "replaced");
      await n.runner.run(n.lock.refresh(SUB));
      assert.deepEqual(n.lock.entries(SUB), p2);
      assert.equal(n.lock.standing(SUB), "member");
      assert.deepEqual([b.host.secureAsked, n.host.secureAsked], [[], []], "nothing asked of either");
    } finally {
      a.runner.shutdown();
      b.runner.shutdown();
      n.runner.shutdown();
    }
  }
  {
    // The one to begin, its key made before: it begins nothing, and says nothing (no one would read its key: it begins
    // the lock as its person is next asked for something).
    const kB = wsKey(2);
    const s = await first(undefined, ({ A, put }) => {
      put(A, "device", app(idOf("b"), "b", kB));
      put(kB, "device", app(idOf("b"), "b", kB, { person_key: keyOf("b") }));
    });
    const b = device("b", s.pc, s.st);
    try {
      const key = await s.run(s.personal.makeKey());
      assert.ok(key);
      await s.go();
      await s.r.host.time.pass(100);
      assert.equal(s.standing().devices.get(ME)?.said ?? null, null, "nothing said");
      assert.equal(s.st.kept.size, 0, "no lock begun");
      assert.equal(s.personal.standing(SUB), "none");
      assert.equal(s.personal.mayBeginQuietly(SUB), false);
      assert.equal(await s.run(s.personal.beginQuietly(SUB)), false);
      assert.equal(s.r.host.secureAsked.length, s.asked, "nothing asked");
    } finally {
      b.runner.shutdown();
    }
  }
});

test("two workspaces, each with a first device of its own: only the smaller id begins where both stand in both; neither where each stands in one", async () => {
  const k2 = wsKey(0x22);
  /// The core (D1) with ws begun by it and w2 by D2, each putting the other in, D2 saying its key in both.
  const twoLocks = async (D2: string) => {
    return await first((me, keys) => ({ ws: genesis("ws", me, true, [], keys, ME), w2: genesis("w2", k2, true, [], keys, D2) }), ({ A, put }) => {
      put(A, "device", app(D2, "d2", k2));
      put(k2, "device", app(D2, "d2", k2, { person_key: personKey("d2") }));
      put(k2, "device", app(ME, "this", A), "w2");
      put(k2, "device", app(D2, "d2", k2, { person_key: personKey("d2") }), "w2");
    });
  };
  {
    // D2's id the smaller: D2 is the one; this device says its key in both, and begins nothing.
    const s = await twoLocks("11".repeat(32));
    await s.go("ws", "w2");
    await s.until(() => s.standing("ws").devices.get(ME)?.said != null && s.standing("w2").devices.get(ME)?.said != null, "its key said in both");
    assert.equal(s.st.kept.size, 0, "not begun here");
    assert.equal(s.personal.standing(SUB), "none");
    assert.equal(s.r.host.secureAsked.length, s.asked);
  }
  {
    // This device's id the smaller: it begins, D2 on it.
    const D2 = "ef".repeat(32);
    const s = await twoLocks(D2);
    await s.go("ws", "w2");
    await s.until(() => s.standing("ws").devices.get(ME)?.said != null && s.standing("w2").devices.get(ME)?.said != null, "begun, its key said in both");
    assert.equal(s.personal.standing(SUB), "member");
    assert.deepEqual(idsOn(s.personal.entries(SUB)), [ME, D2].sort());
    assert.equal(s.r.host.secureAsked.length, s.asked);
  }
  {
    // D1 only in ws, D2 only in w2: no device of theirs stands in every lock, so no one is to begin: nothing begun,
    // and nothing said (a key made to say it could begin none later, should this device come to stand in both).
    const D2 = "ef".repeat(32);
    const s = await first((me, keys) => ({ ws: genesis("ws", me, true, [], keys, ME), w2: genesis("w2", k2, true, [], keys, D2) }), ({ put }) => {
      put(k2, "device", app(D2, "d2", k2, { person_key: personKey("d2") }), "w2");
    });
    await s.go("ws", "w2");
    await s.r.host.time.pass(100);
    assert.equal(s.st.kept.size, 0, "not begun");
    assert.equal(s.standing("ws").devices.get(ME)?.said ?? null, null, "nothing said");
    assert.equal(s.personal.mayBeginQuietly(SUB), true, "no key made");
    assert.equal(s.personal.standing(SUB), "none");
    assert.equal(s.r.host.secureAsked.length, s.asked);
  }
});

test("the person's stations answered: not while one seen within 31 days has not; once each has, or refused; one not seen for longer not waited for; no lock begun quietly before", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const at = Math.floor(host.nowMs() / 1000);
  const S1 = "01".repeat(32), S3 = "03".repeat(32), OLD = "02".repeat(32);
  // How each station answers a read of the person's lock: "ok", "refuse" (lock_unconfirmed), or nothing at all.
  const answers = new Map<string, "ok" | "refuse" | "silent">([[S1, "ok"], [S3, "silent"], [OLD, "silent"]]);
  const inner = {
    host,
    runner,
    // (`owner`: none, so `ownLockFor`, asked again as the last station answers, does nothing on this stand-in)
    workspaces: { owned: () => [["ws", SUB]], owner: () => null },
    provider: { kind: "stillfail" },
    // (`record`, `put`: what a station said of the builds is kept as it answers, views/lock.ts `keepBuilds`; none here)
    data: { shared: () => ({ stations: [{ id: S1, last_seen: at - 60 }, { id: S3, last_seen: at - 86400 }, { id: OLD, last_seen: at - 40 * 86400 }] }), record: () => null, put: () => undefined },
    stations: {
      requests: {
        call: (to: StationAddr) => {
          const a = answers.get(to.station);
          return a === "ok" ? Effect.succeed({ chains: [] }) : a === "refuse" ? Effect.fail(new CoreError("lock_unconfirmed", "not let in")) : Effect.never;
        },
      },
    },
  } as unknown as Inner;
  const env = personalStations(inner);
  const settle = async <X>(e: Effect.Effect<X>) => {
    const out: { done: boolean; value?: X } = { done: false };
    runner.fork(Effect.map(e, (v) => void ((out.value = v), (out.done = true))));
    await host.time.passUntil(20000, () => out.done);
    assert.ok(out.done, "read");
    // (the asks still going, what came meanwhile noted)
    await host.time.pass(10);
    return out.value;
  };
  try {
    assert.equal(env.answered!(SUB), false, "none read yet");
    assert.deepEqual(await settle(env.read(SUB)), [], "S1 keeps none");
    assert.equal(env.answered!(SUB), false, "S3, seen yesterday, has not answered");
    answers.set(S3, "refuse");
    await settle(env.read(SUB));
    assert.equal(env.answered!(SUB), true, "S3 refused this device: an answer; OLD, not seen for 40 days, not waited for");
  } finally {
    runner.shutdown();
  }
  // Without it, no lock is begun quietly, and nothing is made for it.
  const st = stations(false);
  const d = device("d", personCloud(), st);
  try {
    await d.runner.run(d.lock.refresh(SUB));
    assert.equal(d.lock.mayBeginQuietly(SUB), true);
    assert.equal(await d.runner.run(d.lock.beginQuietly(SUB)), false);
    assert.deepEqual(d.lock.entries(SUB), []);
    assert.equal(d.lock.mayBeginQuietly(SUB), true, "no key made");
    st.answered.value = true;
    assert.equal(await d.runner.run(d.lock.beginQuietly(SUB)), true);
    assert.deepEqual(d.host.secureAsked, []);
  } finally {
    d.runner.shutdown();
  }
});

test("ownStandings: who put each device in and with which key, the key each said, its ancestors; a restatement keeps a standing, one taken out and put in again begins anew", () => {
  const kA = wsKey(1), kB = wsKey(2), kC = wsKey(3), kG = wsKey(8);
  const A = "a1".repeat(32), B = "b1".repeat(32), C = "c1".repeat(32), G = "c8".repeat(32);
  const PB = personKey("0b"), PC = personKey("0c");
  let ch: Entry[] = [genesis("ws", kA, true, [], {}, A, [app(G, "g", kG)])]; // 0: A signs, G beside it
  ch = then(ch, kA, "device", app(B, "b", kB)); // 1: A puts B in
  ch = then(ch, kB, "device", app(C, "c", kC)); // 2: B puts C in
  ch = then(ch, kB, "device", app(B, "b", kB, { person_key: PB })); // 3: B says itself
  ch = then(ch, kC, "device", app(C, "c", kC, { person_key: PC })); // 4: C says itself
  let s = ownStandings(ch, SUB, NOW);
  const of = (id: string) => {
    const d = s.devices.get(id);
    return d && { by: d.by, byKey: d.byKey, bySub: d.bySub, since: d.since, said: d.said };
  };
  assert.deepEqual(of(A), { by: null, byKey: null, bySub: null, since: 0, said: null }, "the genesis's signer: put in by no one");
  assert.deepEqual(of(G), { by: A, byKey: kA.id, bySub: SUB, since: 0, said: null }, "the genesis's other of the signer's: put in by it");
  assert.deepEqual(of(B), { by: A, byKey: kA.id, bySub: SUB, since: 1, said: PB });
  assert.deepEqual(of(C), { by: B, byKey: kB.id, bySub: SUB, since: 2, said: PC });
  assert.deepEqual(ancestors(s, C).map((d) => d.id), [B, A]);
  assert.deepEqual(ancestors(s, A), []);
  // Someone else writing B again with the key it has (a label changed): its standing and what it said kept.
  ch = then(ch, kA, "device", app(B, "b again", kB)); // 5
  s = ownStandings(ch, SUB, NOW);
  assert.deepEqual(of(B), { by: A, byKey: kA.id, bySub: SUB, since: 1, said: PB });
  assert.equal(s.devices.get(B)?.label, "b again");
  // A key not of the form said: none.
  ch = then(ch, kB, "device", app(B, "b again", kB, { person_key: "ed25519:nope" })); // 6
  assert.equal(ownStandings(ch, SUB, NOW).devices.get(B)?.said, PB, "what it said before stands");
  // C taken out and put in again by A: put in by A since then, what it said before gone; said again, said.
  ch = then(ch, kA, "device.remove", { id: C }); // 7
  ch = then(ch, kA, "device", app(C, "c", kC)); // 8
  s = ownStandings(ch, SUB, NOW);
  assert.deepEqual(of(C), { by: A, byKey: kA.id, bySub: SUB, since: 8, said: null });
  ch = then(ch, kC, "device", app(C, "c", kC, { person_key: PC })); // 9
  s = ownStandings(ch, SUB, NOW);
  assert.deepEqual(of(C), { by: A, byKey: kA.id, bySub: SUB, since: 8, said: PC });
  // A taken out (by B): those A put in put in by no one that stands.
  ch = then(ch, kB, "device.remove", { id: A }); // 10
  s = ownStandings(ch, SUB, NOW);
  assert.equal(s.devices.has(A), false);
  assert.deepEqual(of(B), { by: null, byKey: null, bySub: null, since: 1, said: PB });
  assert.deepEqual(of(C), { by: null, byKey: null, bySub: null, since: 8, said: PC });
  assert.deepEqual(of(G), { by: null, byKey: null, bySub: null, since: 0, said: null });
  // Another person's devices are not theirs; a lock that does not check out says none.
  assert.equal(ownStandings(ch, S2, NOW).devices.size, 0);
  assert.deepEqual(ownStandings(ch.slice(1), SUB, NOW), { devices: new Map() });
});
