// The locks end to end against the local still.fail (scripts/e2e-local.sh locks, after up; locks-all, the side run's):
// alice's devices and bob's, each still.fail's TS core in Node in a process of its own (client/core-ts hosts/node.ts,
// on the station's mesh addon: one core a process, as its calls' handlers are the module's), each signed in with the
// dev cloud's mock account and keeping its keys in a file (a sealer that asks no one, counting what it would have
// asked), as a person uses the app (round 13's first three devices and round 14's two as apps from before, sealing
// nothing; round 16's a web page, keeping no keys):
//   1-3 A turns safe mode on: alice's own lock begun by A by itself and bound, nobody asked; A keeps an item in a
//     vault; C, asking from its waiting page with A showing the code, lands on alice's own lock and is given the
//     vault; A takes C off: C taken out, the vault keyed anew; B joins the own lock face to face, is let in and given
//     the vault; A, its vault locked, takes B off: B refused, the vault keyed anew (the box key read); B joins again;
//     D joins through B; the station restarted, D taken off while it is frozen, B taken off while its app is closed;
//   4 B takes A, the first device, off; the last one left cannot take itself off;
//   5 A's app installed anew (its data and keys gone): a new device, let in only as it joins again;
//   6 the cloud frozen while a device joins and is taken off: the stations carry the locks;
//   7 a second station in the lock, the first frozen while a device joins and is taken off through the second;
//   7b two stations that took different entries (each up while the other was not): one chain once both are up, the
//     entry that lost signed again by its device, both changes on it, nobody asked;
//   8 bob, a member: his first device approved by the owner face to face, which begins his own lock by itself (bound,
//     nobody asked), a vault of his own, his second device on his own lock; taken out of the workspace by the owner,
//     out of its lock with his devices, refused;
//   9 a second workspace of alice's, safe mode on there too, its own station: a device joining her own lock once is let
//     in by both, taken off it refused by both;
//   10 safe mode turned off in the second: its station lets that device in again, the first still refuses it;
//   11 round 7's second station taken out of the first workspace: out of its lock too;
//   12 bob made a member again: his first device approved by the owner once more, his own lock bound again, his other
//     device on it let in; then every device of his lost: a new one finds none to approve it, says so (his own lock
//     begun anew), the owner takes him out and makes him a member again and approves it as his first;
//   13 carol, a member whose three devices are apps from before (they seal nothing): the first approved by the owner,
//     each next by the one before, no lock of her own; two apps updated say their keys in the workspace's lock and
//     nobody begins; the first updated begins her own lock with the three on it, the others take it, it is bound,
//     nobody asked; a vault of hers then, and a new device of hers asking from its waiting page lands on her own lock;
//   14 dave, a member whose two devices are apps from before: the second, updated, turns his own lock on by an act that
//     asks him (the first, the one to begin, not updated); the first, updated, is outside it and still let in, nobody
//     shut out, he not bound; it joins with one approval, and he is bound;
//   15 erin, a member of both workspaces: a station of hers asleep (Two's, switched off once her device had reached
//     it, her app then started again) holds the beginning of her own lock back; switched on again, her device begins
//     it by itself and it is bound;
//   16 alice's web page in the first workspace, her own lock bound there: refused, it asks from its waiting page, B
//     shows the code; it is in the workspace's lock as a web page's for 30 days at most, let in, signing nothing, no
//     vault, her own lock untouched; started again, let in with nobody asked; B takes it out on 设置 › 安全: refused;
//   17 a station enrolled in the first workspace with its token alone, not in its lock (#5540): B reads it alone and
//     still holds the lock the first keeps, started again too; B's 「保护」 takes it in and it keeps the lock; out again;
//   18 no station up, the cloud up: B removes A installed anew, answered within seconds as pending, its page showing it
//     waiting for the station by name, A installed anew still listed; the station started: within seconds the removal
//     is on its chain, nothing pending, A installed anew refused.
// Each check says PASS or FAIL; it goes on after a failure where it can, and exits 1 if any failed. E2E_SF_SRC,
// E2E_ORIGIN, E2E_PEER_DATA as peer.ts; E2E_WORK, E2E_STATION as e2e-local.sh's.
import { readFileSync, writeFileSync } from "node:fs";
import { check, Device, dir, fail, failures, type J, log, must, stationDo, stationSays, whenChanged, within } from "./device.ts";

const lockDevices = (l: J): J[] => (l.members ?? []).flatMap((m: J) => (m.groups ?? []).flatMap((g: J) => g.devices ?? []));
const appIds = (l: J): string[] => lockDevices(l).filter((d) => d.kind === "app").map((d) => d.id.slice(0, 8)).sort();
const short = (s: J) => JSON.stringify({ state: s.state, cause: s.cause, message: s.message });

const a = new Device("A");
const b = new Device("B");
const c = new Device("C");
const d = new Device("D");
const e = new Device("E");
const f = new Device("F");
const g = new Device("G");
const h = new Device("H", "bob");
const i = new Device("I", "bob");
const j = new Device("J");
const k = new Device("K", "bob");
// (round 13's: carol's apps from before the update, sealing nothing, and a new one of hers; named so as `l` and `n`
// are the file's names for a lock and a length)
const lDev = new Device("L", "carol", { sealed: false });
const mDev = new Device("M", "carol", { sealed: false });
const nDev = new Device("N", "carol", { sealed: false });
const oDev = new Device("O", "carol");
// (round 14's: dave's two apps from before; round 15's: erin's one, sealing)
const d1 = new Device("D1", "dave", { sealed: false });
const d2 = new Device("D2", "dave", { sealed: false });
const e1 = new Device("E1", "erin");
// (round 16's: a web page of alice's, keeping no keys; named so as `w` is the file's name for a workspace)
const wDev = new Device("W", "alice", { page: true });
let dKey = "";
let dBase = "";
let sub = "";
/// The test station's data: its database, the lock chains it keeps (scripts/e2e-local.sh lock-state reads them).
const stationData = `${process.env.E2E_STATION}/data`;
try {
  const { workspace, station } = await a.signIn();
  sub = a.sub;
  log(`A signed in as ${sub}: workspace ${workspace}, station ${station}`);
  await a.stationState(workspace, (s) => s.state === "online", 120_000);
  const baseOf = async (d: Device) => (await d.lock(workspace, (l) => typeof l.me?.device === "string")).me.device as string;
  const aBase = await baseOf(a);

  await must("A turns safe mode on, the only device in it", async () => {
    const draft = await a.until({ topic: "lockDraft", workspace }, (v) => (v?.ready ? v : undefined), 120_000);
    for (const d of draft.devices ?? []) if (!d.current) await a.call("lock.toggle", { workspace, id: d.id });
    await a.call("lock.open", { workspace });
    await a.lock(workspace, (l) => l.locked && l.signs);
    await a.stationState(workspace, (s) => s.state === "online");
  });
  // (everyone in safe mode comes to have a lock of their own with nobody asked: A, the only device of alice's there and
  // sealing its keys, is the one to begin hers, once her stations answered a read of it; bound by A then)
  await check("A began alice's own lock by itself and it is bound (the station's: one person), nobody asked", async () => {
    const t1 = Date.now();
    await a.personal((p) => p.standing === "member", 90_000);
    const t2 = Date.now();
    let said = "";
    await whenChanged([stationData], () => /^PERSONS 1$/m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
    log(`  A on alice's own lock after ${t2 - t1} ms, bound at the station ${Date.now() - t2} ms later`);
    if (a.asked() !== 0) throw new Error(`A's sealer asked the person ${a.asked()} times: ${a.askedWhat().join("; ")}`);
  });

  let vault = "";
  let item = "";
  const secret = `ghp_e2e_${Date.now()}`;
  const opens = async (d: Device) => {
    const o = await d.call("vault.open", { workspace, item });
    if (o?.plain?.fields?.value !== secret) throw new Error(`${d.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  };
  const keyedFor = async (d: Device, ms = 90_000) => {
    await d.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), ms);
  };
  // (once it has heard it is out of the workspace's lock: what it held before, it held. Not by `signs` alone: a device
  // that hears it is off its person's own lock shows as not signing at once, while the entry taking it out of the
  // workspace's lock, which the vault goes by, comes a moment after)
  const refusedVault = async (d: Device) => {
    const l = await d.lock(workspace, (l) => !l.signs && !lockDevices(l).some((x) => x.mine && x.signs), 60_000);
    log(`  ${d.name}'s lock view: me=${JSON.stringify(l.me)}`);
    await d.call("vault.lock", { workspace });
    const o = await d.call("vault.open", { workspace, item }).then((o) => o, (e) => e);
    if (!(o instanceof Error)) throw new Error(`still opened: ${JSON.stringify(o)?.slice(0, 200)}`);
    log(`  ${d.name}'s vault.open: ${o.message.slice(0, 200)}`);
  };
  /// A's vault as it stands after a device went: keyed anew for the `left` devices that hold its key now (shown all
  /// along, the one that went still among those holding its key until then) and opened, how long it took.
  const aStill = async (what: string, left: number) => {
    const t1 = Date.now();
    const v = await a.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed && x.devices === left), 60_000);
    log(`  ${what}: A's vault keyed anew after ${Date.now() - t1} ms (${v.devices} devices hold its key)`);
    await a.stationState(workspace, (s) => s.state === "online");
    await opens(a);
  };

  await must("A sets up the vault and keeps an item in it", async () => {
    await a.until({ topic: "vaults", workspace }, (v) => (v?.locked && (v.refused ?? []).length === 0 ? v : undefined), 60_000);
    await a.call("vault.setup", { workspace });
    await a.until({ topic: "vaults", workspace }, (v) => v?.setUp, 60_000);
    vault = (await a.call("vault.create", { workspace, name: "e2e", station: station.split("/")[1] })).id;
    item = (await a.call("vault.putItem", {
      workspace, vault,
      plain: { kind: "token", name: "e2e-token", fields: { value: secret }, domains: [], notes: "" },
      listing: { name: "e2e-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id;
  });

  // ── C: a new device approved from its waiting page with A showing the code, as a person does it: with alice's own lock
  // bound, the request lands on it (views/lock.ts `pair`), and C is let into the workspace's lock for being on it ──
  await c.signIn();
  let cKey = "";
  await must("C asks from its waiting page, A shows the code: C on alice's own lock, in the workspace's lock signing, let in", async () => {
    // (left out by the station first: then it waits in the workspace, to be approved, once it has heard the workspace's
    // lock names alice's own: until then its request would go to the workspace's lock)
    await c.stationState(workspace, (s) => s.cause === "lock", 60_000);
    await c.lock(workspace, (l) => l.me?.waiting && l.me?.ownLock, 60_000);
    const shown = a.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await c.call("lock.pair", { workspace });
    const p = await shown;
    await c.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await c.call("lock.pairCode", { workspace, code: p.code });
    await c.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await c.stationState(workspace, (s) => s.state === "online", 90_000);
    // (its key on alice's own lock, as it has itself there: what A takes off below)
    cKey = (await c.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key as string;
  });
  const cBase = await baseOf(c);
  await must("C sets up the vault, is given its key, opens the item", async () => {
    await c.call("vault.setup", { workspace });
    await keyedFor(c);
    await opens(c);
  });
  await check("C in the workspace's lock, let in, opens the item", async () => {
    const l = await a.lock(workspace, (l) => l.signs, 30_000);
    if (!lockDevices(l).some((d) => d.id === cBase)) throw new Error("C not in the workspace's lock");
    await c.stationState(workspace, (s) => s.state === "online", 30_000);
    await opens(c);
  });
  /// The device that asked to be let onto its person's own lock has the field for the code: a device of theirs shows it
  /// and this one has heard that it does (adbShare's `personal.pair`). A person types only then; typed the moment the
  /// other device showed it, a run under a load of 47 was told "no trusted device shows a code" (2026-11-11).
  const codeAsked = (d: Device) => d.personal((p) => p.pair?.state === "code", 60_000);
  const join = async (d: Device) => {
    const shown = a.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub });
    const p = await shown;
    await codeAsked(d);
    await d.call("adb.personalCode", { code: p.code });
    const mine = await d.personal((p) => p.standing === "member", 90_000);
    return mine.devices.find((x: J) => x.me)?.key as string;
  };
  await must("A removes C from alice's own lock", async () => {
    await a.call("adb.personalRemove", { sub, key: cKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("C, taken off alice's own lock, is taken out of the workspace's", async () => {
    const l = await a.lock(workspace, (l) => !lockDevices(l).some((d) => d.id === cBase), 90_000);
    log(`  A sees app devices: ${appIds(l)}`);
  });
  await check("the station refuses C", async () => log(`  C sees: ${short(await c.stationState(workspace, (s) => s.state !== "online", 90_000))}`));
  await check("C can no longer open the item", () => refusedVault(c));
  await check("A's vault keyed anew without C (its key in hand: nobody asked)", () => aStill("C taken out", 1));

  // ── B joins the own lock face to face, is put in the workspace's lock and given the vault ──
  await b.signIn();
  let bKey = "";
  await must("B joins alice's own lock face to face with A", async () => {
    bKey = await join(b);
  });
  await check("B let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await b.call("vault.setup", { workspace });
    await keyedFor(b);
    await opens(b);
  });

  // ── B taken off by A, A's vault key not in hand: keyed anew all the same, the person asked ──
  await must("A removes B from alice's own lock, the vault locked on A first", async () => {
    await a.call("vault.lock", { workspace });
    await a.call("adb.personalRemove", { sub, key: bKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("B gone from the workspace's lock, refused by the station and by the vault", async () => {
    await a.lock(workspace, (l) => appIds(l).length === 1, 90_000);
    log(`  B sees: ${short(await b.stationState(workspace, (s) => s.state !== "online", 90_000))}`);
    await refusedVault(b);
  });
  await check("A's vault keyed anew without B (its key read with the box key)", () => aStill("B taken off", 1));

  // ── B back again: a new key given it ──
  await must("B joins alice's own lock again", async () => {
    bKey = await join(b);
  });
  await check("B let in again and given the vault's new key, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await keyedFor(b);
    await opens(b);
  });
  await check("A still let in and opens the item", async () => {
    await a.stationState(workspace, (s) => s.state === "online");
    await opens(a);
    log(`  A's own lock: ${JSON.stringify((await a.personal(() => true)).devices.map((d: J) => d.key.slice(8, 16)))}; workspace lock apps ${appIds(await a.lock(workspace, () => true))} (A ${aBase.slice(0, 8)})`);
  });

  // ── D approved by B (not A): any device on the own lock lets one in, and puts it in the workspace's lock ──
  await d.signIn();
  await must("D joins alice's own lock face to face with B", async () => {
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub });
    const p = await shown;
    log(`  B shows ${p.code}`);
    await codeAsked(d);
    await d.call("adb.personalCode", { code: p.code });
    dKey = (await d.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key;
  });
  dBase = await baseOf(d);
  await check("D let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await d.stationState(workspace, (s) => s.state === "online", 90_000);
    await d.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await d.call("vault.setup", { workspace });
    await keyedFor(d);
    await opens(d);
  });

  // ── B's app started anew: still on the locks, let in, its vault opened ──
  await b.restart();
  await check("B started anew: on the own lock, let in, opens the item", async () => {
    await b.personal((p) => p.standing === "member", 60_000);
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await opens(b);
  });

  // ── the station started anew: those on the lock let in again, C still refused ──
  await check("the station started anew: A, B and D let in again, the item opened on each", async () => {
    stationDo("freeze");
    stationDo("thaw");
    for (const x of [a, b, d]) await x.stationState(workspace, (s) => s.state === "online", 120_000);
    for (const x of [a, b, d]) await opens(x);
  });
  await check("C still refused by the station started anew", async () => {
    await c.restart();
    const st = await c.stationState(workspace, (s) => s.cause === "lock" || (s.state !== "online" && s.state !== "connecting"), 90_000);
    log(`  C sees: ${short(st)}`);
  });

  // ── D taken off while the station is away: pending (no station took it, and the cloud's taking it would count for
  // nothing), still on alice's lock as A shows it; refused once the station is back and has taken it ──
  await must("A removes D from alice's own lock while the station is frozen: pending, D still on her lock", async () => {
    stationDo("freeze");
    const r = await a.call("adb.personalRemove", { sub, key: dKey });
    if (r?.pending?.state !== "waiting") throw new Error(`not pending: ${JSON.stringify(r)?.slice(0, 300)}`);
    await a.personal((p) => p.devices.length === 3 && (p.pending ?? []).some((x: J) => x.state === "waiting"), 60_000);
  });
  await check("the station back: D refused, gone from alice's lock and the workspace's, nothing pending, the vault keyed anew for A and B", async () => {
    stationDo("thaw");
    await a.personal((p) => p.devices.length === 2 && (p.pending ?? []).length === 0, 60_000);
    await a.lock(workspace, (l) => !lockDevices(l).some((x) => x.id === dBase), 120_000);
    log(`  D sees: ${short(await d.stationState(workspace, (s) => s.state !== "online", 120_000))}`);
    await refusedVault(d);
    await aStill("D taken off with the station away", 2);
    await keyedFor(b);
    await opens(b);
  });

  // ── B taken off while its app is closed: refused as it starts again ──
  await must("A removes B while B's app is closed", async () => {
    await b.close();
    await a.call("adb.personalRemove", { sub, key: bKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
    await a.lock(workspace, (l) => appIds(l).length === 1, 90_000);
  });
  await check("B started again: refused by the station, off the own lock, no vault", async () => {
    await b.restart();
    log(`  B sees: ${short(await b.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    const p = await b.personal((p) => p.standing !== "member", 60_000);
    log(`  B's own lock standing: ${p.standing}`);
    await refusedVault(b);
  });
  await check("A, the last on the own lock, still let in and opens the item", async () => {
    await aStill("B taken off while closed", 1);
  });

  // ── round 4: the first device taken off by another; the last one left cannot go ──
  const joinVia = async (approver: Device, d: Device) => {
    const t1 = Date.now();
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub: approver.sub });
    const p = await shown;
    log(`  ${approver.name} shows ${JSON.stringify(p).slice(0, 300)} after ${Date.now() - t1} ms`);
    await codeAsked(d);
    await d.call("adb.personalCode", { code: p.code });
    return (await d.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key as string;
  };
  let bKey3 = "";
  await must("B joins alice's own lock once more, face to face with A", async () => {
    bKey3 = await joinVia(a, b);
  });
  await check("B let in, given the vault, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await keyedFor(b);
    await opens(b);
  });
  const aKey = (await a.personal((p) => p.standing === "member")).devices.find((x: J) => x.me)?.key as string;
  await must("B takes A, the first device, off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: aKey });
    await b.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("A refused by the station, out of the workspace's lock, no vault", async () => {
    log(`  A sees: ${short(await a.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    await refusedVault(a);
  });
  await check("B, the one left, keys the vault anew without A and opens the item", async () => {
    const t1 = Date.now();
    const v = await b.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), 60_000);
    log(`  B's vault back after ${Date.now() - t1} ms (${v.devices} devices hold its key)`);
    await b.stationState(workspace, (s) => s.state === "online", 60_000);
    await opens(b);
  });
  await check("B, the last on alice's own lock, cannot take itself off, and still opens the item", async () => {
    const r = await b.call("adb.personalRemove", { sub, key: bKey3 }).then(() => null, (e) => e as Error);
    if (r === null) throw new Error("the last device was taken off");
    log(`  B told: ${r.message.slice(0, 200)}`);
    const p = await b.personal((p) => p.standing === "member");
    if (p.devices.length !== 1) throw new Error(`devices: ${p.devices.length}`);
    await opens(b);
  });

  // ── round 5: A's app installed anew (its data and keys gone): a new device, let in only as it joins again ──
  await a.close();
  await e.signIn();
  await check("A installed anew, before it joins: refused by the station, no vault", async () => {
    log(`  E sees: ${short(await e.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    const o = await e.call("vault.open", { workspace, item }).then((o) => o, (x) => x as Error);
    if (!(o instanceof Error)) throw new Error(`opened: ${JSON.stringify(o)?.slice(0, 200)}`);
  });
  await must("A installed anew joins alice's own lock face to face with B", async () => {
    await joinVia(b, e);
  });
  await check("A installed anew let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await e.stationState(workspace, (s) => s.state === "online", 90_000);
    await e.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await e.call("vault.setup", { workspace });
    await keyedFor(e);
    await opens(e);
  });
  await check("C and D still refused by the station started anew; A installed anew and B let in again", async () => {
    stationDo("freeze");
    stationDo("thaw");
    for (const x of [c, d]) {
      await x.restart();
      log(`  ${x.name} sees: ${short(await x.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    }
    await e.stationState(workspace, (s) => s.state === "online", 90_000);
    await opens(e);
    await opens(b);
  });

  // ── round 6: the cloud frozen (it answers nothing) while a device is let in and taken off: the stations carry the
  // locks (the root AGENTS.md, The cloud is the account system) ──
  await f.signIn();
  await check("F, not on the lock yet, refused by the station", async () => {
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
  });
  stationDo("cloud-freeze");
  let fKey = "";
  let fBase = "";
  await must("with the cloud frozen, F joins alice's own lock face to face with B", async () => {
    const t1 = Date.now();
    fKey = await joinVia(b, f);
    log(`  joined in ${Date.now() - t1} ms`);
  });
  await check("with the cloud frozen, F let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    const t1 = Date.now();
    await f.stationState(workspace, (s) => s.state === "online", 90_000);
    log(`  F let in after ${Date.now() - t1} ms`);
    fBase = await baseOf(f);
    await f.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await f.call("vault.setup", { workspace });
    await keyedFor(f);
    await opens(f);
  });
  await check("with the cloud frozen, A installed anew hears of the station that F joined", async () => {
    await e.personal((p) => p.devices.length === 3, 60_000);
  });
  await must("with the cloud frozen, B takes F off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: fKey });
    await b.personal((p) => p.devices.length === 2, 60_000);
  });
  await check("with the cloud frozen, F refused and out of the vault; B and A installed anew still open the item", async () => {
    await b.lock(workspace, (l) => !lockDevices(l).some((x) => x.id === fBase), 90_000);
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online", 120_000))}`);
    await refusedVault(f);
    await e.personal((p) => p.devices.length === 2, 60_000);
    await keyedFor(b);
    await opens(b);
    await opens(e);
  });
  stationDo("cloud-thaw");
  await check("the cloud back: F still refused; B and A installed anew let in and open the item", async () => {
    await f.restart();
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await opens(x);
    }
  });

  // ── round 7: a second station in the lock. The stations keep each other level in alice's own lock (person-sync.ts):
  // with the first one frozen, G joins through the second; the first, back, hears it of the second ──
  const stationIn = (x: Device, id: string, ok: (s: J) => boolean, ms = 60_000) => x.stationState(workspace, ok, ms, id);
  const chainsAt = (data: string): number => {
    try {
      const kept = JSON.parse(readFileSync(`${data}/mesh/person-chains.json`, "utf8"));
      const chains = (kept.chains ?? kept) as Record<string, J[]>;
      return Math.max(0, ...Object.values(chains).filter((c) => c[0]?.ws === `person:${sub}`).map((c) => c.length));
    } catch {
      return 0;
    }
  };
  const atLength = async (data: string, n: number, ms = 60_000) => {
    await whenChanged([data], () => chainsAt(data) >= n, ms, () => `${data}: alice's own lock ${chainsAt(data)} long, not ${n}`);
  };
  const first = `${process.env.E2E_STATION}/data`;
  const second = `${process.env.E2E_STATION}-b/data`;
  let secondId = "";
  await must("A installed anew enrolls a second station with the lock's hash and takes it into the lock by its code", async () => {
    const made = await e.call("workspace.enroll", { account: sub, workspace, name: "second" });
    const at = `${dir}/enroll.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at);
    const said = readFileSync(`${process.env.E2E_WORK}/run/second-enroll.log`, "utf8");
    const code = said.match(/(?:code|安全码为)\s*([0-9A-Z-]{4,})/i)?.[1];
    if (!code) throw new Error(`no code in: ${said}`);
    const w = await e.until({ topic: "workspace", workspace }, (v) => (v?.stations ?? []).find((s: J) => s.id !== station.split("/")[1]), 60_000);
    secondId = w.id;
    log(`  second station ${secondId.slice(0, 12)}, code ${code}`);
    await e.call("lock.addStation", { workspace, station: secondId, code });
    await e.lock(workspace, (l) => JSON.stringify(l).includes(secondId), 60_000);
  });
  await check("B and A installed anew let in by the second station too", async () => {
    for (const x of [b, e]) log(`  ${x.name} sees the second: ${short(await stationIn(x, secondId, (s) => s.state === "online", 120_000))}`);
  });
  const n = chainsAt(first);
  await check(`the second station hears alice's own lock of the first (${n} long)`, async () => {
    await atLength(second, n);
  });
  stationDo("freeze");
  let gKey = "";
  let gBase = "";
  await g.signIn().catch((x) => log(`  G signs in: ${x}`));
  await check("with the first station frozen, G, not on the lock yet, refused by the second", async () => {
    log(`  G sees the second: ${short(await stationIn(g, secondId, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
  });
  await must("with the first station frozen, G joins alice's own lock face to face with B", async () => {
    const t1 = Date.now();
    gKey = await joinVia(b, g);
    log(`  joined in ${Date.now() - t1} ms`);
  });
  await check("with the first station frozen, the second keeps G on alice's own lock; A installed anew hears it", async () => {
    await atLength(second, n + 1);
    await e.personal((p) => p.devices.length === 3, 60_000);
  });
  await check("with the first station frozen, G let in by the second, in the workspace's lock signing, set up for the vault", async () => {
    const t1 = Date.now();
    await stationIn(g, secondId, (s) => s.state === "online", 90_000);
    log(`  G let in after ${Date.now() - t1} ms`);
    await g.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    gBase = await baseOf(g);
    const t2 = Date.now();
    await g.call("vault.setup", { workspace });
    log(`  G set up in ${Date.now() - t2} ms`);
  });
  stationDo("thaw");
  await check("the first station back hears G of the second: G let in by it too, given the vault (written on the first), opens the item", async () => {
    await atLength(first, n + 1, 90_000);
    log(`  G sees the first: ${short(await stationIn(g, station.split("/")[1], (s) => s.state === "online", 120_000))}`);
    const t1 = Date.now();
    await keyedFor(g);
    log(`  G given the vault's key after ${Date.now() - t1} ms`);
    await opens(g);
  });
  stationDo("freeze");
  // (how many devices hold the vault's key with G among them: one less once it is keyed anew)
  const heldBy = (await b.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), 60_000)).devices as number;
  await must("with the first station frozen, B takes G off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: gKey });
    await b.personal((p) => p.devices.length === 2, 60_000);
  });
  await check("with the first station frozen, the second refuses G; G out of the vault", async () => {
    await atLength(second, n + 2);
    log(`  G sees the second: ${short(await stationIn(g, secondId, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    await refusedVault(g);
  });
  // (a vault is written on the first, by id, of the stations that hold it (views/vault.ts `holds`): the first station,
  // frozen, or the second. On the frozen one it waits to be keyed anew: the devices left read it meanwhile and change
  // nothing in it, told the station it waits for (the owner's decision, 2026-11-10, views/vault.ts `waitingAs`). On the
  // second it is keyed anew at once, and written as ever. Which it is differs by the run, the stations' ids made anew.)
  await check("with the first station frozen, B and A installed anew still open the item; a new item refused while the vault waits for that station, taken where it lives on the second", async () => {
    for (const x of [b, e]) await x.lock(workspace, (l) => !lockDevices(l).some((d) => d.id === gBase), 90_000);
    const host = (await b.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault), 60_000)).station as string;
    const waits = host === station.split("/")[1];
    log(`  the vault lives on the ${waits ? "first station, frozen: it waits to be keyed anew" : "second station: keyed anew at once"}`);
    for (const x of [b, e]) {
      // (on the second station: once keyed anew, G's key gone from it; written meanwhile it is refused as waiting too,
      // for the moment that takes)
      if (!waits) await x.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((y: J) => y.id === vault && y.keyed && y.devices < heldBy), 60_000);
      await opens(x);
    }
    const put = await within(b.call("vault.putItem", {
      workspace, vault,
      plain: { kind: "token", name: "e2e-waiting", fields: { value: "w" }, domains: [], notes: "" },
      listing: { name: "e2e-waiting", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    }).then((o: J) => o, (x: Error) => x), 60_000);
    if (put === undefined) throw new Error("B's vault.putItem not answered in 60 s");
    if (!waits) {
      if (put instanceof Error) throw new Error(`B's vault.putItem on the second station: ${put.message.slice(0, 300)}`);
      return;
    }
    if (!(put instanceof Error)) throw new Error("B's vault.putItem taken while the vault waits to be keyed anew");
    log(`  B's vault.putItem: ${put.message.slice(0, 300)}`);
    if (!/vault_waiting/.test(put.message)) throw new Error(`not refused as waiting: ${put.message.slice(0, 300)}`);
  });
  stationDo("thaw");
  await check("the first station back hears G was taken off: it refuses G; B and A installed anew open the item", async () => {
    await atLength(first, n + 2, 90_000);
    await g.restart();
    log(`  G sees the first: ${short(await stationIn(g, station.split("/")[1], (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    // (the vault keyed anew first: its owner's device writes the new keys on the first station, which was frozen as G
    // was taken off; meanwhile it was read as it stood, and changed by no one)
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await keyedFor(x);
      await opens(x);
    }
  });
  // C, D, F and G were taken off and have no more part: closed, as such a device mostly is. Each device of alice's reads
  // her account again on every change to her workspaces (a member, a station, a workspace), and still.fail cloud gives
  // an account 120 requests a minute (account.ts): nine of them running through rounds 8 and 9 use it up.
  await within(Promise.all([c, d, f, g].map((x) => x.close())), 5000);

  // ── round 7b: two stations took different entries. The cloud frozen throughout (a station takes from the plane
  // what goes on from its head: with it, the second would hear the first's entry as it starts, and there would be no
  // fork) and A installed anew closed: with the second station stopped, B renews itself in the workspace's lock at
  // the first (`lock.renew`, an expiry 30 days on, what an app's entry may say); the first stopped and the second
  // started, A installed anew, which has not heard that, renews itself at the second. Both up: the stations come to
  // one chain by the rules' fork choice (station/src/cloud/log-keep.ts), the device whose entry lost signs it again
  // after the head (views/lock.ts `again`), both renewals are on it, each device's pages show both and both stations
  // let each in, and nobody was asked ──
  const stationLock = (at?: string) => {
    const said = stationSays("lock-state", ...(at === undefined ? [] : [at]));
    const exp = (id: string) => said.match(new RegExp(`^DEVICE ${id.slice(0, 12)} \\S+ \\S+ own=\\S+ exp=(\\S+)`, "m"))?.[1] ?? "none";
    return { head: said.match(/^HEAD (\S+)/m)?.[1] ?? "", exp };
  };
  const forkB = await baseOf(b);
  const forkE = await baseOf(e);
  const askedBefore = [b.asked(), e.asked()];
  const round7b = new Date().toISOString();
  stationDo("cloud-freeze");
  try {
    await must("the cloud frozen, the second station stopped and A installed anew closed: B renews itself at the first", async () => {
      await e.close();
      stationDo("second-stop");
      await b.call("lock.renew", { workspace, device: forkB });
      await whenChanged([first], () => stationLock().exp(forkB) !== "-", 60_000, () => `the first: B's expiry ${stationLock().exp(forkB)}`);
    });
    await must("the first station stopped and the second started: A installed anew, not having heard it, renews itself at the second", async () => {
      await b.close();
      stationDo("freeze");
      stationDo("second-again");
      await e.restart();
      await stationIn(e, secondId, (s) => s.state === "online", 120_000);
      if (stationLock("second").exp(forkB) !== "-") throw new Error("the second heard B's entry already: no fork to come");
      await e.call("lock.renew", { workspace, device: forkE });
      await whenChanged([second], () => stationLock("second").exp(forkE) !== "-", 60_000, () => `the second: A installed anew's expiry ${stationLock("second").exp(forkE)}`);
    });
    // Which renewal loses is the rules' tie (of the parent's hash and the signing key, both new each run), so either
    // device is the one to sign again: B, closed since its renewal, can only once it runs. So the stations come to one
    // chain first, the winning renewal on it, and which lost is said (B's renewal on the chain while B is closed won:
    // B could not have signed it again; A installed anew, running, may have signed its own again already); then B is
    // started and the one that lost is on the chain too, signed again by its device, whichever it is. (The side run of
    // 2026-11-12, run 43182403308: B's renewal lost, and the round waited for it signed again with B closed.)
    let lost = "";
    await check("both stations up: one chain at both within seconds, the renewal that won on it", async () => {
      stationDo("thaw");
      // (from when the thawed station is up: `thaw` returns once it is)
      const t1 = Date.now();
      const renewed = (l: ReturnType<typeof stationLock>, id: string) => !["-", "none"].includes(l.exp(id));
      const level = () => {
        const one = stationLock();
        const two = stationLock("second");
        return one.head !== "" && one.head === two.head && (renewed(one, forkB) || renewed(one, forkE)) ? one : null;
      };
      const at = await whenChanged([first, second], level, 10_000, () => `the first: head ${stationLock().head.slice(0, 12)}, B ${stationLock().exp(forkB)}, A installed anew ${stationLock().exp(forkE)}; the second: head ${stationLock("second").head.slice(0, 12)}, B ${stationLock("second").exp(forkB)}, A installed anew ${stationLock("second").exp(forkE)}`);
      lost = renewed(at, forkB) ? "A installed anew" : "B";
      log(`  one chain at both stations ${Date.now() - t1} ms after the first was up again, head ${at.head.slice(0, 12)}; the renewal that lost: ${lost}'s`);
    });
    await check("B started: both renewals on one chain at both within seconds (the one that lost signed again by its device); B and A installed anew let in by both and their pages show both renewals; nobody asked", async () => {
      // (B started whatever the check before found: the rounds after use it)
      const t1 = Date.now();
      await b.restart();
      const level = () => {
        const one = stationLock();
        const two = stationLock("second");
        return one.head !== "" && one.head === two.head && [forkB, forkE].every((id) => !["-", "none"].includes(one.exp(id))) ? one : null;
      };
      const at = await whenChanged([first, second], level, 10_000, () => `the renewal that lost: ${lost || "not known"}'s; the first: head ${stationLock().head.slice(0, 12)}, B ${stationLock().exp(forkB)}, A installed anew ${stationLock().exp(forkE)}; the second: head ${stationLock("second").head.slice(0, 12)}, B ${stationLock("second").exp(forkB)}, A installed anew ${stationLock("second").exp(forkE)}`);
      log(`  both renewals on one chain at both stations ${Date.now() - t1} ms after B was started, head ${at.head.slice(0, 12)}; signed again by ${lost || "?"}`);
      // (what each device holds, as its own pages say it: both renewed, 30 days left; let in by both stations)
      const renewed = (l: J) => [forkB, forkE].every((id) => lockDevices(l).find((x) => x.id === id)?.daysLeft != null);
      for (const x of [b, e]) {
        await x.lock(workspace, renewed, 60_000);
        for (const id of [station.split("/")[1]!, secondId]) await stationIn(x, id, (st) => st.state === "online", 60_000);
      }
      const asked = [b.asked(), e.asked()];
      if (asked.some((n, i) => n !== askedBefore[i])) throw new Error(`asked the person: B ${asked[0]! - askedBefore[0]!}, A installed anew ${asked[1]! - askedBefore[1]!} times (from ${round7b}): B ${b.askedWhat(askedBefore[0]).join("; ") || "-"}; A installed anew ${e.askedWhat(askedBefore[1]).join("; ") || "-"}`);
    });
  } finally {
    stationDo("cloud-thaw");
  }
  // (round 9's devices' ids, as the workspace's lock has them: a device's id is its own, the same in each workspace)
  const bId = await baseOf(b);
  const eId = await baseOf(e);
  // ── round 8: a second person, bob, a member: his first device let into the workspace's lock by the owner face to
  // face, which begins his own lock by itself (nobody asked) and binds it, a vault of his own, his second device
  // joining his own lock; then the owner takes him out of the workspace: the cloud's to say (members are the account
  // system's), his devices refused ──
  let bobVault = "";
  let bobItem = "";
  const bobSecret = `ghp_bob_${Date.now()}`;
  const bobOpens = async (x: Device) => {
    const o = await x.call("vault.open", { workspace, item: bobItem });
    if (o?.plain?.fields?.value !== bobSecret) throw new Error(`${x.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  };
  await must("B adds bob to the workspace", async () => {
    const r = await b.call("workspace.addMembers", { account: sub, workspace, role: "member", emails: ["bob@example.test"] });
    log(`  added: ${JSON.stringify(r)?.slice(0, 200)}`);
  });
  await h.signIn();
  await must("bob's first device H, not in the workspace's lock, refused; B approves it face to face", async () => {
    log(`  H sees the first: ${short(await h.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await h.lock(workspace, (l) => l.me?.waiting, 60_000);
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await h.call("lock.pair", { workspace });
    const p = await shown;
    await h.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await h.call("lock.pairCode", { workspace, code: p.code });
    await h.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await h.stationState(workspace, (s) => s.state === "online", 90_000);
  });
  // (before its vault: opening a vault's key reads the box key, which asks the person, and that is not what is counted
  // here)
  await check("H, once approved, began bob's own lock by itself, nobody asked", async () => {
    await h.personal((p) => p.standing === "member", 90_000);
    if (h.asked() !== 0) throw new Error(`H's sealer asked the person ${h.asked()} times: ${h.askedWhat().join("; ")}`);
  });
  await must("H sets up the vault, keeps an item in a vault of bob's own, opens it", async () => {
    await h.call("vault.setup", { workspace });
    await h.until({ topic: "vaults", workspace }, (v) => v?.setUp, 60_000);
    bobVault = (await h.call("vault.create", { workspace, name: "bob", station: station.split("/")[1] })).id;
    bobItem = (await h.call("vault.putItem", {
      workspace, vault: bobVault,
      plain: { kind: "token", name: "bob-token", fields: { value: bobSecret }, domains: [], notes: "" },
      listing: { name: "bob-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id;
    await bobOpens(h);
  });
  await check("alice's devices do not open bob's item; B still opens alice's", async () => {
    const o = await b.call("vault.open", { workspace, item: bobItem }).then((o) => o, (x) => x);
    if (!(o instanceof Error)) throw new Error(`B opened bob's item: ${JSON.stringify(o)?.slice(0, 200)}`);
    await opens(b);
  });
  await check("bob bound to his own lock in the workspace's lock (the station's: two persons); H still let in", async () => {
    let said = "";
    await whenChanged([stationData], () => /^PERSONS 2$/m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
    await h.stationState(workspace, (s) => s.state === "online", 60_000);
    await bobOpens(h);
  });
  await i.signIn();
  await check("bob's second device I, not on his own lock, refused", async () => {
    log(`  I sees the first: ${short(await i.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
  });
  await must("I joins bob's own lock face to face with H", async () => {
    await joinVia(h, i);
  });
  await check("I let in, in the workspace's lock signing, given bob's vault, opens his item", async () => {
    const t1 = Date.now();
    await i.stationState(workspace, (s) => s.state === "online", 90_000);
    log(`  I let in after ${Date.now() - t1} ms`);
    await i.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await i.call("vault.setup", { workspace });
    await i.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === bobVault && x.keyed), 90_000);
    await bobOpens(i);
  });
  await check("alice's own lock untouched by bob's: B and A installed anew still let in, open alice's item", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  await must("B takes bob out of the workspace", async () => {
    await b.call("workspace.removeMember", { account: sub, workspace, member: h.sub });
  });
  /// Out of the workspace as the device has it: the workspace gone from its list (the cloud's, the account system's),
  /// or its station refusing it, whichever it hears first.
  const out = (x: Device, ms: number) => Promise.any([
    x.until({ topic: "workspaces" }, (v) => (v ?? []).every((a: J) => !(a.workspaces ?? []).some((w: J) => w.id === workspace)) ? "the workspace gone from its list" : undefined, ms),
    x.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", ms).then(short),
  ]).catch((x: AggregateError) => Promise.reject(x.errors[0]));
  await check("bob out of the workspace's lock too, his devices with him: the cloud alone does not keep him out", async () => {
    let said = "";
    await whenChanged([stationData], () => !/^DEVICE \S+ bob /m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").filter((l) => l.startsWith("DEVICE")).join("; ")}`);
  });
  await check("bob's devices H and I out once he is: the workspace gone, its station refusing them", async () => {
    for (const x of [h, i]) {
      const t1 = Date.now();
      log(`  ${x.name}: ${await out(x, 60_000)} after ${Date.now() - t1} ms`);
    }
  });
  await check("bob out: a device of his started anew is out too", async () => {
    await i.restart();
    log(`  I: ${await out(i, 60_000)}`);
  });
  await check("alice's devices go on: B and A installed anew let in, open alice's item", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  // ── round 9: a second workspace of alice's, safe mode on there too, its own station: alice's own lock bound in both;
  // a new device joining it once is let in by both, taken off it once is refused by both ──
  let two = "";
  let third = "";
  await must("A installed anew makes a second workspace and enrolls a station of its own in it", async () => {
    two = (await e.call("workspace.create", { account: sub, name: "Two" })).id;
    const made = await e.call("workspace.enroll", { account: sub, workspace: two, name: "third" });
    const at = `${dir}/enroll-two.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at, "third");
    third = (await e.until({ topic: "workspace", workspace: two }, (v) => (v?.stations ?? [])[0], 60_000)).id;
    await e.stationState(two, (s) => s.state === "online", 120_000);
  });
  await must("A installed anew turns safe mode on in it, with B and itself, the two on alice's own lock", async () => {
    const draft = await e.until({ topic: "lockDraft", workspace: two }, (v) => (v?.ready ? v : undefined), 120_000);
    log(`  the draft's devices: ${(draft.devices ?? []).map((d: J) => `${d.id.slice(0, 8)}${d.on === false ? " (off)" : ""}`).join(", ")}`);
    for (const d of draft.devices ?? []) if (d.id !== bId && d.id !== eId && d.on !== false) await e.call("lock.toggle", { workspace: two, id: d.id });
    await e.call("lock.open", { workspace: two });
    await e.lock(two, (l) => l.locked && l.signs);
    await e.stationState(two, (s) => s.state === "online");
  });
  await check("alice's own lock bound in the second workspace too; B let in there, signing", async () => {
    await b.stationState(two, (s) => s.state === "online", 90_000);
    await b.lock(two, (l) => l.signs && l.me?.confirmed, 90_000);
    const at = `${process.env.E2E_STATION}-third/data`;
    const persons = () => { try { return readFileSync(`${at}/mesh/person-chains.json`, "utf8"); } catch { return ""; } };
    await whenChanged([at], () => persons().includes(`person:${sub}`), 60_000, () => `the third station keeps no lock of alice's: ${persons().slice(0, 200)}`);
  });
  await j.signIn();
  await check("a new device J, not on alice's own lock, refused in both workspaces", async () => {
    for (const ws of [workspace, two]) log(`  J in ${ws === two ? "Two" : "Dev"}: ${short(await j.stationState(ws, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
  });
  let jKey = "";
  // (as a person does it on a new phone: 发送批准请求 on the page that waits in the workspace, not the settings' 个人锁.
  // Approved into the workspace's lock that way, as it was before, every station went on refusing it: 2026-11-10)
  await must("J asks from the page that waits in Dev: it joins alice's own lock, face to face with B", async () => {
    const me = (await j.lock(workspace, (l) => l.me?.waiting && l.me?.ownLock, 60_000)).me;
    log(`  J's page in Dev: ${JSON.stringify({ waiting: me.waiting, ownLock: me.ownLock, pair: me.pair?.state ?? null })}`);
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await j.call("lock.pair", { workspace });
    const p = await shown;
    // (B's prompt names the workspaces J is let in to by it, as one approved into a workspace's lock is shown)
    const named = (p.workspaces ?? []).map((w: J) => w.id).sort();
    if (JSON.stringify(named) !== JSON.stringify([workspace, two].sort())) throw new Error(`B's prompt names ${JSON.stringify(p.workspaces)}`);
    await j.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await j.call("lock.pairCode", { workspace, code: p.code });
    jKey = (await j.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key as string;
  });
  await check("J let in by both workspaces' stations, in both workspaces' locks signing", async () => {
    for (const ws of [workspace, two]) {
      const t1 = Date.now();
      await j.stationState(ws, (s) => s.state === "online", 90_000);
      await j.lock(ws, (l) => l.signs && l.me?.confirmed, 90_000);
      log(`  J in ${ws === two ? "Two" : "Dev"} after ${Date.now() - t1} ms`);
    }
  });
  // (as a person does it: 移除 beside the device on 设置 › 安全 of a workspace, not the page of their own lock. That
  // took it out of the workspace's lock alone, and it was let in still: 2026-11-10)
  await must("B removes J on Dev's security page: off alice's own lock", async () => {
    await b.call("lock.removeDevice", { workspace, device: await baseOf(j) });
    await b.personal((p) => !p.devices.some((x: J) => x.key === jKey), 60_000);
  });
  await check("J refused by both workspaces' stations, out of both workspaces' locks", async () => {
    for (const ws of [workspace, two]) {
      log(`  J in ${ws === two ? "Two" : "Dev"}: ${short(await j.stationState(ws, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
      await j.lock(ws, (l) => !l.signs, 60_000);
    }
  });
  await check("B and A installed anew still let in by both, alice's item opened", async () => {
    for (const x of [b, e]) {
      for (const ws of [workspace, two]) await x.stationState(ws, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  // ── round 10: safe mode turned off in the second workspace by its owner: its station lets in any device of its
  // members again, J too; the first workspace's lock, and alice's own lock bound there, still keep J out ──
  await must("A installed anew turns safe mode off in Two", async () => {
    await e.call("lock.disable", { workspace: two });
    await e.lock(two, (l) => !l.locked, 60_000);
  });
  await check("J, off alice's own lock, let in by Two's station now; still refused in Dev", async () => {
    const t1 = Date.now();
    await j.stationState(two, (s) => s.state === "online", 90_000);
    log(`  J in Two after ${Date.now() - t1} ms`);
    log(`  J in Dev: ${short(await j.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 30_000))}`);
  });
  await check("B and A installed anew go on in both", async () => {
    for (const x of [b, e]) for (const ws of [workspace, two]) await x.stationState(ws, (s) => s.state === "online", 60_000);
    await opens(b);
  });
  // ── round 11: the second station of round 7 taken out of the first workspace by alice: out of its lock too, by her
  // device's signature, not the cloud's word alone; the first station and her devices go on ──
  await must("B takes the second station out of Dev", async () => {
    await b.call("workspace.removeStation", { account: sub, workspace, station: secondId });
  });
  await check("the first station's lock names it no more", async () => {
    let said = "";
    await whenChanged([stationData], () => /^STATIONS 1$/m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-3).join("; ")}`);
  });
  await check("B and A installed anew go on in Dev, alice's item opened", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  // ── round 12: a member taken out and made a member again, then every device of his lost. The workspace's lock
  // forgot him as he was taken out (his devices, the lock of his own he had bound), so his first device back is
  // approved by an owner as anyone's first is. With every device gone, a new one finds none of his to approve it: he
  // says so on it (a lock of his own begun anew), which the workspace's lock does not follow by itself (no one but a
  // device of his own says which lock is his); the owner takes him out and makes him a member again, and approves the
  // new device as his first ──
  const bobAgain = async () => {
    await b.call("workspace.addMembers", { account: sub, workspace, role: "member", emails: ["bob@example.test"] });
  };
  /// `x` approved into the workspace's lock from its waiting page, the code shown on `approver` (round 13's too; round
  /// 16's web page, which signs nothing once in: `page`). How long from the code typed to let in, in ms.
  const approvedBy = async (approver: Device, x: Device, page = false): Promise<number> => {
    // (once it has heard the workspace's lock names no lock of its person's: until then its request would go to the
    // devices of the lock named before, not to the workspace's)
    const t1 = Date.now();
    const me = (await x.lock(workspace, (l) => l.me?.waiting && !l.me?.ownLock, 90_000)).me;
    log(`  ${x.name}'s page in Dev: ${JSON.stringify({ waiting: me.waiting, ownLock: me.ownLock ?? false })} after ${Date.now() - t1} ms`);
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await x.call("lock.pair", { workspace });
    const p = await shown;
    await x.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await x.call("lock.pairCode", { workspace, code: p.code });
    const typed = Date.now();
    await x.lock(workspace, (l) => (page || l.signs) && l.me?.confirmed, 90_000);
    await x.stationState(workspace, (s) => s.state === "online", 90_000);
    return Date.now() - typed;
  };
  const approvedByB = (x: Device) => approvedBy(b, x);
  const persons = async (n: number) => {
    let said = "";
    await whenChanged([stationData], () => new RegExp(`^PERSONS ${n}$`, "m").test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
  };
  await must("B makes bob a member again", bobAgain);
  await must("H, back in the workspace and not in its lock, approved by B face to face: let in, signing", async () => {
    await approvedByB(h);
  });
  await check("bob's own lock, as H has it, bound in the workspace's lock again (the station's: two persons)", async () => {
    await persons(2);
  });
  await check("I, on bob's own lock, let in and signing in the workspace's lock", async () => {
    const t1 = Date.now();
    await i.stationState(workspace, (s) => s.state === "online", 90_000);
    log(`  I let in after ${Date.now() - t1} ms`);
    await i.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
  });
  await h.close();
  await i.close();
  await k.signIn();
  await must("K, a new device of bob's, every other gone: refused, and none of his found to approve it", async () => {
    log(`  K sees the first: ${short(await k.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await k.lock(workspace, (l) => l.me?.waiting && l.me?.ownLock, 60_000);
    await k.call("lock.pair", { workspace });
    const pair = (await k.lock(workspace, (l) => l.me?.pair?.state === "none" || l.me?.pair?.state === "failed", 120_000)).me.pair;
    log(`  K's request: ${JSON.stringify(pair).slice(0, 300)}`);
  });
  await must("K says bob's other devices are gone: a lock of his own begun anew, K alone on it", async () => {
    await k.call("adb.personalRestart", { sub: k.sub });
    await k.personal((p) => p.standing === "member" && p.devices.length === 1, 60_000);
  });
  await check("K still refused: the workspace's lock names the lock from before", async () => {
    log(`  K in Dev: ${short(await k.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 60_000))}`);
    const me = (await k.lock(workspace, (l) => l.me?.waiting, 60_000)).me;
    log(`  K's page in Dev: ${JSON.stringify({ waiting: me.waiting, ownLock: me.ownLock ?? false, pair: me.pair?.state ?? null })}`);
  });
  await must("B takes bob out of the workspace and makes him a member again", async () => {
    await b.call("workspace.removeMember", { account: sub, workspace, member: k.sub });
    await persons(1);
    await bobAgain();
  });
  await must("K approved by B face to face as bob's first device: let in, signing", async () => {
    await approvedByB(k);
  });
  await check("the lock bob began anew bound in the workspace's lock (the station's: two persons)", async () => {
    await persons(2);
  });
  await check("H, a device from before the loss, started again: refused", async () => {
    await h.restart();
    // (refused by the station for the lock, not only not reached yet: it is bob's device no more)
    log(`  H: ${short(await h.stationState(workspace, (s) => s.state !== "online" && s.cause === "lock", 90_000))}`);
  });
  await check("alice's devices go on: B and A installed anew let in, alice's item opened", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });

  // ── round 13: a person from before the update moved over with nobody asked. carol, a member, has three apps from
  // before (L, M, N: they seal nothing, so make no key of a lock of her own, and sign the workspace's lock with a key
  // kept in a plain file), each approved face to face in the workspace's lock, the first by the owner, each next by the
  // one before. As each app updates (its host sealing now, the same data), it says in the workspace's lock the key it
  // would be on her own lock with; the first of hers, updated last, begins that lock by itself once the others said
  // theirs, puts on it those it approved and those they approved, they take it by themselves, and it is bound: nobody
  // asked for anything (views/lock.ts `ownLockFor`). Then a new device of hers asks from its waiting page and lands on
  // her own lock. ──
  // H, J, K and A installed anew have no more part: closed. Each device of alice's reads her account again on every
  // change to her workspaces (carol made a member is one), and still.fail cloud gives an account 120 requests a minute
  // (account.ts); and every owner's device is dialled for a member's first device, so B alone shows the code for L.
  await within(Promise.all([e, h, j, k].map((x) => x.close())), 5000);
  const personsIn = (said: string) => Number(said.match(/^PERSONS (\d+)$/m)?.[1] ?? NaN);
  const saidIn = (said: string) => (said.match(/^SAID(.*)$/m)?.[1] ?? "").trim().split(/\s+/).filter((x) => x !== "");
  const before = personsIn(stationSays("lock-state"));
  log(`  persons in the workspace's lock before carol: ${before}`);
  let carolVault = "";
  let carolItem = "";
  const carolSecret = `ghp_carol_${Date.now()}`;
  const carolOpens = async (x: Device) => {
    const o = await x.call("vault.open", { workspace, item: carolItem });
    if (o?.plain?.fields?.value !== carolSecret) throw new Error(`${x.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  };
  const carolKeyed = (x: Device, ms = 90_000) => x.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((y: J) => y.id === carolVault && y.keyed), ms);
  await must("B adds carol to the workspace", async () => {
    const r = await b.call("workspace.addMembers", { account: sub, workspace, role: "member", emails: ["carol@example.test"] });
    log(`  added: ${JSON.stringify(r)?.slice(0, 200)}`);
  });
  await lDev.signIn();
  await must("carol's first device L, an app from before, refused; B approves it face to face from its waiting page", async () => {
    log(`  L sees the first: ${short(await lDev.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(b, lDev);
  });
  await mDev.signIn();
  await must("M, an app from before, refused; approved from its waiting page by L, the code shown on L", async () => {
    log(`  M sees the first: ${short(await mDev.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(lDev, mDev);
  });
  await nDev.signIn();
  await must("N, an app from before, refused; approved from its waiting page by M, the code shown on M", async () => {
    log(`  N sees the first: ${short(await nDev.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(mDev, nDev);
  });
  // (as lock-state names them: the first 12 hex digits of each one's id in the workspace's lock)
  const [lId, mId, nId] = (await Promise.all([lDev, mDev, nDev].map(baseOf))).map((x) => x.slice(0, 12));
  log(`  L ${lId}, M ${mId}, N ${nId}`);
  // (no vault of carol's yet: a host that seals nothing has no vault (views/vault.ts `able`), so hers is kept once her
  // apps updated, below)
  await check("carol has no lock of her own: none on L, the station's persons as before, none of L, M, N said a key", async () => {
    await lDev.personal((p) => p.standing === "none", 30_000);
    const said = stationSays("lock-state");
    if (personsIn(said) !== before) throw new Error(`persons ${personsIn(said)}, not ${before}`);
    const named = saidIn(said).filter((x) => [lId, mId, nId].includes(x));
    if (named.length > 0) throw new Error(`said: ${named.join(" ")}`);
  });
  // ── N's and M's apps updated: they say their keys; nobody begins, L (the first of hers, the one to) not updated ──
  await nDev.restart({ sealed: true });
  await mDev.restart({ sealed: true });
  await check("N and M updated: still let in, signing in the workspace's lock", async () => {
    for (const x of [nDev, mDev]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await x.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    }
  });
  await check("N and M say in the workspace's lock the key they would be on carol's own lock with; L does not", async () => {
    let said = "";
    await whenChanged([stationData], () => {
      const now = saidIn((said = stationSays("lock-state")));
      return now.includes(nId) && now.includes(mId);
    }, 90_000, () => `SAID ${saidIn(said).join(" ")}`);
    if (saidIn(said).includes(lId)) throw new Error(`L said a key: SAID ${saidIn(said).join(" ")}`);
  });
  await check("nobody began carol's own lock: the station's persons as before", async () => {
    const said = stationSays("lock-state");
    if (personsIn(said) !== before) throw new Error(`persons ${personsIn(said)}, not ${before}`);
  });
  // ── L's app updated: it begins carol's own lock with the three on it, M and N take it, it is bound ──
  await lDev.restart({ sealed: true });
  await check("L, updated, began carol's own lock by itself with L, M and N on it", async () => {
    const p = await lDev.personal((p) => p.standing === "member" && p.devices.length === 3, 90_000);
    log(`  carol's own lock: ${JSON.stringify(p.devices.map((d: J) => d.label))}`);
  });
  await check("M and N took carol's own lock by themselves", async () => {
    for (const x of [mDev, nDev]) await x.personal((p) => p.standing === "member", 90_000);
  });
  await check("carol bound to her own lock in the workspace's lock (the station's: one person more)", async () => {
    let said = "";
    await whenChanged([stationData], () => personsIn((said = stationSays("lock-state"))) === before + 1, 90_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
  });
  await check("L, M and N let in, signing in the workspace's lock", async () => {
    for (const x of [lDev, mDev, nDev]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await x.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    }
  });
  // (before carol's vault: opening a vault's key given to a device reads its box key, which asks the person, and that
  // is not what is counted here)
  await check("nobody asked for anything on L, M or N", async () => {
    const asked = lDev.asked() + mDev.asked() + nDev.asked();
    if (asked !== 0) throw new Error(`asked: L ${lDev.asked()}, M ${mDev.asked()}, N ${nDev.asked()}: ${[lDev, mDev, nDev].flatMap((x) => x.askedWhat().map((w) => `${x.name} ${w}`)).join("; ")}`);
  });
  await must("L sets up the vault, keeps an item in a vault of carol's own, opens it", async () => {
    await lDev.call("vault.setup", { workspace });
    await lDev.until({ topic: "vaults", workspace }, (v) => v?.setUp, 60_000);
    carolVault = (await lDev.call("vault.create", { workspace, name: "carol", station: station.split("/")[1] })).id;
    carolItem = (await lDev.call("vault.putItem", {
      workspace, vault: carolVault,
      plain: { kind: "token", name: "carol-token", fields: { value: carolSecret }, domains: [], notes: "" },
      listing: { name: "carol-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id;
    await carolOpens(lDev);
  });
  await check("M and N set up the vault, are given the key of carol's, open her item", async () => {
    for (const x of [mDev, nDev]) {
      await x.call("vault.setup", { workspace });
      await carolKeyed(x);
      await carolOpens(x);
    }
  });
  // ── O, a new device of carol's: from its waiting page it lands on her own lock, L showing the code ──
  await oDev.signIn();
  await must("O, a new device of carol's, refused; asks from its waiting page, L shows the code: O on carol's own lock", async () => {
    log(`  O sees the first: ${short(await oDev.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    // (once it has heard the workspace's lock names carol's own: until then its request would go to the workspace's)
    await oDev.lock(workspace, (l) => l.me?.waiting && l.me?.ownLock, 60_000);
    const shown = lDev.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await oDev.call("lock.pair", { workspace });
    const p = await shown;
    await oDev.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await oDev.call("lock.pairCode", { workspace, code: p.code });
    await oDev.personal((p) => p.standing === "member", 90_000);
  });
  await check("O let in, signing in the workspace's lock, given the key of carol's vault, opens her item", async () => {
    await oDev.stationState(workspace, (s) => s.state === "online", 90_000);
    await oDev.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await oDev.call("vault.setup", { workspace });
    await carolKeyed(oDev);
    await carolOpens(oDev);
  });

  // ── round 14: a lock of one's own begun on a device that is not the first, by an act that asks its person; the first,
  // outside it, is not shut out, and joins it with one approval. dave, a member, has two apps from before (D1, D2:
  // sealing nothing), D1 approved by the owner, D2 by D1. D2, updated, says its key and begins nothing (D1 is the one to
  // begin, and has not updated); D2 then turns dave's own lock on as allowing a phone's debugging does, D2 alone on it.
  // D1, updated, sees that lock and is outside it: a device of his off his own lock keeps the workspace's lock from
  // binding him, so D1 is still let in by the workspace's lock. D1 joins dave's own lock with D2 showing the code, and
  // he is bound then. ──
  // L, M, N and O, carol's, have no more part: closed, as such a device mostly is. Each device left running reads its
  // account again on every change to the workspace's members (dave and erin added below), and the station serves each.
  await within(Promise.all([lDev, mDev, nDev, oDev].map((x) => x.close())), 5000);
  const before14 = personsIn(stationSays("lock-state"));
  log(`  persons in the workspace's lock before dave: ${before14}`);
  await must("B adds dave to the workspace", async () => {
    const r = await b.call("workspace.addMembers", { account: sub, workspace, role: "member", emails: ["dave@example.test"] });
    log(`  added: ${JSON.stringify(r)?.slice(0, 200)}`);
  });
  await d1.signIn();
  await must("dave's first device D1, an app from before, refused; B approves it face to face from its waiting page", async () => {
    log(`  D1 sees the first: ${short(await d1.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(b, d1);
  });
  await d2.signIn();
  await must("D2, an app from before, refused; approved from its waiting page by D1, the code shown on D1", async () => {
    log(`  D2 sees the first: ${short(await d2.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(d1, d2);
  });
  const d2Id = (await baseOf(d2)).slice(0, 12);
  // ── D2's app updated: it says its key; nobody begins, D1 (the first of his, the one to) not updated ──
  await d2.restart({ sealed: true });
  await check("D2 updated: still let in, signing in the workspace's lock", async () => {
    await d2.stationState(workspace, (s) => s.state === "online", 90_000);
    await d2.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
  });
  await check("D2 says in the workspace's lock the key it would be on dave's own lock with; nobody began his own lock", async () => {
    let said = "";
    await whenChanged([stationData], () => saidIn((said = stationSays("lock-state"))).includes(d2Id), 90_000, () => `SAID ${saidIn(said).join(" ")}`);
    if (personsIn(said) !== before14) throw new Error(`persons ${personsIn(said)}, not ${before14}`);
  });
  // ── D2 turns dave's own lock on (an act that asks him: its key, made before, is read so) ──
  await must("D2 turns dave's own lock on, as allowing a phone's debugging does: D2 alone on it", async () => {
    await d2.call("adb.personalOpen", { sub: d2.sub });
    await d2.personal((p) => p.standing === "member" && p.devices.length === 1, 60_000);
  });
  // ── D1's app updated: outside dave's own lock, and still let in ──
  await d1.restart({ sealed: true });
  await check("D1, updated, sees dave's own lock and is outside it", async () => {
    await d1.personal((p) => p.standing === "outside", 90_000);
  });
  await check("D1 and D2 still let in, signing in the workspace's lock; dave not bound (the station's persons as before)", async () => {
    for (const x of [d1, d2]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await x.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    }
    const said = stationSays("lock-state");
    if (personsIn(said) !== before14) throw new Error(`persons ${personsIn(said)}, not ${before14}`);
  });
  // ── D1 joins dave's own lock as the app's 共享调试 page asks it to, D2 showing the code ──
  await must("D1 asks to be let onto dave's own lock, D2 shows the code: D1 on it", async () => {
    await joinVia(d2, d1);
  });
  await check("dave bound to his own lock in the workspace's lock (the station's: one person more); D1 and D2 let in, signing", async () => {
    await persons(before14 + 1);
    for (const x of [d1, d2]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await x.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    }
  });

  // ── round 15: a station of a person's asleep holds the beginning of their own lock back (a lock kept only by a station
  // that did not answer would get a second one begun beside it: views/lock.ts `personalStations` `answered`); switched
  // on again, it is begun. erin, a member of the first workspace and of alice's second (Two, safe mode off there since
  // round 10, its station the one named `third`, up since round 9). Her device signs in and reaches Two's station (so
  // it holds what Two keeps of a lock: none), then that station is switched off and her app started again: this run it
  // has not reached it, while the control plane saw it lately. Approved by the owner, her device is the one to begin
  // her own lock, and waits; once the station is on again and reached, it begins it, nobody asked, and she is bound.
  // (What asks the device again here may also be a read of Two's lock still waiting on the station as it comes back, a
  // read waiting as long as TAKEN_MS: the run does not wait that out. The device asked again by the station's answer
  // alone, nothing else moving, is client/core-ts/test/lock-stations.test.ts's.) ──
  const before15 = personsIn(stationSays("lock-state"));
  log(`  persons in the workspace's lock before erin: ${before15}`);
  await must("B adds erin to the workspace and to Two", async () => {
    for (const ws of [workspace, two]) {
      const r = await b.call("workspace.addMembers", { account: sub, workspace: ws, role: "member", emails: ["erin@example.test"] });
      log(`  added to ${ws === two ? "Two" : "Dev"}: ${JSON.stringify(r)?.slice(0, 200)}`);
    }
  });
  await e1.signIn();
  await must("erin's device E1 reaches Two's station; that station switched off, E1's app started again and found it off", async () => {
    await e1.stationState(two, (s) => s.state === "online", 90_000);
    stationDo("second-stop", "third");
    await e1.restart();
    // (it has found the station off: what it asks of it from here waits, and none of it is answered)
    log(`  E1 sees Two's station: ${short(await e1.stationState(two, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
  });
  await must("erin's device E1 refused; B approves it face to face from its waiting page: let in, signing", async () => {
    log(`  E1 sees the first: ${short(await e1.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await approvedBy(b, e1);
  });
  // (this cannot show it would never begin, only that it had not once it was let in; the next check, after the station
  // is on again, is what shows the wait was for the station)
  await check("erin has no lock of her own with Two's station off: none on E1, the station's persons as before, nobody asked", async () => {
    await e1.personal((p) => p.standing === "none", 30_000);
    const said = stationSays("lock-state");
    if (personsIn(said) !== before15) throw new Error(`persons ${personsIn(said)}, not ${before15}`);
    if (e1.asked() !== 0) throw new Error(`E1's sealer asked the person ${e1.asked()} times: ${e1.askedWhat().join("; ")}`);
  });
  stationDo("second-again", "third");
  await check("Two's station on again: E1 began erin's own lock by itself, she is bound (one person more), nobody asked", async () => {
    const t1 = Date.now();
    await e1.personal((p) => p.standing === "member", 90_000);
    log(`  E1 on erin's own lock ${Date.now() - t1} ms after the station was on again`);
    let said = "";
    await whenChanged([stationData], () => personsIn((said = stationSays("lock-state"))) === before15 + 1, 90_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
    if (e1.asked() !== 0) throw new Error(`E1's sealer asked the person ${e1.asked()} times: ${e1.askedWhat().join("; ")}`);
  });

  // ── round 16: a web page of alice's, W, in the first workspace, where her own lock is bound. A page keeps no keys (its
  // code is still.fail cloud's: lock.ts `Signer`), so it is never on her own lock: it is in the workspace's lock as a
  // device of kind `web` for 30 days at most (views/pair.ts `approve`, WEB_DEVICE_SECS), which the stations let it in by
  // with her own lock bound there all the same (station/src/mesh/serve.ts `inLock`: a bound person's app devices go by
  // their own lock, a web page by its entry). From its waiting page it asks in the workspace's lock (views/pair.ts
  // `waitingIn`: `offOwnLock` is an app's), and B shows the code: the one app of hers still open, on her own lock since
  // round 4 (A was taken off in round 4, A installed anew closed before round 13). Then B takes it out on 设置 › 安全. ──
  /// The station's lock's line for device `id`: whose, what kind, until when (seconds; null for no end).
  const deviceIn = (said: string, id: string) => {
    const m = said.match(new RegExp(`^DEVICE ${id.slice(0, 12)} (\\S+) (\\S+) own=\\S+ exp=(\\S+)`, "m"));
    return m ? { sub: m[1]!, kind: m[2]!, exp: m[3] === "-" ? null : Number(m[3]) } : null;
  };
  /// Which lock of their own each person is bound to in the station's lock.
  const bindings = (said: string) => said.split("\n").filter((x) => x.startsWith("PERSON ")).sort().join("; ");
  const ownKeys = async () => ((await b.personal((p) => p.standing === "member", 60_000)).devices as J[]).map((d) => d.key as string).sort().join(" ");
  const boundBefore = bindings(stationSays("lock-state"));
  const ownBefore = await ownKeys();
  log(`  alice's own lock before W: ${ownBefore.split(" ").length} devices; bound in Dev: ${boundBefore}`);
  await wDev.signIn();
  const wId = await baseOf(wDev);
  await check("W, alice's web page, refused by Dev's station for the lock; its page says a web page's, waiting, signing nothing", async () => {
    log(`  W sees the first: ${short(await wDev.stationState(workspace, (s) => s.state !== "online" && s.cause === "lock", 90_000))}`);
    const l = await wDev.lock(workspace, (l) => l.locked && l.me?.waiting, 60_000);
    const said = { kind: l.me.kind, waiting: l.me.waiting, confirmed: l.me.confirmed, ownLock: l.me.ownLock ?? false, signs: l.signs, canSign: l.canSign };
    log(`  W's page in Dev: ${JSON.stringify(said)}`);
    if (said.kind !== "web" || said.confirmed !== false || said.ownLock !== false || said.signs !== false || said.canSign !== false) throw new Error(`W's page: ${JSON.stringify(said)}`);
  });
  await must("W asks from its waiting page, B shows the code, W types it: let in", async () => {
    log(`  W let in ${await approvedBy(b, wDev, true)} ms after the code was typed`);
  });
  await check("the station's lock lists W as alice's web page, ending in 31 days at most; W's page lists it under her, confirmed", async () => {
    let said = "";
    const d = await whenChanged([stationData], () => deviceIn((said = stationSays("lock-state")), wId), 60_000, () => `W not in the station's lock: ${said.split("\n").filter((x) => x.startsWith("DEVICE")).join("; ")}`);
    const now = Date.now() / 1000;
    log(`  the station's lock: W ${JSON.stringify(d)}${d.exp === null ? "" : `, ${((d.exp - now) / 86400).toFixed(1)} days left`}`);
    if (d.sub !== sub || d.kind !== "web") throw new Error(`W in the station's lock as ${d.sub}'s ${d.kind}`);
    if (d.exp === null || d.exp <= now || d.exp - now > 31 * 86400) throw new Error(`W's entry ends at ${d.exp} (now ${Math.floor(now)})`);
    const l = await wDev.lock(workspace, (l) => l.me?.confirmed, 30_000);
    const hers = (l.members ?? []).find((m: J) => m.sub === sub);
    const row = (hers?.groups ?? []).flatMap((g: J) => g.devices ?? []).find((x: J) => x.id === wId);
    if (row?.kind !== "web") throw new Error(`W's page lists it under alice as ${JSON.stringify(row)?.slice(0, 200)}`);
    await wDev.stationState(workspace, (s) => s.state === "online", 30_000);
  });
  await check("alice's own lock as it was (W not on it); no person's binding changed", async () => {
    const own = await ownKeys();
    if (own !== ownBefore) throw new Error(`alice's own lock: ${own}, not ${ownBefore}`);
    const bound = bindings(stationSays("lock-state"));
    if (bound !== boundBefore) throw new Error(`bound in Dev: ${bound}, not ${boundBefore}`);
  });
  await check("W signs nothing and has no vault (not able, none keyed, the item refused); B still opens it", async () => {
    const l = await wDev.lock(workspace, (l) => l.me?.confirmed, 30_000);
    if (l.signs !== false || l.canSign !== false) throw new Error(`W's page: signs ${l.signs}, canSign ${l.canSign}`);
    const v = await wDev.until({ topic: "vaults", workspace }, (v) => v, 30_000);
    log(`  W's vaults: ${JSON.stringify({ available: v.available, canSign: v.canSign, setUp: v.setUp, vaults: (v.vaults ?? []).map((x: J) => ({ keyed: x.keyed, open: x.open })) })}`);
    if (v.available !== false || v.canSign !== false || v.setUp !== false || (v.vaults ?? []).some((x: J) => x.keyed || x.open)) throw new Error("W's vaults are not a web page's");
    const o = await wDev.call("vault.open", { workspace, item }).then((o) => o, (x) => x as Error);
    if (!(o instanceof Error)) throw new Error(`W opened: ${JSON.stringify(o)?.slice(0, 200)}`);
    log(`  W's vault.open: ${o.message.slice(0, 200)}`);
    if (!/vault_unavailable/.test(o.message)) throw new Error(`not refused as a web page: ${o.message.slice(0, 300)}`);
    await opens(b);
  });
  await check("W closed and started again: let in again, nobody asked", async () => {
    await wDev.restart();
    const t1 = Date.now();
    await wDev.stationState(workspace, (s) => s.state === "online", 60_000);
    log(`  W let in again ${Date.now() - t1} ms after it started`);
    const l = await wDev.lock(workspace, (l) => l.me?.confirmed && !l.me?.waiting, 30_000);
    if (l.me.pair != null) throw new Error(`W asked again: ${JSON.stringify(l.me.pair).slice(0, 200)}`);
    const shown = (await b.call("lockPrompt.state", {}))?.pairing ?? [];
    if (shown.length !== 0) throw new Error(`B shows a code: ${JSON.stringify(shown).slice(0, 200)}`);
  });
  // (as a person does it: 移除 beside the device on 设置 › 安全, as round 9 takes J out)
  await must("B takes W out on Dev's security page", async () => {
    const row = lockDevices(await b.lock(workspace, (l) => lockDevices(l).some((x) => x.id === wId), 30_000)).find((x) => x.id === wId);
    log(`  B's row for W: ${JSON.stringify({ kind: row.kind, removable: row.removable, daysLeft: row.daysLeft, metaText: row.metaText })}`);
    if (row.removable !== true) throw new Error("B's page offers no 移除 beside W");
    await b.call("lock.removeDevice", { workspace, device: wId });
  });
  await check("W out: the station refuses it for the lock, the station's lock lists it no more, its page says it waits", async () => {
    const t1 = Date.now();
    // (W's refusal is waited for, the station's lock then read once: the station writes an entry to its lock's file as
    // it takes it, before it closes anyone for it (station/src/cloud/state.ts `takeLock`). W's page says so up to
    // RECONNECT_MS (2 s) after: the station closes W's stream at once (13 ms after the entry, by its log), and W's link
    // opens the stream again, and is refused, after its wait unless something wakes it (the core's station/link.ts).)
    log(`  W sees the first: ${short(await wDev.stationState(workspace, (s) => s.state !== "online" && s.cause === "lock", 60_000))} ${Date.now() - t1} ms after B took it out`);
    const still = deviceIn(stationSays("lock-state"), wId);
    if (still !== null) throw new Error(`W still in the station's lock: ${JSON.stringify(still)}`);
    await wDev.lock(workspace, (l) => !l.me?.confirmed && l.me?.waiting, 60_000);
  });
  await check("B, alice's app, untouched: let in, signing, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 60_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 30_000);
    await opens(b);
  });
  // (done with: closed, as C, D, F and G are before round 8, for the account's requests)
  await within(wDev.close(), 5000);

  // ── round 17: a station in the workspace that its lock does not name (#5540). Enrolled with the token alone, the
  // lock's hash dropped, as the app's 添加这台 Mac enrolled one before #5545, it goes by the cloud's word: lets the
  // members in and answers GET /lock that it keeps none. A device that read it alone (its link opened, or it told
  // `lock`) took that for every station's answer and let go of the lock the others keep: safe mode off on it till its
  // app started again (views/lock.ts `readLockOf`). Then 设置 › 安全's 「保护」 beside it (`lock.joinStation`) takes it
  // into the lock, which it then keeps. Last, as it adds a station to the lock and takes it out: the rounds before count
  // the first station's lock's stations. The devices of alice's still open: B alone (A installed anew and W closed). ──
  const firstId = station.split("/")[1]!;
  const fourthData = `${process.env.E2E_STATION}-fourth/data`;
  /// The entries of the lock a station keeps for its home workspace (its mesh/lock.json, as lock-state reads it), null
  /// with none pinned (or the file mid-write: looked at again as it changes).
  const keptAt = (data: string): J[] | null => {
    try {
      const j = JSON.parse(readFileSync(`${data}/mesh/lock.json`, "utf8"));
      const es = (j.entries ?? j) as J[];
      return Array.isArray(es) && es.length > 0 ? es : null;
    } catch {
      return null;
    }
  };
  /// Its head, as the signed entry it ends in: the same seq and signature is the same lock as far.
  const headOf = (es: J[] | null) => (es === null ? null : `${es[es.length - 1].seq}:${es[es.length - 1].sig?.sig}`);
  /// Whether the entries name station `id` (its last word on it a `station` entry, not `station.remove`).
  const namesStation = (es: J[] | null, id: string) => (es ?? []).filter((x) => (x.kind === "station" || x.kind === "station.remove") && x.body?.key === id).pop()?.kind === "station";
  const stationRow = (l: J, id: string) => (l.stations ?? []).find((s: J) => s.id === id);
  let fourthId = "";
  // (when the fourth was enrolled: what B asks of it is answered after that, as it came online then)
  let enrolledAt = 0;
  await must("B holds Dev's lock, signing", async () => {
    const l = await b.lock(workspace, (l) => l.locked && l.signs, 30_000);
    log(`  B's lock: ${(l.stations ?? []).map((s: J) => `${s.id.slice(0, 8)}${s.protected ? " protected" : ""}`).join(", ")}`);
  });
  // What B's 设置 › 安全 shows of Dev's lock, every value of it, from before the fourth exists to the end of the check
  // below: one subscription all along (device.ts `watch`). A look of its own would not do: showing the lock, or asking
  // it (`lock.state`), reads it again of all its stations (views/lock.ts, "Shown: read again now"), which without the
  // fix took the lock back of the first station a moment after B let it go (run r42-e2e-7, B's record: the fourth's
  // `GET /lock/devices`, then `GET /lock?after=-1` of both), and the check saw it held. Its own read is of the first
  // station alone, the fourth not there yet.
  const bShown = b.watch({ topic: "lock", workspace });
  await must("B enrolls a fourth station in Dev with the token alone, the lock's hash dropped (as 添加这台 Mac did before #5545)", async () => {
    enrolledAt = Date.now();
    const made = await b.call("workspace.enroll", { account: sub, workspace, name: "fourth" });
    const hash = String(made?.command ?? "").match(/--lock ([0-9a-f]+)/)?.[1];
    if (!hash) throw new Error(`the command names no lock's hash: ${JSON.stringify(made)?.slice(0, 200)}`);
    log(`  the command names the lock's hash ${hash.slice(0, 12)}…, not given the station`);
    const at = `${dir}/enroll-fourth.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at, "fourth", "bare");
    const w = await b.until({ topic: "workspace", workspace }, (v) => (v?.stations ?? []).find((s: J) => s.id !== firstId && s.id !== secondId), 60_000);
    fourthId = w.id;
    log(`  the fourth station ${fourthId.slice(0, 12)}`);
  });
  await check("the fourth station unprotected: it keeps no lock for Dev, the first station's lock does not name it, B's security page lists it not protected", async () => {
    const said = stationSays("lock-state", "fourth").trim();
    log(`  the fourth's lock-state: ${said.split("\n").join("; ")}`);
    if (!/^LOCK off$/m.test(said) || keptAt(fourthData) !== null) throw new Error(`the fourth station keeps a lock: ${said}`);
    if (namesStation(keptAt(stationData), fourthId)) throw new Error("the first station's lock names the fourth");
    const l = await b.lock(workspace, (l) => stationRow(l, fourthId) !== undefined, 60_000);
    if (stationRow(l, fourthId).protected !== false || stationRow(l, firstId)?.protected !== true) throw new Error(`B's security page: ${JSON.stringify(l.stations)}`);
  });
  /// How B holds Dev's lock now: safe mode shown on, signing, the first station shown protected (its head on the chain
  /// B holds: views/lock.ts `keeps`) and the fourth not, the same devices as the first station's lock, the item opened.
  const bHolds = async (l: J) => {
    log(`  B's lock: locked ${l.locked}, signs ${l.signs}, stations ${(l.stations ?? []).map((s: J) => `${s.id.slice(0, 8)}${s.protected ? " protected" : ""}`).join(", ")}`);
    if (!l.locked) throw new Error("B shows safe mode off: it let go of the lock the first station keeps (#5540)");
    if (!l.signs) throw new Error("B does not sign in Dev's lock");
    if (stationRow(l, firstId)?.protected !== true) throw new Error(`the first station not shown protected: ${JSON.stringify(l.stations)}`);
    const theirs = stationSays("lock-state").split("\n").filter((x) => x.startsWith("DEVICE ")).map((x) => x.split(" ")[1]).sort().join(" ");
    const mine = lockDevices(l).map((x) => x.id.slice(0, 12)).sort().join(" ");
    if (mine !== theirs) throw new Error(`B's lock's devices ${mine}, the first station's ${theirs}`);
    await opens(b);
  };
  // The read itself, seen where it goes (device.ts `answered`): a read of a station's lock asks it `GET /lock?after=…`
  // and then `GET /lock/devices` (views/lock.ts `readLockOf`), the second's answer the end of that station's part. B's
  // first read of the fourth is of it alone, as its link opened (station/sync.ts `snapshot`, the lock's `also.read`).
  // Then a round trip to B's process that asks nothing of the lock (`lockPrompt.state`, the prompts as they are), and
  // what B's `lock` showed since the watch began is looked at: never off. That alone does not hold #5540: a core that
  // let go of the lock had not told the watch so by then (run with views/lock.ts as it was before the fix: `on on`).
  // What holds it is the item: the vault reads the lock B holds, and one that let go of it answers `vault_needs_lock`,
  // 请先开启 workspace 的安全模式, which is what #5540's phone said. Nothing here asks B's `lock` anew before that:
  // asking it is a read of every station, which gives a device that let go of the lock its lock back.
  await check("B reached the fourth station and read its lock alone: it holds Dev's lock as the first station keeps it, safe mode never shown off, the item opened (not asked to turn safe mode on)", async () => {
    try {
      log(`  B sees the fourth: ${short(await stationIn(b, fourthId, (s) => s.state === "online", 90_000))}`);
      const a = await b.answered(fourthId, "/lock/devices", enrolledAt, 90_000);
      log(`  B's ${a.method} ${a.path} of the fourth answered ${a.at - enrolledAt} ms after it was enrolled`);
      await b.call("lockPrompt.state", {});
      const since = bShown.values.filter((v) => v.at >= enrolledAt);
      log(`  B's lock shown ${bShown.values.length} times since the watch began, ${since.length} since the fourth was enrolled: ${bShown.values.map((v) => (v.value?.locked ? "on" : "off")).join(" ")}`);
      if (bShown.values.length === 0) throw new Error("B's lock was never shown");
      if (bShown.values.some((v) => v.value?.locked === false)) throw new Error("B shows safe mode off: it let go of the lock the first station keeps (#5540)");
      await bHolds(bShown.values[bShown.values.length - 1]!.value).catch((e) => {
        if (/vault_needs_lock/.test(String(e?.message ?? e))) throw new Error(`B is asked to turn safe mode on to open the item: it let go of the lock the first station keeps (#5540): ${String(e?.message ?? e).slice(0, 200)}`);
        throw e;
      });
    } finally {
      bShown.stop();
    }
  });
  // (started again, B reads every station's lock as its 设置 › 安全 is shown and asked (`lock.state`): this holds with
  // the fix or without it, and says only that B is let in by both and holds the lock once started again)
  await b.restart();
  await check("B started again: let in by both stations, it holds Dev's lock (read of all its stations as it is shown), the item opened", async () => {
    for (const id of [firstId, fourthId]) await stationIn(b, id, (s) => s.state === "online", 90_000);
    await bHolds(await b.call("lock.state", { workspace }));
  });
  // ── 设置 › 安全's 「保护」 beside the fourth station, on B (an owner's device signing in the lock) ──
  await must("B protects the fourth station (「保护」, lock.joinStation)", async () => {
    const r = await b.call("lock.joinStation", { workspace, station: fourthId });
    log(`  joinStation: ${JSON.stringify(r)?.slice(0, 300)}`);
  });
  await check("the first station's lock names the fourth; the fourth keeps Dev's lock, as far as the first", async () => {
    await whenChanged([stationData, fourthData], () => {
      const ours = keptAt(stationData);
      return namesStation(ours, fourthId) && headOf(keptAt(fourthData)) === headOf(ours);
    }, 60_000, () => `the first's head ${headOf(keptAt(stationData))} (names the fourth: ${namesStation(keptAt(stationData), fourthId)}), the fourth's ${headOf(keptAt(fourthData))}`);
    log(`  both at ${headOf(keptAt(stationData))?.slice(0, 20)}; the fourth's lock-state: ${stationSays("lock-state", "fourth").trim().split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
  });
  await check("B's security page lists the fourth station protected; B still holds the lock and opens the item", async () => {
    const l = await b.lock(workspace, (l) => stationRow(l, fourthId)?.protected === true, 60_000);
    if (!l.locked || !l.signs) throw new Error(`B's lock: locked ${l.locked}, signs ${l.signs}`);
    await opens(b);
  });
  // (as round 11 takes the second out, and the rigs' run its rig: out of the workspace, then down)
  await must("B takes the fourth station out of Dev: the first station's lock names it no more; it goes down", async () => {
    await b.call("workspace.removeStation", { account: sub, workspace, station: fourthId });
    await whenChanged([stationData], () => !namesStation(keptAt(stationData), fourthId), 60_000, () => "the first station's lock still names the fourth");
    stationDo("second-down", "fourth");
  });
  await check("B goes on in Dev, safe mode on, alice's item opened", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 60_000);
    await b.lock(workspace, (l) => l.locked && l.signs, 30_000);
    await opens(b);
  });
  // ── round 18: no station up (3b-2). The workspace's one station left frozen (asked, it never answers), the cloud up:
  // B removes A installed anew (its own lock bound here, so off that first and out of the workspace's after it,
  // views/lock.ts `run`'s removeDevice). No station takes it: pending, said so at once, nothing on the chains held
  // (A installed anew still listed), the cloud's taking it counting for nothing; the station back, B brings it as it
  // reads it again, and A installed anew is refused ──
  const firstName = (stationRow(await b.lock(workspace, (l) => stationRow(l, firstId) !== undefined, 30_000), firstId)?.name ?? "") as string;
  stationDo("freeze");
  try {
    await check("no station up: B removes A installed anew, answered within seconds as pending; B's page shows it waiting for the station by name, A installed anew still listed", async () => {
      const t0 = Date.now();
      const r = await b.call("lock.removeDevice", { workspace, device: eId });
      const ms = Date.now() - t0;
      log(`  answered after ${ms} ms: ${JSON.stringify(r)?.slice(0, 300)}`);
      if (ms > 10_000) throw new Error(`answered after ${ms} ms`);
      if (r?.pending?.state !== "waiting") throw new Error("not answered as pending");
      const l = await b.lock(workspace, (l) => (l.pending ?? []).some((x: J) => x.state === "waiting" && (x.stations ?? []).includes(firstName)), 10_000);
      log(`  B's page: ${JSON.stringify(l.pending)?.slice(0, 300)}`);
      if (!lockDevices(l).some((x) => x.id === eId)) throw new Error("A installed anew is not listed while its removal is pending");
    });
  } finally {
    stationDo("thaw");
  }
  await check("the station started: within seconds the removal is on its chain, nothing pending on B's page, A installed anew refused", async () => {
    const t1 = Date.now();
    await whenChanged([stationData], () => (keptAt(stationData) ?? []).some((x) => x.kind === "device.remove" && x.body?.id === eId), 20_000, () => "the station's chain has no removal of A installed anew");
    log(`  on the station's chain ${Date.now() - t1} ms after it was up`);
    await b.lock(workspace, (l) => (l.pending ?? []).length === 0 && !lockDevices(l).some((x) => x.id === eId), 20_000);
    await e.restart();
    log(`  A installed anew sees: ${short(await stationIn(e, firstId, (s) => s.state !== "online" && s.state !== "connecting", 60_000))}`);
  });
} catch (e) {
  fail("the run", e);
}
log(failures() === 0 ? "ALL PASSED" : `${failures()} FAILED`);
await within(Promise.all([a, b, c, d, e, f, g, h, i, j, k, lDev, mDev, nDev, oDev, d1, d2, e1, wDev].map((x) => x.close())), 5000);
process.exit(failures() === 0 ? 0 : 1);
