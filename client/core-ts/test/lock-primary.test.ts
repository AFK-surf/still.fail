// Primary trusted devices (主授信设备, src/lock-primary.ts, docs/workspace-lock.md): an app its person made one is told
// wherever its app is when a new device of theirs asks to be approved face to face. Made one, it is kept on the device,
// its push registration says so (the cloud wakes those: cloud/src/push.ts lockWake) and the lock's view does; a web
// page cannot be one. A push about a new device asking is shown there, not elsewhere, not with the app in view; a new
// device showing this one's code, the app behind, puts up a notification of its own (never the code). A new device
// asking has the cloud wake its person's, once for each account. None made one, nothing of it happens. Against the
// lock rig's cloud, on the test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import { PRIMARY_KEY } from "../src/lock-primary.ts";
import { type Duplex, dialer, serveTrusted } from "../src/views/pair.ts";
import { ME, PHONE, elsewhere, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { stationReplies } from "./station-fixture.ts";

type Rig = Awaited<ReturnType<typeof rig>>;

/// What the rig's cloud is asked to push to (`/v1/push`) and to wake (`lock/wake`), answered; the rest as the rig's.
function seen(r: Rig) {
  const pushes: any[] = [];
  const wakes: { url: string; body: any }[] = [];
  stationReplies(r.host, (req) => {
    const body = req.body ? JSON.parse(new TextDecoder().decode(req.body)) : null;
    if (req.method === "POST" && req.url.endsWith("/v1/push")) {
      pushes.push(body);
      return {};
    }
    if (req.method === "POST" && /\/v1\/workspaces\/[^/]+\/lock\/wake$/.test(req.url)) {
      wakes.push({ url: req.url, body });
      return { sent: 1 };
    }
    return r.cloud.reply(req);
  });
  return { pushes, wakes };
}

test("made one of its person's primary trusted devices: kept on this device, said with its push registration and in the lock's view", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  const { pushes } = seen(r);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  assert.deepEqual([(await lock()).primary, (await lock()).canBePrimary], [false, true]);
  await r.ask("push.register", { kind: "fcm", token: "t" });
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].primary, undefined, "none made one: as before");
  await r.ask("lock.primary", { workspace: "ws", on: true });
  assert.equal((await lock()).primary, true);
  assert.deepEqual(pushes.slice(1).map((p) => [p.token, p.primary]), [["t", true]], "given again, saying so");
  assert.equal(new TextDecoder().decode(r.host.storage.get(PRIMARY_KEY)), "1");
  // Said again as it is: nothing given again.
  await r.ask("lock.primary", { workspace: "ws", on: true });
  assert.equal(pushes.length, 2);
  await r.ask("lock.primary", { workspace: "ws", on: false });
  assert.equal((await lock()).primary, false);
  assert.deepEqual(pushes.slice(2).map((p) => [p.token, p.primary]), [["t", undefined]]);
  assert.equal(r.host.storage.get(PRIMARY_KEY), undefined);
});

test("a web page, or an app that does not sign here, cannot be one", async () => {
  const page = await rig((me) => ({ ws: genesis("ws", me, true) }), (host) => {
    host.appKeys = false;
  });
  const v = await (await page.watch({ topic: "lock", workspace: "ws" }))();
  assert.equal(v.canBePrimary, false);
  await assert.rejects(page.ask("lock.primary", { workspace: "ws", on: true }));
  // An app waiting to be approved (not in the lock): not here.
  const waiting = await rig(() => ({ ws: genesis("ws", elsewhere(), false) }));
  assert.equal((await (await waiting.watch({ topic: "lock", workspace: "ws" }))()).canBePrimary, false);
});

test("a push about a new device asking is shown on a primary trusted device whose app is not in view, and nowhere else", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  seen(r);
  await r.watch({ topic: "lock", workspace: "ws" });
  const pushed = () => r.ask("notice.pushed", { workspace: "ws", kind: "pair", title: "有新设备申请加入" });
  assert.deepEqual(await pushed(), { show: false }, "not one: as before");
  await r.ask("lock.primary", { workspace: "ws", on: true });
  assert.deepEqual(await pushed(), { show: true });
  // In view, the code comes up by itself once the new device reaches it.
  await r.ask("client.focus", { visible: true, focused: true });
  assert.deepEqual(await pushed(), { show: false });
});

test("a new device showing a primary trusted device's code, its app behind: a notification says so, never the code", async () => {
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME, [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }]) }));
  seen(r);
  await r.watch({ topic: "lock", workspace: "ws" });
  const notify = await r.watch({ topic: "notify", workspace: "ws" });
  const ask = async () => {
    const [trusted, phone] = await pipe();
    r.core.inner.runner.fork(serveTrusted(r.core.inner, "aa".repeat(32), ME, trusted));
    await Effect.runPromise(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", "aa".repeat(32), "s1") }], kind: "web", label: "Chrome · Windows", sign_key: null }));
    await r.host.time.pass(500);
    return phone;
  };
  // Not one: nothing but the prompt in the app, as before.
  await ask();
  assert.deepEqual((await notify()).show, []);
  await r.ask("lock.primary", { workspace: "ws", on: true });
  const phone = await ask();
  const shown = (await notify()).show;
  assert.equal(shown.length, 1);
  assert.deepEqual([shown[0].kind, shown[0].tag, shown[0].title], ["pair", `pair/${"aa".repeat(32)}`, t("core-misc.lock.pairNotice.title")]);
  assert.match(shown[0].body, /Chrome · Windows/);
  const code = (await r.ask("lockPrompt.state", {})).pairing[0].code as string;
  assert.ok(!JSON.stringify(shown).includes(code), "the code is shown in the app only");
  void phone;
});

test("asking to be approved has the cloud wake its person's primary trusted devices, once for each account", async () => {
  const owner = elsewhere();
  const r = await rig(() => ({
    ws: genesis("ws", owner, false, [], {}, ME, [{ id: "e1".repeat(32), sub: "s1", kind: "app", label: "still.fail Android · Pixel 8", sign_key: owner.id }]),
    w2: genesis("w2", owner, false, [], {}, ME, [{ id: "e1".repeat(32), sub: "s1", kind: "app", label: "still.fail Android · Pixel 8", sign_key: owner.id }]),
  }));
  const { wakes } = seen(r);
  r.core.inner.mesh = () => Effect.succeed({ deviceId: () => ME, lockClaim: () => null } as never);
  dialer.open = (): Effect.Effect<Duplex, CoreError> => Effect.fail(CoreError.plainly("pair", "not reached"));
  await r.watch({ topic: "lock", workspace: "ws" });
  await r.watch({ topic: "lock", workspace: "w2" });
  await r.ask("lock.pair", { workspace: "ws" });
  await r.host.time.pass(1_000);
  assert.equal(wakes.length, 1, "one account: woken once, for the first workspace it waits in");
  assert.match(wakes[0]!.url, /\/v1\/workspaces\/(ws|w2)\/lock\/wake$/);
  assert.equal(wakes[0]!.body.device, ME);
  assert.equal(typeof wakes[0]!.body.label, "string");
});
