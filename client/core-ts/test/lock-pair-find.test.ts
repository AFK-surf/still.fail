// A new device asking to be approved face to face (`lock.pair`, views/pair.ts) keeps looking for its person's trusted
// devices: one not reached when it asked (its app not open yet, a phone's put away) is dialled again every
// PAIR_REDIAL_MS, PAIR_DIAL_TRIES times in all, a code shown elsewhere or not, so the one the person opens after asking
// shows its code; one reached is not dialled again, whatever it answered (it shows its code once); none reached in
// those tries, the page says so (`none`) and nothing more is dialled. Its page names the devices it dials, those
// showing a code first. On the test clock, the trusted devices' ends a line of the test's (`dialer`), each answering as
// the test says.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { CoreError, HostError } from "../src/error.ts";
import { type Entry, entryHash, next, signedBytes } from "../src/lock.ts";
import { PersonalLock } from "../src/personal-lock.ts";
import { type Duplex, dialer, PAIR_DIAL_MS, PAIR_DIAL_TRIES, PAIR_REDIAL_MS, personalBegin, personalPairState, serveTrusted } from "../src/views/pair.ts";
import { ME, elsewhere, genesis, pipe, rig } from "./lock-rig.ts";

/// The owner's phone and computer, apps that sign: the devices that may approve this one.
const PHONE_APP = "e1".repeat(32);
const LAPTOP_APP = "e2".repeat(32);

/// How a trusted device answers when dialled: not there (the dial fails at once), not answering (the dial hangs), a
/// code shown, that it approves this one nowhere it asks, or nothing (reached, its answer lost).
type Way = "away" | "silent" | "code" | "code-ends-on-proof" | "code-ends-after-another" | "credential" | "no" | "mute";

// Several fixtures can still be alive after a test stops waiting. Route each dial to the fixture for that core.
const fixtureDials = new WeakMap<Parameters<typeof dialer.open>[0], (id: string) => Effect.Effect<Duplex, CoreError>>();
dialer.open = (inner, id) => {
  const open = fixtureDials.get(inner);
  if (open === undefined) throw new Error("pairing fixture has no dialer for this core");
  return open(id);
};

/// A core waiting in `ws` (its device not in the lock, the owner's two apps in it), its mesh's base key ME, and the
/// trusted devices' ends as `ways` says now: each dial of each counted.
async function waiting(ways: Record<string, Way>, secondWorkspace = false, place = "ws") {
  const owner = elsewhere();
  const r = await rig(() => ({
    ws: genesis("ws", owner, false, [], {}, ME, [
      { id: PHONE_APP, sub: "s1", kind: "app", label: "still.fail Android · Pixel 8", sign_key: owner.id },
      { id: LAPTOP_APP, sub: "s1", kind: "app", label: "still.fail 桌面版 · MacBook", sign_key: owner.id },
    ]),
    ...(secondWorkspace ? { w2: genesis("w2", owner, false, [], {}, ME, [
      { id: PHONE_APP, sub: "s1", kind: "app", label: "still.fail Android · Pixel 8", sign_key: owner.id },
    ]) } : {}),
  }));
  r.core.inner.mesh = () => Effect.succeed({ deviceId: () => ME, lockClaim: () => null, link: () => Effect.fail(CoreError.plainly("mesh", "this fixture has no station link")) } as never);
  r.core.inner.cloudSync.credential = () => Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" });
  const dials: Record<string, number> = {};
  const hellos: unknown[] = [];
  const peers: Record<string, Duplex> = {};
  const open = (id: string): Effect.Effect<Duplex, CoreError> =>
    Effect.suspend(() => {
      dials[id] = (dials[id] ?? 0) + 1;
      const way = ways[id] ?? "away";
      if (way === "away") return Effect.fail(CoreError.plainly("pair", "not reached"));
      if (way === "silent") return Effect.never;
      return Effect.flatMap(Effect.promise(() => pipe()), ([here, there]) =>
        Effect.sync(() => {
          peers[id] = there;
          r.core.inner.runner.fork(
            Effect.gen(function* () {
              const hello = yield* there.next();
              hellos.push(hello);
              if (way === "mute") return;
              const hasCredential = way === "credential" && (hello as { workspaces?: { ws: string; credential: string }[] }).workspaces?.some((w) => w.ws === "ws" && w.credential === "signed-member");
              yield* there.send(way === "code" || way === "code-ends-on-proof" || way === "code-ends-after-another" || hasCredential ? { t: "code", workspaces: [place] } : { t: "no", error: "not_here" });
              if (way === "code-ends-on-proof" || way === "code-ends-after-another") {
                yield* there.next(); // It disconnects while the new device is checking the code.
                if (way === "code-ends-after-another") {
                  ways[LAPTOP_APP] = "code";
                  yield* Effect.sleep(PAIR_REDIAL_MS + 1_000);
                }
                there.close();
              }
            }),
          );
          return here;
        }));
    });
  fixtureDials.set(r.core.inner, open);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const secondLock = secondWorkspace ? await r.watch({ topic: "lock", workspace: "w2" }) : null;
  const pair = async () => (await lock()).me.pair;
  return { ...r, owner, ways, dials, hellos, peers, lock, pair, secondLock };
}

/// A joining device with a verified personal chain naming both trusted devices, but not this device.
async function waitingPersonal(ways: Record<string, Way>) {
  const w = await waiting(ways, false, "person:s1");
  const signed = (e: Omit<Entry, "sig">): Entry => ({ ...e, sig: { key: w.owner.id, alg: "Ed25519", sig: w.owner.signBytes(signedBytes(entryHash(e))) } });
  const first = signed(next("person:s1", null, 1_000, "genesis", { sub: "s1", device: { key: w.owner.id, id: PHONE_APP, label: "phone" } }));
  const add = signed(next("person:s1", { seq: 0, hash: entryHash(first), genesis: entryHash(first) }, 1_001, "device", { key: `ed25519:${"22".repeat(32)}`, id: LAPTOP_APP, label: "laptop" }));
  const personal = new PersonalLock({
    host: w.host, runner: w.core.inner.runner, device: () => Effect.succeed(ME), label: () => "joining device", changed: () => {},
    cloud: () => Effect.succeed({ entries: [first, add] }),
  });
  w.core.inner.adb.personal = () => personal;
  await w.core.inner.runner.run(personal.refresh("s1"));
  assert.deepEqual(personal.approvers("s1").map((d) => d.id), [PHONE_APP, LAPTOP_APP]);
  return { ...w, personal };
}

test("a signing key that cannot be read ends the request with its error, and a retry can ask again", async () => {
  const w = await waiting({ [PHONE_APP]: "code" });
  const secureGet = w.host.secureGet!;
  w.host.secureGet = (key, opts) => key === "lock-signer"
    ? Effect.fail(new HostError("钥匙暂不可用", true))
    : secureGet(key, opts);
  await assert.rejects(w.ask("lock.pair", { workspace: "ws" }), { code: "lock_key" });
  const failed = await w.pair();
  assert.equal(failed.state, "failed");
  assert.match(failed.error, /钥匙暂不可用/);
  assert.deepEqual(w.dials, {});
  w.host.secureGet = secureGet;
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "code");
  assert.equal(w.dials[PHONE_APP], 1);
});

test("a cancelled key read failing late cannot end a newer pairing request", async () => {
  const w = await waiting({ [PHONE_APP]: "code" });
  const secureGet = w.host.secureGet!;
  const release = Deferred.makeUnsafe<void>();
  w.host.secureGet = (key, opts) => key === "lock-signer"
    ? Effect.andThen(Deferred.await(release), Effect.fail(new HostError("钥匙暂不可用", true)))
    : secureGet(key, opts);
  const first = w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(500);
  await w.ask("lock.pairCancel", { workspace: "ws" });
  w.host.secureGet = secureGet;
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "code");
  Deferred.doneUnsafe(release, Effect.void);
  await assert.rejects(first, { code: "lock_key" });
  assert.equal((await w.pair()).state, "code");
  assert.equal(w.dials[PHONE_APP], 1);
});

function addApprover(w: Awaited<ReturnType<typeof waiting>>, addedDevice: string) {
  const entry = next("ws", w.cloud.head("ws"), w.host.nowMs() / 1000, "device", {
    id: addedDevice, sub: "s1", kind: "app", label: "new trusted device", sign_key: w.owner.id,
  });
  const signed: Entry = { ...entry, sig: { key: w.owner.id, alg: "Ed25519", sig: w.owner.signBytes(signedBytes(entryHash(entry))) } };
  w.cloud.chains.set("ws", [...w.cloud.chains.get("ws")!, signed]);
  const topic = { topic: "workspace", workspace: "ws" };
  w.core.inner.data.set(topic, { ...(w.core.inner.data.shared(topic) as object), lock: w.cloud.head("ws") });
}

test("a newly trusted device becomes available while the new device is looking: it is also asked", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "away", [LAPTOP_APP]: "away", [addedDevice]: "code" });
  const release = w.host.hold("/v1/workspaces/ws/lock?after=0");
  addApprover(w, addedDevice);
  await w.host.time.pass(500);
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal(w.dials[addedDevice], undefined);
  release();
  await w.host.time.pass(2 * PAIR_REDIAL_MS, 100);
  assert.equal(w.dials[addedDevice], 1, "the new trusted device is asked when its lock has been read");
  assert.equal((await w.pair()).state, "code");
});

test("a newer lock still being read is followed even when all old devices immediately say no", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "no", [LAPTOP_APP]: "no", [addedDevice]: "code" });
  const release = w.host.hold("/v1/workspaces/ws/lock?after=0");
  addApprover(w, addedDevice);
  await w.host.time.pass(500);
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "finding");
  release();
  await w.host.time.pass(2_000);
  assert.equal(w.dials[addedDevice], 1);
  assert.equal((await w.pair()).state, "code");
});

test("an unreadable newer lock does not leave the search waiting forever", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "no", [LAPTOP_APP]: "no", [addedDevice]: "code" });
  const release = w.host.hold("/v1/workspaces/ws/lock?after=0");
  addApprover(w, addedDevice);
  await w.host.time.pass(500);
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass((PAIR_DIAL_TRIES + 1) * PAIR_REDIAL_MS, 100);
  assert.equal((await w.pair()).state, "none");
  release();
  await w.host.time.pass(2_000);
  assert.equal(w.dials[addedDevice], undefined);
});

test("an approver added after looking began is asked without repeating an existing code", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away", [addedDevice]: "code" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "code");
  addApprover(w, addedDevice);
  await w.host.time.pass(2_000);
  assert.equal(w.dials[addedDevice], 1);
  assert.equal(w.dials[PHONE_APP], 1, "the existing code is not replaced");
  assert.equal((await w.pair()).devices, 2);
});

test("a lock begins updating during a search: the search follows its pending read", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "mute", [LAPTOP_APP]: "no", [addedDevice]: "code" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  const release = w.host.hold("/v1/workspaces/ws/lock?after=0");
  addApprover(w, addedDevice);
  // The old devices have answered or timed out, but the newer record is still being read.
  await w.host.time.pass(35_000, 100);
  assert.equal((await w.pair()).state, "finding");
  release();
  await w.host.time.pass(2_000);
  assert.equal(w.dials[addedDevice], 1);
  assert.equal((await w.pair()).state, "code");
});

test("cancelling while a newer lock is read never asks a newly added device", async () => {
  const addedDevice = "e3".repeat(32);
  const w = await waiting({ [PHONE_APP]: "away", [LAPTOP_APP]: "away", [addedDevice]: "code" });
  const release = w.host.hold("/v1/workspaces/ws/lock?after=0");
  addApprover(w, addedDevice);
  await w.host.time.pass(500);
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  await w.ask("lock.pairCancel", { workspace: "ws" });
  release();
  await w.host.time.pass(2 * PAIR_REDIAL_MS, 100);
  assert.equal(w.dials[addedDevice], undefined);
  assert.equal(await w.pair(), undefined);
});

test("a trusted device opened after the new device asked shows its code: dialled again every PAIR_REDIAL_MS", async () => {
  const w = await waiting({ [PHONE_APP]: "away", [LAPTOP_APP]: "away" });
  assert.equal((await w.lock()).me.waiting, true);
  await w.ask("lock.pair", { workspace: "ws" });
  // 25 s on, neither reached: still looking (not "none", as when each was dialled once), each dialled three times.
  await w.host.time.pass(25_000);
  assert.equal((await w.pair()).state, "finding");
  assert.deepEqual([w.dials[PHONE_APP], w.dials[LAPTOP_APP]], [3, 3]);
  // The person opens still.fail on their phone: it shows a code at the next dial.
  w.ways[PHONE_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  const p = await w.pair();
  assert.equal(p.state, "code");
  assert.deepEqual(p.approvers.map((a: { id: string; showing: boolean }) => [a.id, a.showing]), [[PHONE_APP, true], [LAPTOP_APP, false]]);
  assert.match(p.approvers[0].nameText, /Pixel 8/);
  assert.equal((w.hellos[0] as { t: string }).t, "hello");
  // The phone kept, not dialled again; the laptop still is, a code shown elsewhere or not, PAIR_DIAL_TRIES times in all.
  await w.host.time.pass(10 * PAIR_REDIAL_MS);
  assert.equal(w.dials[PHONE_APP], 4);
  assert.equal(w.dials[LAPTOP_APP], PAIR_DIAL_TRIES);
  assert.equal((await w.pair()).state, "code", "the phone's code still to type");
});

test("the laptop opened before its last try: it shows its code beside the phone's", async () => {
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(2 * PAIR_REDIAL_MS + 1_000);
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  const p = await w.pair();
  assert.deepEqual([p.devices, p.approvers.map((a: { showing: boolean }) => a.showing)], [2, [true, true]]);
  assert.deepEqual([w.dials[PHONE_APP], w.dials[LAPTOP_APP]], [1, 4]);
});

test("a code disappears during the search: another device opened afterwards can still show one", async () => {
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "code");
  w.peers[PHONE_APP]!.close();
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "finding", "the other device is still being sought");
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  assert.equal((await w.pair()).state, "code");
  assert.equal(w.dials[PHONE_APP], 1, "the device whose code was shown is not asked again");
  assert.equal(w.dials[LAPTOP_APP], 2);
});

for (const when of ["before proof", "during proof"] as const) {
  test(`a personal code disappears ${when}: another trusted device can still show one`, async () => {
    const w = await waitingPersonal({ [PHONE_APP]: when === "before proof" ? "code" : "code-ends-on-proof", [LAPTOP_APP]: "away" });
    try {
      await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
      await w.host.time.pass(1_000);
      assert.equal(personalPairState(w.core.inner, "s1")?.state, "code");
      if (when === "before proof") {
        w.peers[PHONE_APP]!.close();
        await w.host.time.pass(1_000);
      } else {
        await assert.rejects(w.ask("adb.personalCode", { code: "123456" }), { code: "pair_ended" });
      }
      assert.equal(personalPairState(w.core.inner, "s1")?.state, "finding", "the other device is still being sought");
      w.ways[LAPTOP_APP] = "code";
      await w.host.time.pass(PAIR_REDIAL_MS);
      assert.equal(personalPairState(w.core.inner, "s1")?.state, "code");
      assert.equal(w.dials[PHONE_APP], 1);
      assert.equal(w.dials[LAPTOP_APP], 2);
    } finally {
      await w.core.close();
    }
  });
}

test("a personal code disappears and no other device answers: the page says why", async () => {
  const w = await waitingPersonal({ [PHONE_APP]: "code-ends-on-proof", [LAPTOP_APP]: "away" });
  try {
    await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
    await w.host.time.pass(1_000);
    await assert.rejects(w.ask("adb.personalCode", { code: "123456" }), { code: "pair_ended" });
    await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS, 100);
    const p = personalPairState(w.core.inner, "s1");
    assert.equal(p?.state, "failed");
    assert.ok(p?.error, "the page explains why the code went away");
    assert.equal(w.dials[LAPTOP_APP], PAIR_DIAL_TRIES);
  } finally { await w.core.close(); }
});

test("cancelling a personal search after a code disappears stops further dials", async () => {
  const w = await waitingPersonal({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  try {
    await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
    await w.host.time.pass(1_000);
    w.peers[PHONE_APP]!.close();
    await w.host.time.pass(1_000);
    assert.equal(personalPairState(w.core.inner, "s1")?.state, "finding");
    await w.ask("adb.personalCancel", {});
    w.ways[LAPTOP_APP] = "code";
    await w.host.time.pass(2 * PAIR_REDIAL_MS, 100);
    assert.equal(personalPairState(w.core.inner, "s1"), null);
    assert.equal(w.dials[LAPTOP_APP], 1);
  } finally { await w.core.close(); }
});

test("cancelling a personal search closes a connected device still answering", async () => {
  const w = await waitingPersonal({ [PHONE_APP]: "mute", [LAPTOP_APP]: "away" });
  let closed = false;
  try {
    await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
    await w.host.time.pass(1_000);
    assert.equal(personalPairState(w.core.inner, "s1")?.state, "finding");
    const peer = w.peers[PHONE_APP]!;
    w.core.inner.runner.fork(Effect.map(peer.next(), (answer) => { if (answer === null) closed = true; }));
    await w.ask("adb.personalCancel", {});
    await w.host.time.pass(1_000);
    assert.equal(closed, true, "the pending connection is closed when the request is cancelled");
    assert.equal(personalPairState(w.core.inner, "s1"), null);
  } finally { await w.core.close(); }
});

test("another personal code shown during proof remains ready if the first connection ends", async () => {
  const w = await waitingPersonal({ [PHONE_APP]: "code-ends-after-another", [LAPTOP_APP]: "away" });
  try {
    await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
    await w.host.time.pass(1_000);
    await assert.rejects(w.ask("adb.personalCode", { code: "123456" }), { code: "pair_ended" });
    assert.equal(w.dials[LAPTOP_APP], 2);
    assert.equal(personalPairState(w.core.inner, "s1")?.state, "code");
  } finally { await w.core.close(); }
});

for (const when of ["before a retry", "while a dial is in flight", "while an answer is in flight"] as const) {
  test(`a personal approval being saved stops seeking ${when}`, async () => {
    const w = await waiting({});
    const trusted = await rig((signer) => ({ ws: genesis("ws", signer, true) }));
    const prompts = await trusted.watch({ topic: "lockPrompts" });
    const kept = new Map<string, Entry[]>();
    const cloud = (sub: string, method: string, _path: string, body: unknown) => Effect.sync(() => {
      const entries = kept.get(sub) ?? [];
      if (method === "GET") return { entries };
      const adding = (body as { entries: Entry[] }).entries;
      const next = adding[0]!.seq === 0 ? adding : [...entries.slice(0, adding[0]!.seq), ...adding];
      kept.set(sub, next);
      return { entries: next };
    });
    const personal = (r: Pick<typeof w, "host" | "core">, id: string) => {
      const sealed = new Map<string, Uint8Array>();
      const read = r.host.secureGet!;
      r.host.secureSet = (key, value) => Effect.sync(() => void sealed.set(key, value));
      r.host.secureGet = (key, opts) => opts.user ? Effect.succeed(sealed.get(key) ?? null) : read.call(r.host, key, opts);
      return new PersonalLock({ host: r.host, runner: r.core.inner.runner, cloud, device: () => Effect.succeed(id), label: () => "device", changed: () => {} });
    };
    // The fake hosts otherwise start from the same deterministic random stream.
    w.host.randomBytes(new Uint8Array(17));
    const owner = personal(trusted, PHONE_APP), joining = personal(w, ME);
    trusted.core.inner.adb.personal = () => owner;
    w.core.inner.adb.personal = () => joining;
    const release = Deferred.makeUnsafe<void>(), laptopRelease = Deferred.makeUnsafe<void>();
    let writing = false, laptopAvailable = false, laptopDials = 0, laptopShown = false, laptopClosed = false;
    const results: { _tag: string }[] = [];
    try {
      await trusted.core.inner.runner.run(owner.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
      await trusted.core.inner.runner.run(owner.addDevice("s1", { key: elsewhere().id, id: LAPTOP_APP, label: "laptop" }, "why"));
      await w.core.inner.runner.run(joining.refresh("s1"));
      fixtureDials.set(w.core.inner, (id) => Effect.suspend(() => {
        if (id === LAPTOP_APP) {
          laptopDials++;
          if (when === "before a retry" && !laptopAvailable) return Effect.fail(CoreError.plainly("pair", "not reached"));
        }
        const connecting = Effect.flatMap(Effect.promise(() => pipe()), ([here, there]) => Effect.sync(() => {
          if (id === PHONE_APP) trusted.core.inner.runner.fork(serveTrusted(trusted.core.inner, ME, PHONE_APP, there));
          else w.core.inner.runner.fork(Effect.gen(function* () {
            const hello = yield* there.next();
            if (hello === null) { laptopClosed = true; return; }
            laptopShown = true;
            if (when === "while an answer is in flight") {
              w.core.inner.runner.fork(Effect.map(there.next(), (end) => { if (end === null) laptopClosed = true; }));
              yield* Deferred.await(laptopRelease);
              yield* there.send({ t: "code", workspaces: ["person:s1"] });
              return;
            }
            yield* there.send({ t: "code", workspaces: ["person:s1"] });
            const end = yield* there.next();
            if (end === null) laptopClosed = true;
          }));
          return here;
        }));
        return id === LAPTOP_APP && when === "while a dial is in flight" ? Effect.andThen(Deferred.await(laptopRelease), connecting) : connecting;
      }));
      await w.core.inner.runner.run(personalBegin(w.core.inner, ["s1"]));
      for (let i = 0; i < 100 && personalPairState(w.core.inner, "s1")?.state !== "code"; i++) {
        await w.host.time.pass(10);
        await trusted.host.time.pass(10);
      }
      assert.equal(personalPairState(w.core.inner, "s1")?.state, "code");
      const shown = (await prompts()).pairing.find((p: { device: string }) => p.device === ME);
      assert.ok(shown?.code, "the trusted device really showed a code");
      const set = w.host.storageSet.bind(w.host);
      w.host.storageSet = (key, value) => key.startsWith("personal-lock-")
        ? Effect.andThen(Effect.sync(() => { writing = true; }), Effect.andThen(Deferred.await(release), set(key, value)))
        : set(key, value);
      w.core.inner.runner.fork(Effect.map(Effect.result(w.core.inner.adb.run({ kind: "personalCode", code: shown.code })), (result) => { results.push(result); }));
      for (let i = 0; i < 300 && !writing; i++) { await w.host.time.pass(10); await trusted.host.time.pass(10); }
      assert.equal(writing, true, "the real proof was approved and the joining device is saving it");
      const before = laptopDials;
      laptopAvailable = true;
      if (when === "while an answer is in flight") await w.host.time.pass(1_000, 100);
      const closedBeforeAnswer = laptopClosed;
      Deferred.doneUnsafe(laptopRelease, Effect.void);
      await w.host.time.pass(when === "before a retry" ? PAIR_REDIAL_MS + 1_000 : 1_000, 100);
      const during = { dials: laptopDials, shown: laptopShown, closed: laptopClosed, pair: personalPairState(w.core.inner, "s1") };
      Deferred.doneUnsafe(release, Effect.void);
      for (let i = 0; i < 300 && results.length === 0; i++) { await w.host.time.pass(10); await trusted.host.time.pass(10); }
      const after = personalPairState(w.core.inner, "s1");
      assert.equal(during.dials, before, "an accepted approval stops new dials while its save is pending");
      assert.equal(during.shown, when === "while an answer is in flight", "no new code is requested after approval");
      if (when === "while a dial is in flight") assert.equal(during.closed, true, "a dial already in flight is closed before asking for a code");
      if (when === "while an answer is in flight") assert.equal(closedBeforeAnswer, true, "a pending answer is closed as soon as another device approves");
      assert.equal(during.pair?.state, "checking");
      assert.equal(during.pair?.devices, 0, "no new code is retained while saving");
      assert.equal(results[0]?._tag, "Success");
      assert.equal(after?.state, "done");
      assert.equal(after?.devices, 0, "no code is left open after approval");
      const cold = new PersonalLock({ host: w.host, runner: w.core.inner.runner, cloud, device: () => Effect.succeed(ME), label: () => "device", changed: () => {} });
      await w.core.inner.runner.run(cold.load("s1"));
      assert.equal(cold.chain("s1")?.hash, joining.chain("s1")?.hash);
      assert.equal(cold.standing("s1"), "member");
    } finally {
      Deferred.doneUnsafe(release, Effect.void);
      Deferred.doneUnsafe(laptopRelease, Effect.void);
      await w.core.close();
      await trusted.core.close();
    }
  });
}

test("a code disappears while it is checked: another device opened afterwards can still show one", async () => {
  const w = await waiting({ [PHONE_APP]: "code-ends-on-proof", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "code");
  const error = await w.ask("lock.pairCode", { workspace: "ws", code: "123456" }).then(() => null, (e) => e as { code: string });
  assert.equal(error?.code, "pair_ended");
  assert.equal((await w.pair()).state, "finding", "the other device is still being sought");
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  assert.equal((await w.pair()).state, "code");
  assert.equal(w.dials[PHONE_APP], 1);
  assert.equal(w.dials[LAPTOP_APP], 2);
});

test("a code disappears while it is checked and no other device answers: say why it ended", async () => {
  const w = await waiting({ [PHONE_APP]: "code-ends-on-proof", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  await assert.rejects(w.ask("lock.pairCode", { workspace: "ws", code: "123456" }), { code: "pair_ended" });
  await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS);
  const p = await w.pair();
  assert.equal(p.state, "failed");
  assert.ok(p.error, "the page explains why the previous code went away");
  assert.equal(w.dials[LAPTOP_APP], PAIR_DIAL_TRIES);
});

test("another device shows a code while the first one's code is being checked", async () => {
  const w = await waiting({ [PHONE_APP]: "code-ends-after-another", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  const error = await w.ask("lock.pairCode", { workspace: "ws", code: "123456" }).then(() => null, (e) => e as { code: string });
  assert.equal(w.dials[LAPTOP_APP], 2);
  assert.equal((await w.pair()).state, "code", "the newly shown code was not tested and is not wrong");
  assert.equal(error?.code, "pair_ended");
});

test("a code disappears during the search and no other device answers: say why it ended", async () => {
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  w.peers[PHONE_APP]!.close();
  await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS);
  const p = await w.pair();
  assert.equal(p.state, "failed");
  assert.ok(p.error, "the page explains why the previous code went away");
  assert.equal(w.dials[PHONE_APP], 1);
  assert.equal(w.dials[LAPTOP_APP], PAIR_DIAL_TRIES);
});

test("cancelling after a code disappears stops looking for the remaining devices", async () => {
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  w.peers[PHONE_APP]!.close();
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "finding");
  await w.ask("lock.pairCancel", { workspace: "ws" });
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS * 2);
  assert.equal(await w.pair(), undefined);
  assert.equal(w.dials[LAPTOP_APP], 1);
});

test("a dial that hangs is given up after PAIR_DIAL_MS and made again", async () => {
  const w = await waiting({ [PHONE_APP]: "silent", [LAPTOP_APP]: "away" });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(3 * PAIR_DIAL_MS + 1_000);
  assert.equal(w.dials[PHONE_APP], 4, "once, then again each time one ran its time out");
  w.ways[PHONE_APP] = "code";
  await w.host.time.pass(PAIR_DIAL_MS);
  assert.equal((await w.pair()).state, "code");
});

test("none reached in PAIR_DIAL_TRIES dials each: the page says so, and nothing more is dialled", async () => {
  const w = await waiting({});
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass((PAIR_DIAL_TRIES - 1) * PAIR_REDIAL_MS - 1_000);
  assert.equal((await w.pair()).state, "finding");
  await w.host.time.pass(2_000);
  assert.equal((await w.pair()).state, "none");
  assert.deepEqual(w.dials, { [PHONE_APP]: PAIR_DIAL_TRIES, [LAPTOP_APP]: PAIR_DIAL_TRIES });
  await w.host.time.pass(5 * 60_000);
  assert.deepEqual(w.dials, { [PHONE_APP]: PAIR_DIAL_TRIES, [LAPTOP_APP]: PAIR_DIAL_TRIES });
  // Asked again, it looks again.
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  assert.equal((await w.pair()).state, "finding");
  assert.equal(w.dials[PHONE_APP], PAIR_DIAL_TRIES + 1);
});

test("a trusted device reached is not dialled again, whatever it answered: it shows its code once", async () => {
  // Each says it shows none: dialled once each, and the page says none at once.
  const no = await waiting({ [PHONE_APP]: "no", [LAPTOP_APP]: "no" });
  await no.ask("lock.pair", { workspace: "ws" });
  await no.host.time.pass(10_000);
  assert.deepEqual([no.dials[PHONE_APP], no.dials[LAPTOP_APP]], [1, 1]);
  assert.equal((await no.pair()).state, "none");
  // Reached, its answer lost: it may show a code all the same; met again it would show another. Not dialled again.
  const mute = await waiting({ [PHONE_APP]: "mute", [LAPTOP_APP]: "away" });
  await mute.ask("lock.pair", { workspace: "ws" });
  await mute.host.time.pass(2 * 60_000);
  assert.deepEqual([mute.dials[PHONE_APP], mute.dials[LAPTOP_APP]], [1, PAIR_DIAL_TRIES]);
  assert.equal((await mute.pair()).state, "none");
});

test("a resumed search in one core cannot count dials in another core's fixture", async () => {
  const earlier = await waiting({});
  let later: Awaited<ReturnType<typeof waiting>> | null = null;
  try {
    await earlier.ask("lock.pair", { workspace: "ws" });
    await earlier.host.time.pass((PAIR_DIAL_TRIES - 1) * PAIR_REDIAL_MS + 2_000, 100);
    assert.equal((await earlier.pair()).state, "none");
    assert.deepEqual([earlier.dials[PHONE_APP], earlier.dials[LAPTOP_APP]], [PAIR_DIAL_TRIES, PAIR_DIAL_TRIES]);

    later = await waiting({ [PHONE_APP]: "mute", [LAPTOP_APP]: "away" });
    await later.ask("lock.pair", { workspace: "ws" });
    await later.host.time.pass(2 * 60_000, 100);
    assert.deepEqual([later.dials[PHONE_APP], later.dials[LAPTOP_APP]], [1, PAIR_DIAL_TRIES]);

    // An earlier test may resume after its caller timed out. Its later retry still belongs to its own core.
    await earlier.ask("lock.pair", { workspace: "ws" });
    await earlier.host.time.pass(1_000);
    assert.deepEqual([later.dials[PHONE_APP], later.dials[LAPTOP_APP]], [1, PAIR_DIAL_TRIES], "earlier retries do not reach the later fixture");
    assert.deepEqual([earlier.dials[PHONE_APP], earlier.dials[LAPTOP_APP]], [PAIR_DIAL_TRIES + 1, PAIR_DIAL_TRIES + 1]);
  } finally {
    await earlier.core.close();
    await later?.core.close();
  }
});

test("asked again, the try before stops dialling", async () => {
  const w = await waiting({});
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(15_000);
  await w.ask("lock.pairCancel", { workspace: "ws" }).catch(() => null);
  const dials = { ...w.dials };
  await w.host.time.pass(60_000);
  assert.deepEqual(w.dials, dials);
});

test("a credential temporarily unavailable: the new device asks again and the trusted device can show a code", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  let requests = 0;
  w.core.inner.cloudSync.credential = () => Effect.suspend(() => ++requests === 1
    ? Effect.fail(new CoreError("network", "网络连接失败"))
    : Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" }));
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_REDIAL_MS + 2_000);
  assert.equal((await w.pair()).state, "code", "the trusted device can show a code once the credential is available");
  assert.equal(w.hellos.length, 1, "the trusted device is not asked with an empty credential");
  assert.equal((w.hellos[0] as { workspaces: { credential: string }[] }).workspaces[0]?.credential, "signed-member");
});

test("a credential unavailable throughout: the waiting page says why rather than claiming no trusted device answered", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  w.core.inner.cloudSync.credential = () => Effect.fail(new CoreError("network", "网络连接失败"));
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS + 2_000);
  const p = await w.pair();
  assert.equal(p.state, "failed");
  assert.match(p.error, /网络连接失败/);
  assert.deepEqual(w.hellos, [], "no trusted device is asked without a credential");
});

test("an expired login: the waiting page says why without repeating a rejected request", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  let requests = 0;
  w.core.inner.cloudSync.credential = () => Effect.suspend(() => {
    requests++;
    return Effect.fail(new CoreError("invalid_session", "登录已失效，请重新登录", 401));
  });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_REDIAL_MS + 2_000);
  const p = await w.pair();
  assert.deepEqual([p.state, p.error], ["failed", "登录已失效，请重新登录"]);
  assert.equal(requests, 1);
  assert.deepEqual(w.hellos, []);
});

test("one workspace's credential fails: the other can still ask and the failed workspace says why", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" }, true);
  w.core.inner.cloudSync.credential = (ws) => ws === "ws"
    ? Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" })
    : Effect.fail(new CoreError("invalid_session", "登录已失效，请重新登录", 401));
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(2_000);
  assert.equal((await w.pair()).state, "code");
  const other = (await w.secondLock!()).me.pair;
  assert.deepEqual([other.state, other.error], ["failed", "登录已失效，请重新登录"]);
  assert.deepEqual((w.hellos[0] as { workspaces: { ws: string }[] }).workspaces.map((x) => x.ws), ["ws"]);
  assert.equal(w.dials[PHONE_APP], 1, "a code already showing is not requested a second time");
});

test("a workspace's credential request hangs: another workspace can still show a code", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" }, true);
  w.core.inner.cloudSync.credential = (ws) => ws === "ws"
    ? Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" })
    : Effect.never;
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_REDIAL_MS + 2_000);
  assert.equal((await w.pair()).state, "code");
  assert.deepEqual((w.hellos[0] as { workspaces: { ws: string }[] }).workspaces.map((x) => x.ws), ["ws"]);
  assert.equal((await w.secondLock!()).me.pair.state, "failed");
});

test("a credential request that never answers ends with a network error after the tries", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  w.core.inner.cloudSync.credential = () => Effect.never;
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS + 2_000);
  const p = await w.pair();
  assert.equal(p.state, "failed");
  assert.match(p.error, /网络连接失败/);
  assert.deepEqual(w.hellos, []);
});

test("a credential request that hangs once is retried and can then show a code", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  let requests = 0;
  w.core.inner.cloudSync.credential = () => Effect.suspend(() => ++requests === 1
    ? Effect.never
    : Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" }));
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(PAIR_REDIAL_MS + 2_000);
  assert.equal((await w.pair()).state, "code");
  assert.equal(requests, 2);
  assert.equal(w.dials[PHONE_APP], 1);
});

test("a cancelled try stops retrying its unavailable credential", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" });
  let requests = 0;
  w.core.inner.cloudSync.credential = () => Effect.suspend(() => { requests++; return Effect.fail(new CoreError("network", "网络连接失败")); });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.ask("lock.pairCancel", { workspace: "ws" });
  const before = requests;
  await w.host.time.pass(PAIR_DIAL_TRIES * PAIR_REDIAL_MS);
  assert.equal(requests, before);
  assert.deepEqual(w.hellos, []);
});

test("cancelled while credentials are being fetched: no further attempts or dialogs follow", async () => {
  const w = await waiting({ [PHONE_APP]: "credential" }, true);
  const release = Deferred.makeUnsafe<void>();
  const requests: string[] = [];
  w.core.inner.cloudSync.credential = (ws) => Effect.suspend(() => {
    requests.push(ws);
    return Effect.andThen(Deferred.await(release), Effect.fail(new CoreError("network", "网络连接失败")));
  });
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(500);
  assert.deepEqual([...requests].sort(), ["w2", "ws"]);
  await w.ask("lock.pairCancel", { workspace: "ws" });
  Deferred.doneUnsafe(release, Effect.void);
  await w.host.time.pass(PAIR_REDIAL_MS);
  assert.deepEqual([...requests].sort(), ["w2", "ws"], "no further credential requests follow cancellation");
  assert.deepEqual(w.hellos, []);
});
