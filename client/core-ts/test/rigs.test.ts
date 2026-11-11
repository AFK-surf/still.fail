// A workspace's rigs (src/rigs.ts, a station that only runs tasks): what the stations say of them merged into the `rigs` topic; a rig added
// by a command that names its person's own lock; and what that person signs here (a chat's grant, one taken back,
// 免批准) taken by the rig itself (station/src/rig/grants.ts), which checks it against the lock it pinned.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Result } from "effect";
import { RigGrants } from "../../../station/src/rig/grants.ts";
import { CoreError, HostError } from "../src/error.ts";
import type { Entry } from "../src/lock.ts";
import { shortCode } from "../src/lock.ts";
import { PersonalLock } from "../src/personal-lock.ts";
import { Rigs, parseRig } from "../src/rigs.ts";
import { Devices, parseDevice } from "../src/devices.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { FakeHost } from "../src/testing.ts";
import { sha256 } from "../src/util.ts";

const WS = "ws1";
const SUB = "pat";
const RIG = "aa".repeat(32);
const ST1 = "11".repeat(32);
const ST2 = "22".repeat(32);

/// A device of `pat`'s with their own lock on it, the workspace as the cloud lists it, and two stations that answer.
function world() {
  const host = new FakeHost();
  host.appKeys = true;
  const sealed = new Map<string, Uint8Array>();
  const asks = { n: 0 };
  host.secureSet = (key: string, value: Uint8Array) => Effect.sync(() => void sealed.set(key, value));
  host.secureGet = (key: string, opts: { user: boolean }) => {
    if (opts.user) asks.n++;
    return Effect.succeed(sealed.get(key) ?? null);
  };
  host.secureAsk = () => Effect.sync(() => void asks.n++);
  const runner = new Runner(host.time.clock);
  const kept = { entries: [] as Entry[] };
  const personal = new PersonalLock({
    host, runner, device: () => Effect.succeed("dd".repeat(32)), label: () => "phone", changed: () => {},
    cloud: (_sub, method, _path, body) => Effect.sync(() => {
      if (method === "POST") kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const view: any = {
    stations: [{ id: ST1, name: "willow" }, { id: ST2, name: "nas" }],
    rigs: [{ id: RIG, name: "build-box", owner: SUB, owner_email: "pat@example.com", owner_name: "Pat" }, { id: "bb".repeat(32), name: "theirs", owner: "lee", owner_email: "lee@example.com", owner_name: "Lee" }],
  };
  const asked: { station: string; method: string; path: string; body: any }[] = [];
  const cloudAsked: { method: string; path: string; body: any }[] = [];
  /// How each station answers: its `GET /rigs`, and whether it is reached at all.
  const stations = new Map<string, { up: boolean; rigs: any[] }>([[ST1, { up: true, rigs: [] }], [ST2, { up: true, rigs: [] }]]);
  const invalidated: string[] = [];
  const lock = { locked: false, as: null as "lock" | "person" | null };
  const rigs = new Rigs({
    host,
    store: { invalidate: (topic: any) => void invalidated.push(`${topic.topic} ${topic.workspace}`) } as any,
    personal: () => personal,
    subOf: (ws) => (ws === WS ? SUB : null),
    view: () => view,
    call: (station, method, path, body) =>
      Effect.suspend(() => {
        asked.push({ station: station.station, method, path, body });
        const s = stations.get(station.station)!;
        if (!s.up) return Effect.fail(new CoreError("network", "not reached"));
        return Effect.succeed(method === "GET" && path === "/rigs" ? { workspace: WS, rigs: s.rigs } : { ok: true, delivered: true });
      }),
    cloud: (_sub, method, path, body) => Effect.sync(() => (cloudAsked.push({ method, path, body }), { token: "tok", install: "curl -fsSL https://x/install.sh | sh -s -- tok", installWindows: "& (irm https://x/install.ps1) tok", command: "stillfail station enroll https://x tok", rig: true })),
    first: (asks) => Effect.all(asks.map((a) => Effect.result(a)), { concurrency: "unbounded" }),
    lock: {
      locked: () => lock.locked,
      enrolled: (_sub, _ws, made: any) => Effect.succeed(lock.locked ? { ...made, install: `${made.install} LOCKHASH`, installWindows: `${made.installWindows} LOCKHASH`, command: `${made.command} --lock LOCKHASH` } : made),
      signsAs: () => lock.as,
      signAdd: () => Effect.succeed({ key: "ed25519:lockkey", sig: "00" }),
    },
    sha256,
  });
  return { host, runner, personal, rigs, view, asked, cloudAsked, stations, invalidated, lock, asks, run: <A>(e: Effect.Effect<A, CoreError>) => runner.run(e) };
}

const call = (name: string, params: unknown) => parseRig(name, params)!;

test("a rig is added by a command that names its person's own lock, begun with the first", async () => {
  const w = world();
  try {
    // No lock of their own yet is no step of its own (as a phone's first grant): it is begun as the first is added.
    assert.equal(w.personal.root(SUB), null);
    const made: any = await w.run(w.rigs.run(call("rig.add", { workspace: WS, name: "build-box" })));
    const root = w.personal.root(SUB)!;
    assert.equal(w.personal.standing(SUB), "member");
    assert.deepEqual(w.cloudAsked, [{ method: "POST", path: `/v1/workspaces/${WS}/rigs/enrollments`, body: { name: "build-box" } }]);
    assert.equal(made.install, `curl -fsSL https://x/install.sh | sh -s -- tok rig:${root}`);
    assert.equal(made.installWindows, `& (irm https://x/install.ps1) tok rig:${root}`);
    assert.equal(made.command, `stillfail station enroll https://x tok --rig ${root}`);
    // Security mode: the workspace lock's hash first, as a station's command has it.
    w.lock.locked = true;
    const locked: any = await w.run(w.rigs.run(call("rig.add", { workspace: WS, name: "gpu" })));
    assert.equal(locked.install, `curl -fsSL https://x/install.sh | sh -s -- tok LOCKHASH rig:${root}`);
    assert.equal(locked.command, `stillfail station enroll https://x tok --lock LOCKHASH --rig ${root}`);
    // A web page keeps no key of their own lock.
    w.host.appKeys = false;
    const web = await w.runner.run(Effect.result(w.rigs.run(call("rig.add", { workspace: WS, name: "x" }))));
    assert.ok(Result.isFailure(web) && web.failure.code === "rig_app_only");
  } finally {
    w.runner.shutdown();
  }
});

test("the topic: the cloud's list, with how the stations last said each rig is and the requests of their chats", async () => {
  const w = world();
  try {
    let v = w.rigs.value(WS);
    assert.deepEqual([v.locked, v.app, v.personal], [false, true, "none"]);
    assert.deepEqual(v.rigs.map((r: any) => [r.name, r.mine, r.vouched, r.reached, r.known, r.open, r.code, r.grants, r.requests]), [
      ["build-box", true, true, null, false, false, shortCode(RIG), [], []],
      ["theirs", false, true, null, false, false, shortCode("bb".repeat(32)), [], []],
    ]);
    // One station heard the rig a while ago, the other since: the later says how it is; each says its own chats' asks.
    const grant = { request: "r1", station: ST2, session: "s", chat: "CHAT/1", title: "Fix CI", by: "lee@example.com", timeout: { kind: "idle", seconds: 3600 }, exp: 2000, until: 1500 };
    w.stations.get(ST1)!.rigs = [{ id: RIG, at: 100, reached: true, open: true, settings: 3, grants: [], requests: [{ id: "q1", session: "s1", chat: "CHAT/2", title: "A build", by: "kim@example.com", reason: "make", timeout: { kind: "fixed", seconds: 600 }, at: 50, status: "pending" }] }];
    w.stations.get(ST2)!.rigs = [{ id: RIG, at: 200, reached: true, open: false, settings: 4, grants: [grant], requests: [] }];
    await w.run(w.rigs.read(`${WS}/${ST1}`));
    w.rigs.heard(`${WS}/${ST2}`, "rigs", { workspace: WS, rigs: w.stations.get(ST2)!.rigs });
    w.rigs.heard(`${WS}/${ST2}`, "screens", { workspace: WS, rigs: [] });
    w.rigs.heard(`${WS}/${ST2}`, "rigs", { workspace: "another", rigs: [] });
    // (their devices are the `devices` topic's too)
    assert.deepEqual(w.invalidated, [`rigs ${WS}`, `devices ${WS}`, `rigs ${WS}`, `devices ${WS}`]);
    v = w.rigs.value(WS);
    const mine = v.rigs[0];
    assert.deepEqual([mine.reached, mine.known, mine.open], [true, true, false]);
    assert.deepEqual(mine.grants, [{ request: "r1", station: ST2, stationName: "nas", session: "s", chat: "CHAT/1", title: "Fix CI", by: "lee@example.com", timeoutKind: "idle", timeoutSeconds: 3600, exp: 2000, until: 1500 }]);
    assert.deepEqual(mine.requests, [{ id: "q1", station: `${WS}/${ST1}`, session: "s1", chat: "CHAT/2", title: "A build", by: "kim@example.com", reason: "make", timeoutKind: "fixed", timeoutSeconds: 600, at: 50, status: "pending" }]);
    // A station taken out of the workspace says nothing more.
    w.view.stations = [{ id: ST1, name: "willow" }];
    assert.deepEqual([w.rigs.value(WS).rigs[0].open, w.rigs.value(WS).rigs[0].grants], [true, []]);
    // Security mode: a rig counts once a station says its person signed for it.
    w.lock.locked = true;
    assert.equal(w.rigs.value(WS).rigs[0].vouched, false);
    w.rigs.heard(`${WS}/${ST1}`, "rigs", { workspace: WS, rigs: [{ id: RIG, at: 300, reached: true, vouched: true, open: false, grants: [], requests: [] }] });
    assert.equal(w.rigs.value(WS).rigs[0].vouched, true);
  } finally {
    w.runner.shutdown();
  }
});

test("what the rig's person signs here, the rig takes: a grant, 免批准, a grant taken back; another's rig they do not sign for", async () => {
  const w = world();
  const dir = mkdtempSync(join(tmpdir(), "core-rigs-"));
  try {
    await w.run(w.personal.open(SUB, "turn it on"));
    // The rig, as it joined with the command: its person's lock pinned.
    const ended: string[] = [];
    const now = Math.floor(w.host.nowMs() / 1000);
    const rig = new RigGrants({
      path: join(dir, "grants.json"), self: () => ({ id: RIG, workspace: WS, owner: SUB, person: w.personal.root(SUB)! }),
      busy: () => false, stop: () => {}, running: () => [], ended: (e) => void ended.push(`${e.request} ${e.why}`), changed: () => {},
      fibers: { now: () => now * 1000, after: () => () => {}, close: async () => {} } as any,
    });
    const ask = { rig: RIG, name: "build-box", session: "sess", chat: "CHAT/1", title: "Fix CI", by: "lee@example.com" };
    const before = w.asks.n;
    await w.run(w.rigs.run(call("rig.decide", { station: `${WS}/${ST1}`, request: "r1", allow: true, timeoutKind: "fixed", timeoutSeconds: 7200, ask })));
    assert.equal(w.asks.n, before + 1, "the person is asked: their key is used");
    const sent = w.asked.at(-1)!;
    assert.deepEqual([sent.station, sent.method, sent.path, sent.body.allow], [ST1, "POST", "/rigs/requests/r1/decide", true]);
    assert.deepEqual(sent.body.signed.body, { v: 1, sub: SUB, ws: WS, rig: RIG, station: ST1, session: "sess", chat: "CHAT/1", request: "r1", title: "Fix CI", by: "lee@example.com", timeout: { kind: "fixed", seconds: 7200 }, at: now, exp: now + 7200 });
    // Over the wire as JSON, then to the rig by the chat's station.
    const wire = JSON.parse(JSON.stringify(sent.body));
    assert.deepEqual(rig.grant(ST1, wire.signed, wire.chain), { until: now + 7200 });
    assert.equal(rig.refusal(WS, ST1, "sess"), null);

    // Refused: nothing signed, the person not asked.
    const quiet = w.asks.n;
    await w.run(w.rigs.run(call("rig.decide", { station: `${WS}/${ST1}`, request: "r2", allow: false, ask })));
    assert.deepEqual([w.asked.at(-1)!.path, w.asked.at(-1)!.body, w.asks.n], ["/rigs/requests/r2/decide", { allow: false }, quiet]);
    assert.throws(() => parseRig("rig.decide", { station: `${WS}/${ST1}`, request: "r3", allow: true, timeoutKind: "idle", timeoutSeconds: 45, ask }), /timeout must be idle or fixed/);

    // 免批准: to every station at once (one that is away does not hold it up), numbered after the settings known.
    w.stations.get(ST1)!.up = false;
    await w.run(w.rigs.run(call("rig.setOpen", { workspace: WS, rig: RIG, open: true })));
    const settings = w.asked.filter((a) => a.path === `/rigs/${RIG}/settings`);
    assert.deepEqual(settings.map((a) => a.station).sort(), [ST1, ST2]);
    rig.settings(JSON.parse(JSON.stringify(settings[0]!.body.signed)), settings[0]!.body.chain);
    assert.equal(rig.open(), true);
    await w.run(w.rigs.run(call("rig.setOpen", { workspace: WS, rig: RIG, open: false })));
    rig.settings(JSON.parse(JSON.stringify(w.asked.filter((a) => a.path === `/rigs/${RIG}/settings`).at(-1)!.body.signed)));
    assert.equal(rig.open(), false, "the later settings are the newer ones");
    // Reached by none: said, nothing lost for good (the person asks again).
    w.stations.get(ST2)!.up = false;
    const away = await w.runner.run(Effect.result(w.rigs.run(call("rig.setOpen", { workspace: WS, rig: RIG, open: true }))));
    assert.ok(Result.isFailure(away) && away.failure.code === "rig_no_station");
    w.stations.get(ST1)!.up = true;
    w.stations.get(ST2)!.up = true;

    // Taken back: through the chat's own station, on what is signed; the rig ends it.
    await w.run(w.rigs.run(call("rig.revoke", { workspace: WS, rig: RIG, request: "r1", station: ST1 })));
    const revoke = w.asked.at(-1)!;
    assert.deepEqual([revoke.station, revoke.path, revoke.body.rig], [ST1, "/rigs/requests/r1/revoke", RIG]);
    rig.revoke(JSON.parse(JSON.stringify(revoke.body.signed)), revoke.body.chain);
    assert.deepEqual(ended, ["r1 revoked"]);
    assert.match(rig.refusal(WS, ST1, "sess")!, /no grant/);

    // Another person's rig: nothing is signed for it here.
    for (const c of [call("rig.setOpen", { workspace: WS, rig: "bb".repeat(32), open: true }), call("rig.revoke", { workspace: WS, rig: "bb".repeat(32), request: "x", station: ST1 }), call("rig.decide", { station: `${WS}/${ST1}`, request: "r9", allow: true, ask: { ...ask, rig: "bb".repeat(32) } })]) {
      const r = await w.runner.run(Effect.result(w.rigs.run(c)));
      assert.ok(Result.isFailure(r) && r.failure.code === "rig_not_owner");
    }
  } finally {
    w.runner.shutdown();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a station's mode: made one that only runs tasks by asking it first, then the cloud; whole again by its person's signature, then the cloud", async () => {
  const w = world();
  const dir = mkdtempSync(join(tmpdir(), "core-rigs-"));
  try {
    // Only tasks: the station itself is told first (by this device, with the lock to pin: begun here, there being
    // none yet), then the cloud lists it so.
    await w.run(w.rigs.run(call("rig.setMode", { workspace: WS, station: ST2, mode: "tasks" })));
    const root = w.personal.root(SUB)!;
    assert.deepEqual(w.asked, [{ station: ST2, method: "POST", path: "/mode", body: { mode: "tasks", person: root } }]);
    assert.deepEqual(w.cloudAsked, [{ method: "PATCH", path: `/v1/workspaces/${WS}/stations/${ST2}`, body: { mode: "tasks" } }]);
    // The station not reached: the cloud is not asked, so nothing lists it as what it is not.
    w.stations.get(ST2)!.up = false;
    const away = await w.runner.run(Effect.result(w.rigs.run(call("rig.setMode", { workspace: WS, station: ST2, mode: "tasks" }))));
    assert.ok(Result.isFailure(away));
    assert.equal(w.cloudAsked.length, 1);
    w.stations.get(ST2)!.up = true;

    // Whole again: its person's alone to sign, carried by a station to the rig, which takes it; then the cloud.
    const theirs = await w.runner.run(Effect.result(w.rigs.run(call("rig.setMode", { workspace: WS, station: "bb".repeat(32), mode: "full" }))));
    assert.ok(Result.isFailure(theirs) && theirs.failure.code === "rig_not_owner");
    w.asked.length = 0;
    const before = w.asks.n;
    await w.run(w.rigs.run(call("rig.setMode", { workspace: WS, station: RIG, mode: "full" })));
    assert.equal(w.asks.n, before + 1, "the person is asked: their key is used");
    const sent = w.asked.find((a) => a.path === `/rigs/${RIG}/full`)!;
    assert.equal(sent.method, "POST");
    assert.deepEqual(w.cloudAsked.at(-1), { method: "PATCH", path: `/v1/workspaces/${WS}/stations/${RIG}`, body: { mode: "full" } });
    const now = Math.floor(w.host.nowMs() / 1000);
    const rig = new RigGrants({
      path: join(dir, "grants.json"), self: () => ({ id: RIG, workspace: WS, owner: SUB, person: root }),
      busy: () => false, stop: () => {}, running: () => [], ended: () => {}, changed: () => {},
      fibers: { now: () => now * 1000, after: () => () => {}, close: async () => {} } as any,
    });
    const wire = JSON.parse(JSON.stringify(sent.body));
    assert.deepEqual(rig.full(wire.signed, wire.chain).body, { v: 1, sub: SUB, ws: WS, rig: RIG, at: now });
    assert.throws(() => parseRig("rig.setMode", { workspace: WS, station: RIG, mode: "half" }));
  } finally {
    w.runner.shutdown();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("security mode: the rig's code compared, then signed for with the key the workspace's lock knows this person by", async () => {
  const w = world();
  try {
    await w.run(w.personal.open(SUB, "turn it on"));
    w.lock.locked = true;
    const vouch = (code: string) => w.runner.run(Effect.result(w.rigs.run(call("rig.vouch", { workspace: WS, rig: RIG, code }))));
    const wrong = await vouch("AAA-AAA");
    assert.ok(Result.isFailure(wrong) && wrong.failure.code === "rig_wrong_code");
    // A device that signs nothing in this workspace's lock.
    const unsigned = await vouch(shortCode(RIG));
    assert.ok(Result.isFailure(unsigned) && unsigned.failure.code === "lock_no_signer");
    // One of their own devices in the lock: its lock key, the person not asked.
    w.lock.as = "lock";
    const before = w.asks.n;
    assert.ok(Result.isSuccess(await vouch(shortCode(RIG).toLowerCase())));
    const adds = w.asked.filter((a) => a.path === `/rigs/${RIG}/add`);
    assert.deepEqual(adds.map((a) => a.station).sort(), [ST1, ST2]);
    assert.deepEqual([adds[0]!.body.signed.sig.key, adds[0]!.body.signed.body.sub, adds[0]!.body.signed.body.ws, adds[0]!.body.signed.body.rig, w.asks.n], ["ed25519:lockkey", SUB, WS, RIG, before]);
    // Bound to their own lock there: a key on it, the person asked.
    w.lock.as = "person";
    assert.ok(Result.isSuccess(await vouch(shortCode(RIG))));
    assert.equal(w.asks.n, before + 1);
    assert.notEqual(w.asked.at(-1)!.body.signed.sig.key, "ed25519:lockkey");
  } finally {
    w.runner.shutdown();
  }
});

test("devices: a whole station's added there; a rig's signed by its person and taken by the rig; granted alone, 免批准 on one; one list", async () => {
  const w = world();
  const dir = mkdtempSync(join(tmpdir(), "core-devices-"));
  try {
    await w.run(w.personal.open(SUB, "turn it on"));
    const now = Math.floor(w.host.nowMs() / 1000);
    const rig = new RigGrants({
      path: join(dir, "grants.json"), self: () => ({ id: RIG, workspace: WS, owner: SUB, person: w.personal.root(SUB)! }),
      busy: () => false, stop: () => {}, running: () => [], ended: () => {}, changed: () => {},
      fibers: { now: () => now * 1000, after: () => () => {}, close: async () => {} } as any,
    });
    const devices = new Devices({
      host: w.host, store: { invalidate: (topic: any) => void w.invalidated.push(`${topic.topic} ${topic.workspace}`) } as any,
      rigs: () => w.rigs, personal: () => w.personal, subOf: () => SUB, emailOf: () => "pat@example.com", view: () => w.view,
      call: (station, method, path, body) => Effect.sync(() => (w.asked.push({ station: station.station, method, path, body }), method === "GET" ? { workspace: WS, devices: [], phones: [] } : { ok: true, delivered: true })),
    });
    const dcall = (name: string, params: unknown) => parseDevice(name, params)!;
    // On a whole station: asked of that station, which keeps it (no signature).
    await w.run(devices.run(dcall("device.add", { workspace: WS, station: ST1, name: "cam", kind: "tcp", target: "10.0.0.5:554" })));
    assert.deepEqual(w.asked.at(-1), { station: ST1, method: "POST", path: "/devices", body: { name: "cam", kind: "tcp", target: "10.0.0.5:554" } });
    assert.throws(() => parseDevice("device.add", { workspace: WS, station: ST1, name: "x", kind: "usb", target: "a" }), /kind/);
    const bad = await w.runner.run(Effect.result(devices.run(dcall("device.add", { workspace: WS, station: ST1, name: "x", kind: "tcp", target: "nohost" }))));
    assert.ok(Result.isFailure(bad));
    // On the rig: signed by its person, carried by a station; the rig takes it.
    await w.run(devices.run(dcall("device.add", { workspace: WS, station: RIG, name: "board", kind: "serial", target: "/dev/ttyUSB0", baud: 9600 })));
    const added = w.asked.at(-1)!;
    assert.equal(added.path, `/rigs/${RIG}/devices`);
    rig.device(JSON.parse(JSON.stringify(added.body.signed)), JSON.parse(JSON.stringify(added.body.chain)));
    const board = rig.devices()[0]!;
    assert.deepEqual([board.name, board.kind, board.target, board.baud], ["board", "serial", "/dev/ttyUSB0", 9600]);
    // Another's rig: not theirs to attach to.
    const theirs = await w.runner.run(Effect.result(devices.run(dcall("device.add", { workspace: WS, station: "bb".repeat(32), name: "x", kind: "tcp", target: "a:1" }))));
    assert.ok(Result.isFailure(theirs) && theirs.failure.code === "rig_not_owner");
    // The stations say what is attached: one list, whose each is.
    devices.heard(`${WS}/${ST1}`, "devices", { workspace: WS, devices: [{ id: "0123456789abcdef", name: "cam", kind: "tcp", target: "10.0.0.5:554", owner: SUB, owner_email: "pat@example.com", owner_name: "Pat" }], phones: [] });
    w.rigs.heard(`${WS}/${ST2}`, "rigs", { workspace: WS, rigs: [{ id: RIG, at: 10, reached: true, open: false, settings: 0, devices: [{ ...board, open: false, settings: 0 }], grants: [], requests: [{ id: "q1", session: "s1", chat: "CHAT/9", title: "Flash it", by: "lee@example.com", reason: "flash", timeout: { kind: "idle", seconds: 3600 }, at: 5, status: "pending", device: board.id, deviceName: "board" }] }] });
    const v = devices.value(WS);
    assert.deepEqual(v.devices.map((d: any) => [d.name, d.via, d.stationName, d.mine, d.open]), [["cam", "station", "willow", true, true], ["board", "rig", "build-box", true, false]]);
    assert.deepEqual(v.devices[1].requests.map((q: any) => [q.id, q.station]), [["q1", `${WS}/${ST2}`]]);
    // (the rig's own row does not list a request for one of its devices)
    assert.deepEqual(w.rigs.value(WS).rigs[0].requests, []);
    // A chat's grant of the device alone: what is signed names it, and the rig lets that chat reach it, not run tasks.
    const ask = { rig: RIG, name: "build-box", session: "s1", chat: "CHAT/9", title: "Flash it", by: "lee@example.com", device: board.id, deviceName: "board" };
    await w.run(w.rigs.run(call("rig.decide", { station: `${WS}/${ST2}`, request: "q1", allow: true, timeoutKind: "fixed", timeoutSeconds: 600, ask })));
    const decided = JSON.parse(JSON.stringify(w.asked.at(-1)!.body));
    assert.equal(decided.signed.body.device, board.id);
    rig.grant(ST2, decided.signed, decided.chain);
    assert.equal(rig.deviceRefusal(WS, ST2, "s1", board.id), null);
    assert.notEqual(rig.refusal(WS, ST2, "s1"), null);
    // 免批准 on the device alone.
    await w.run(devices.run(dcall("device.setOpen", { workspace: WS, station: RIG, device: board.id, open: true })));
    rig.settings(JSON.parse(JSON.stringify(w.asked.at(-1)!.body.signed)));
    assert.equal(rig.view()!.devices[0]!.open, true);
    assert.equal(rig.open(), false);
    // Taken off: signed as removed; a whole station's, asked of it.
    await w.run(devices.run(dcall("device.remove", { workspace: WS, station: RIG, device: board.id })));
    rig.device(JSON.parse(JSON.stringify(w.asked.at(-1)!.body.signed)));
    assert.deepEqual(rig.devices(), []);
    await w.run(devices.run(dcall("device.remove", { workspace: WS, station: ST1, device: "0123456789abcdef" })));
    assert.deepEqual([w.asked.at(-1)!.method, w.asked.at(-1)!.path], ["DELETE", "/devices/0123456789abcdef"]);
  } finally {
    w.runner.shutdown();
    rmSync(dir, { recursive: true, force: true });
  }
});
