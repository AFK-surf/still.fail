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
import { type Duplex, dialer, PAIR_DIAL_MS, PAIR_DIAL_TRIES, PAIR_REDIAL_MS, personalBegin, personalPairState, personalProve } from "../src/views/pair.ts";
import { lockSeen, signerOf } from "../src/views/lock.ts";
import { ME, elsewhere, genesis, pipe, rig } from "./lock-rig.ts";
import { stationReplies } from "./station-fixture.ts";

/// The owner's phone and computer, apps that sign: the devices that may approve this one.
const PHONE_APP = "e1".repeat(32);
const LAPTOP_APP = "e2".repeat(32);

/// How a trusted device answers when dialled: not there (the dial fails at once), not answering (the dial hangs), a
/// code shown, that it approves this one nowhere it asks, or nothing (reached, its answer lost).
type Way = "away" | "silent" | "code" | "code-ends-on-proof" | "code-ends-after-another" | "credential" | "no" | "mute";

/// A core waiting in `ws` (its device not in the lock, the owner's two apps in it), its mesh's base key ME, and the
/// trusted devices' ends as `ways` says now: each dial of each counted.
async function waiting(ways: Record<string, Way>, secondWorkspace = false) {
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
              const places = (hello as { personal?: unknown }).personal ? ["person:s1"] : ["ws"];
              yield* there.send(way === "code" || way === "code-ends-on-proof" || way === "code-ends-after-another" || hasCredential ? { t: "code", workspaces: places } : { t: "no", error: "not_here" });
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
  dialer.open = (_inner, id) => open(id);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const secondLock = secondWorkspace ? await r.watch({ topic: "lock", workspace: "w2" }) : null;
  const pair = async () => (await lock()).me.pair;
  return { ...r, owner, ways, dials, hellos, peers, lock, pair, secondLock };
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
  // Each a row of its page's list: a phone or a computer, and which machine.
  assert.deepEqual(p.approvers.map((a: { kind: string; nameText: string }) => [a.kind, a.nameText]), [["phone", "Pixel 8"], ["computer", "MacBook"]]);
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

test("a personal lock's code disappears during the search: another device can still show one", async () => {
  const w = await waiting({ [PHONE_APP]: "code", [LAPTOP_APP]: "away" });
  w.core.inner.adb.personal = () => ({
    makeKey: () => Effect.succeed(`ed25519:${"11".repeat(32)}`),
    approvers: () => [{ id: PHONE_APP, label: "phone" }, { id: LAPTOP_APP, label: "laptop" }],
    // (the workspaces' locks are shown again as the try goes on: views/pair.ts `changed`)
    standing: () => "none", root: () => null,
    // (views/lock.ts `ownLockFor` reads these of it as the locks are read: it begins nothing here)
    refresh: () => Effect.void, entries: () => [], mayBeginQuietly: () => false,
    // (and what is pending of it, on the lock's topic, as the workspace's view changes)
    pendingShown: () => [], stationsChanged: () => {},
  }) as never;
  await Effect.runPromise(personalBegin(w.core.inner, ["s1"]));
  await w.host.time.pass(1_000);
  assert.equal(personalPairState(w.core.inner, "s1").state, "code");
  w.peers[PHONE_APP]!.close();
  await w.host.time.pass(1_000);
  assert.equal(personalPairState(w.core.inner, "s1").state, "finding");
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  assert.equal(personalPairState(w.core.inner, "s1").state, "code");
  assert.deepEqual([w.dials[PHONE_APP], w.dials[LAPTOP_APP]], [1, 2]);
});

test("a personal lock's code disappears while it is checked: another device can still show one", async () => {
  const w = await waiting({ [PHONE_APP]: "code-ends-on-proof", [LAPTOP_APP]: "away" });
  w.core.inner.adb.personal = () => ({
    makeKey: () => Effect.succeed(`ed25519:${"11".repeat(32)}`),
    approvers: () => [{ id: PHONE_APP, label: "phone" }, { id: LAPTOP_APP, label: "laptop" }],
    // (the workspaces' locks are shown again as the try goes on: views/pair.ts `changed`)
    standing: () => "none", root: () => null,
    // (views/lock.ts `ownLockFor` reads these of it as the locks are read: it begins nothing here)
    refresh: () => Effect.void, entries: () => [], mayBeginQuietly: () => false,
    // (and what is pending of it, on the lock's topic, as the workspace's view changes)
    pendingShown: () => [], stationsChanged: () => {},
  }) as never;
  await Effect.runPromise(personalBegin(w.core.inner, ["s1"]));
  await w.host.time.pass(1_000);
  assert.equal(personalPairState(w.core.inner, "s1").state, "code");
  const proving = Effect.runPromise(Effect.result(personalProve(w.core.inner, "123456")));
  await w.host.time.pass(1_000);
  const result = await proving;
  assert.equal(result._tag, "Failure");
  if (result._tag === "Failure") assert.equal(result.failure.code, "pair_ended");
  assert.equal(personalPairState(w.core.inner, "s1").state, "finding");
  w.ways[LAPTOP_APP] = "code";
  await w.host.time.pass(PAIR_REDIAL_MS);
  assert.equal(personalPairState(w.core.inner, "s1").state, "code");
  assert.deepEqual([w.dials[PHONE_APP], w.dials[LAPTOP_APP]], [1, 2]);
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

/// An entry the owner's phone signs, kept at the cloud and read here (as addApprover's is).
async function signedIn(w: Awaited<ReturnType<typeof waiting>>, kind: string, body: unknown) {
  const entry = next("ws", w.cloud.head("ws"), w.host.nowMs() / 1000, kind, body);
  w.cloud.chains.set("ws", [...w.cloud.chains.get("ws")!, { ...entry, sig: { key: w.owner.id, alg: "Ed25519", sig: w.owner.signBytes(signedBytes(entryHash(entry))) } }]);
  const topic = { topic: "workspace", workspace: "ws" };
  w.core.inner.data.set(topic, { ...(w.core.inner.data.shared(topic) as object), lock: w.cloud.head("ws") });
  await w.host.time.pass(1_000);
}

test("where its person bound a lock of their own that this device is not on, it asks to join that lock, from the page that waits there too; approved into the workspace's lock alone it waits still", async () => {
  // (2026-11-10, a new phone: 发送批准请求 on the page that waits had it approved into the workspace's lock, face to
  // face, and every station went on refusing it, as they let the person's app devices in on their own lock alone:
  // 「已经批过了啊」)
  const w = await waiting({ [PHONE_APP]: "code" }, true);
  const inner = w.core.inner;
  stationReplies(w.host, (req) => (req.method === "GET" && req.url.endsWith("/v1/me/personal-lock") ? { entries: [] } : w.cloud.reply(req)));
  // Their lock as this device read it: the phone on it, this one not. Bound in `ws` (the phone signed that), not in `w2`.
  let standing = "outside";
  inner.adb.personal = () => ({
    makeKey: () => Effect.succeed(`ed25519:${"11".repeat(32)}`),
    approvers: () => [{ id: PHONE_APP, label: "phone" }],
    standing: () => standing, root: () => null, entries: () => [], chain: () => null,
    // (views/lock.ts `ownLockFor` reads these of it as the locks are read: it begins nothing here)
    refresh: () => Effect.void, mayBeginQuietly: () => false,
    // (and what is pending of it, on the lock's topic, as the workspace's view changes)
    pendingShown: () => [], stationsChanged: () => {},
  }) as never;
  await signedIn(w, "person", { sub: "s1", person: "ab".repeat(32) });
  const here = (await w.lock()).me;
  assert.deepEqual([here.waiting, here.ownLock, here.confirmed], [true, true, false]);
  const there = (await w.secondLock!()).me;
  assert.deepEqual([there.waiting, there.ownLock ?? false], [true, false]);

  // Asked from the other workspace: approved there, not into this one's lock, which would let it in nowhere.
  await w.ask("lock.pair", { workspace: "w2" });
  await w.host.time.pass(1_000);
  assert.deepEqual(w.hellos.map((h) => (h as { workspaces: { ws: string }[] }).workspaces.map((x) => x.ws)), [["w2"]]);
  // Asked from this one's page: its person's own lock is what it asks to join, and the page shows how that goes.
  await w.ask("lock.pair", { workspace: "ws" });
  await w.host.time.pass(1_000);
  const hello = w.hellos.at(-1) as { workspaces: unknown[]; personal?: { subs: string[] } };
  assert.deepEqual([hello.workspaces, hello.personal?.subs], [[], ["s1"]]);
  assert.equal((await w.pair()).state, "code", "the page that waits here has the boxes for the code");

  // In the workspace's lock all the same (approved the old way): it waits still, to join their own.
  await signedIn(w, "device", { id: ME, sub: "s1", kind: "app", label: "this", sign_key: signerOf(inner) });
  const after = (await w.lock()).me;
  assert.deepEqual([after.waiting, after.ownLock, after.confirmed], [true, true, false]);
  // Their lock not read yet (an app just started): what the workspace's lock says stands, no page that waits.
  standing = "none";
  lockSeen(inner).touch("lock ws");
  const started = (await w.lock()).me;
  assert.deepEqual([started.waiting, started.confirmed], [false, true]);
});
