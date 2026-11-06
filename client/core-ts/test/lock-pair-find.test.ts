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
import { type Duplex, dialer, PAIR_DIAL_MS, PAIR_DIAL_TRIES, PAIR_REDIAL_MS } from "../src/views/pair.ts";
import { ME, elsewhere, genesis, pipe, rig } from "./lock-rig.ts";

/// The owner's phone and computer, apps that sign: the devices that may approve this one.
const PHONE_APP = "e1".repeat(32);
const LAPTOP_APP = "e2".repeat(32);

/// How a trusted device answers when dialled: not there (the dial fails at once), not answering (the dial hangs), a
/// code shown, that it approves this one nowhere it asks, or nothing (reached, its answer lost).
type Way = "away" | "silent" | "code" | "credential" | "no" | "mute";

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
  const open = (id: string): Effect.Effect<Duplex, CoreError> =>
    Effect.suspend(() => {
      dials[id] = (dials[id] ?? 0) + 1;
      const way = ways[id] ?? "away";
      if (way === "away") return Effect.fail(CoreError.plainly("pair", "not reached"));
      if (way === "silent") return Effect.never;
      return Effect.flatMap(Effect.promise(() => pipe()), ([here, there]) =>
        Effect.sync(() => {
          r.core.inner.runner.fork(
            Effect.gen(function* () {
              const hello = yield* there.next();
              hellos.push(hello);
              if (way === "mute") return;
              const hasCredential = way === "credential" && (hello as { workspaces?: { ws: string; credential: string }[] }).workspaces?.some((w) => w.ws === "ws" && w.credential === "signed-member");
              yield* there.send(way === "code" || hasCredential ? { t: "code", workspaces: ["ws"] } : { t: "no", error: "not_here" });
            }),
          );
          return here;
        }));
    });
  dialer.open = (_inner, id) => open(id);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const secondLock = secondWorkspace ? await r.watch({ topic: "lock", workspace: "w2" }) : null;
  const pair = async () => (await lock()).me.pair;
  return { ...r, ways, dials, hellos, lock, pair, secondLock };
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
