// The locks of a workspace whose chain moved to its people's own logs, end to end against the local still.fail
// (scripts/e2e-local.sh locks-moved, after up; locks-moved-all, the side run's): a run of its own beside e2e/locks.ts,
// a fresh cloud and stations, so that the earlier rounds' devices and history (and their share of an account's
// requests a minute, account.ts) are not in it. Its devices are e2e/device.ts's, as locks.ts's. The dev cloud's "Dev"
// workspace, its test station (the first) and a second taken into its lock by its code:
//   19 alice, its owner, with two apps (A, P) and a web page (X); frank an admin and gina a member, each with an app
//     approved face to face and bound to a lock of their own; a vault of alice's and one of gina's. A hands the chain
//     over (`lock.handOver`, offered by this driver's host only, device.ts): asked nothing (the chain as it moved still
//     says what the logs have not, 2026-11-14: `moved` alone); both stations hold it moved and on with the chain's list
//     (lock-state: `MOVED <root> <on>`), gina's web page in too; every device started anew let in by both, nobody else
//     asked; the vaults used with the asks of before.
//   20 the acts of the moved workspace, each a statement in its actor's own log: frank made an owner by A; hank's
//     first app (S) approved by frank's Q with the role frank gave; frank's web page (Y) approved by his own app,
//     renewed, taken off; a station added by frank by its code and taken out; P off alice's own lock, her vault
//     waiting then keyed anew; gina taken out by frank (her app loses the workspace); frank answered `lock_root_only`; off and on again by A. X is
//     closed meanwhile (one account's requests a minute, the cloud's 120).
//   21 the cloud frozen and the stations apart: X off at the first, one state at both once the second is back; S
//     started anew let in by both.
//   22 alice's new app N after P went: refused by both, its page joining her own log, no admin named; it asks from the
//     page that waits, A shows the code, nothing asked on N; given A's vault, nothing done on A.
//   23 ivy, carried with no log of her own: set up at round 19's start while A says a release under MOVED_FROM_BUILD
//     (the chain held unmoved), her app J one that never says the key of a lock of one's own (no sealer) approved
//     by A, then I, which can, by J, and I begins no log while J stands unsaid (views/lock.ts `ownLockOnce`'s `waiting`)
//     and J holds no move back (it says no build, taken as able): the commonest member at a move, a stale second app
//     in their list (the lead, 2026-11-14). A comes back on a release that moves the chain, and it moves with nobody
//     asked, ivy carried, bound to no log. At the end: I approves her third app K from its page (one ask on I, nobody
//     else asked, K given her vault, ivy bound to the log begun in that ask by her own `bind`), her web page W, takes J
//     off; frank (an owner) makes her an admin and takes her out, as any member. jade, set up beside her as she was
//     (M with no sealer approved by A, O by M) and doing nothing after the move, is taken out by frank and added again:
//     her new app L, told by the stations that the list names no app of hers, is a newcomer (its own log begun, Q
//     asked once, nothing on L) and in at both, jade bound by that admit. What alice's and frank's sign-ins asked the
//     cloud in the minute before frank's acts is logged (`requestsOf`): alice's account is near its 120 by then.
// Chains are handed over by themselves on every build from HAND_OVER_FROM (client/core-ts src/lock-handover.ts; the
// user, 2026-11-14: 无感迁移, no date, no switch), so by default nothing calls `lock.handOver`: P's joining alice's own
// lock face to face, the ask for something else that A answers, is moved from round 19's start to where the call was
// (and P's vault, which needs P let in, after it), and the workspace moves by itself once every station and app device
// of it said a build that takes it; the rounds after the move are as they are. E2E_HANDOVER=call is the round of
// before, A calling `lock.handOver` after P joined at round 19's start: on these builds the chain moves by itself on one
// of A's asks before the call (the call then answers it done with nobody asked), so it holds only where the devices'
// clock is before HAND_OVER_FROM, and is not the side run's.
// Each check says PASS or FAIL; it goes on after a failure where it can, and exits 1 if any failed. E2E_SF_SRC,
// E2E_ORIGIN, E2E_PEER_DATA as peer.ts; E2E_WORK, E2E_STATION as e2e-local.sh's.
import { createPrivateKey, createPublicKey, randomBytes } from "node:crypto";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { check, Device, dir, fail, failures, type J, log, must, stationDo, stationSays, whenChanged, within } from "./device.ts";

const auto = process.env.E2E_HANDOVER !== "call";
const short = (s: J) => JSON.stringify({ state: s.state, cause: s.cause, message: s.message });

// alice's two apps and her web page; frank, an admin, and gina, a member, an app each
// (A says a release under MOVED_FROM_BUILD until ivy is set up, round 19's start: the chain held unmoved meanwhile)
const vDev = new Device("A", "alice", { build: "0.1.9000" });
const pDev = new Device("P");
const xDev = new Device("X", "alice", { page: true });
const qDev = new Device("Q", "frank");
const rDev = new Device("R", "gina");
// gina's web page, approved on the chain by R before the move, and her second app; hank, a member after the move (his
// first app); frank's web page
const gDev = new Device("G", "gina", { page: true });
const tDev = new Device("T", "gina");
const sDev = new Device("S", "hank");
const yDev = new Device("Y", "frank", { page: true });
// alice's new app after P was taken off (round 22)
const nDev = new Device("N");
// ivy's apps: J, one that never says the key of a lock of one's own (no sealer), and I, an app of today; her third app
// and her web page (round 23)
const jDev = new Device("J", "ivy", { sealed: false });
const iDev = new Device("I", "ivy");
const kDev = new Device("K", "ivy");
const wDev = new Device("W", "ivy", { page: true });
// jade, set up as ivy (her app M with no sealer, O by M), who does nothing after the move, and her new app once she
// was taken out and added again (round 23's end)
const mDev = new Device("M", "jade", { sealed: false });
const oDev = new Device("O", "jade");
const lDev = new Device("L", "jade");
const fifthData = `${process.env.E2E_STATION}/data`;
const sixthData = `${process.env.E2E_STATION}-b/data`;
try {
  const { workspace: three, station } = await vDev.signIn();
  const fifthId = station.split("/")[1]!;
  let sixthId = "";
  log(`A signed in as ${vDev.sub}: workspace ${three}, station ${fifthId}`);
  await vDev.stationState(three, (s) => s.state === "online", 120_000);
  const baseOf = async (d: Device) => (await d.lock(three, (l) => typeof l.me?.device === "string")).me.device as string;
  const vBase = await baseOf(vDev);
  const inThree = (x: Device, id: string, ok: (s: J) => boolean, ms = 90_000) => x.stationState(three, ok, ms, id);
  const both = () => [fifthId, sixthId];
  /// What `devices`' sign-ins asked the dev cloud, by its log (LOG_REQUESTS, cloud/test/dev.ts: each request's time,
  /// route and token's last six characters): in the clock's minute the cloud counts now (account.ts `charge`) and in the
  /// last 60 s, the locks' routes apart (a minute of their own, api.ts LOCK_ROUTE). A token refreshed since its sign-in
  /// is not counted.
  const requestsOf = (devices: Device[]) => {
    const tails = new Set(devices.map((d) => d.tokenTail).filter((t) => t !== ""));
    const at = (t: string) => {
      const [h, m, s] = t.split(":");
      return (Number(h) * 60 + Number(m)) * 60_000 + Number(s) * 1000;
    };
    const now = new Date().toISOString().slice(11, 23);
    let minute = 0, last = 0, locks = 0;
    for (const line of readFileSync(`${process.env.E2E_WORK}/run/cloud.log`, "utf8").split("\n")) {
      const m = line.match(/REQ (\d\d:\d\d:\d\d\.\d+) \d+ \S+ (\S+) (\S+)/);
      if (!m || !tails.has(m[3]!)) continue;
      const ago = at(now) - at(m[1]!);
      if (/^\/v1\/(me\/personal-lock|workspaces\/[^/]+\/(lock(\/.*)?|devices))$/.test(m[2]!)) {
        if (ago >= 0 && ago < 60_000) locks++;
        continue;
      }
      if (m[1]!.slice(0, 5) === now.slice(0, 5)) minute++;
      if (ago >= 0 && ago < 60_000) last++;
    }
    return `${minute} in this minute, ${last} in the last 60 s (${locks} more on the locks' routes)`;
  };
  /// `x` approved into the workspace's lock from its waiting page, the code shown on `approver` (as locks.ts's `approvedBy`),
  /// let in by `at` (both stations by default).
  const approvedInThree = async (x: Device, page = false, approver: Device = vDev, at: () => string[] = both) => {
    await x.lock(three, (l) => l.me?.waiting && !l.me?.ownLock, 90_000);
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await x.call("lock.pair", { workspace: three });
    const p = await shown;
    await x.lock(three, (l) => l.me?.pair?.state === "code", 60_000);
    await x.call("lock.pairCode", { workspace: three, code: p.code });
    await x.lock(three, (l) => (page || l.signs) && l.me?.confirmed, 90_000);
    for (const id of at()) await inThree(x, id, (s) => s.state === "online");
  };
  /// `d` on `approver`'s person's own lock face to face, as locks.ts's `joinVia` (typed once the field for the code is shown).
  const joinVia = async (approver: Device, d: Device) => {
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub: approver.sub });
    const p = await shown;
    await d.personal((p) => p.pair?.state === "code", 60_000);
    await d.call("adb.personalCode", { code: p.code });
    await d.personal((p) => p.standing === "member", 90_000);
  };
  /// lock-state of the first station (`fifth`) or the second (`sixth`), the names this file's checks use for them.
  const threeSays = (n: "fifth" | "sixth") => (n === "fifth" ? stationSays("lock-state") : stationSays("lock-state", "second"));
  const personsAt = (said: string) => Number(said.match(/^PERSONS (\d+)$/m)?.[1] ?? NaN);

  // ── round 19: the handover (#5967) ──
  await must("A turns safe mode on, the only device in it, and begins alice's own lock by itself", async () => {
    const draft = await vDev.until({ topic: "lockDraft", workspace: three }, (v) => (v?.ready ? v : undefined), 120_000);
    for (const d of draft.devices ?? []) if (!d.current) await vDev.call("lock.toggle", { workspace: three, id: d.id });
    await vDev.call("lock.open", { workspace: three });
    await vDev.lock(three, (l) => l.locked && l.signs);
    await vDev.personal((p) => p.standing === "member", 90_000);
  });
  // ── round 23's setup: ivy, before the chain moves (A on a release under MOVED_FROM_BUILD) ──
  const memberAt = (said: string, who: string) => said.match(new RegExp(`^MEMBER ${who} (\\S+)`, "m"))?.[1] ?? null;
  const personAt = (said: string, who: string) => new RegExp(`^PERSON ${who} `, "m").test(said);
  const firstSays = () => threeSays("fifth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ");
  const ivyVault = { vault: "", item: "", secret: "" };
  await must("A adds ivy; her app J (no sealer) approved by A, then her app I by J (her own, as before a move): on the chain, no log of hers", async () => {
    await vDev.call("workspace.addMembers", { account: vDev.sub, workspace: three, role: "member", emails: ["ivy@example.test"] });
    // (the second station not enrolled yet: let in by the first; I, ivy's second app, asks her own J, views/pair.ts
    // `waitingIn`: J signs, so she is no first device to owners and admins)
    await jDev.signIn();
    await approvedInThree(jDev, false, vDev, () => [fifthId]);
    await iDev.signIn();
    await approvedInThree(iDev, false, jDev, () => [fifthId]);
    await whenChanged([fifthData], () => !/^MOVED /m.test(threeSays("fifth")) && memberAt(threeSays("fifth"), iDev.sub) === "member" && !personAt(threeSays("fifth"), iDev.sub), 60_000, () => `the first: ${firstSays()}`);
    const p = await iDev.personal(() => true, 30_000).catch(() => null);
    log(`  I's own lock: ${p?.standing ?? "none listed"}`);
    if (p !== null && p.standing !== "none") throw new Error(`I stands ${p.standing} on a lock of ivy's own`);
  });
  await must("A adds jade; her app M (no sealer) approved by A, then her app O by M: on the chain, no log of hers", async () => {
    await vDev.call("workspace.addMembers", { account: vDev.sub, workspace: three, role: "member", emails: ["jade@example.test"] });
    await mDev.signIn();
    await approvedInThree(mDev, false, vDev, () => [fifthId]);
    await oDev.signIn();
    await approvedInThree(oDev, false, mDev, () => [fifthId]);
    await whenChanged([fifthData], () => memberAt(threeSays("fifth"), oDev.sub) === "member" && !personAt(threeSays("fifth"), oDev.sub), 60_000, () => `the first: ${firstSays()}`);
  });
  await check("I sets up ivy's vault on the chain with an item", async () => {
    await iDev.call("vault.setup", { workspace: three });
    await iDev.until({ topic: "vaults", workspace: three }, (v) => v?.setUp, 60_000);
    ivyVault.secret = `ghp_ivy_${Date.now()}`;
    ivyVault.vault = (await iDev.call("vault.create", { workspace: three, name: "ivy", station: fifthId })).id as string;
    ivyVault.item = (await iDev.call("vault.putItem", {
      workspace: three, vault: ivyVault.vault,
      plain: { kind: "token", name: "ivy-token", fields: { value: ivyVault.secret }, domains: [], notes: "" },
      listing: { name: "ivy-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id as string;
  });
  await must("A back on a release that moves it: the chain moves by itself, nobody asked; ivy carried, bound to no log; I still in", async () => {
    const from = [vDev, iDev].map((x) => [x, x.asked()] as const);
    vDev.build = "0.1.9170";
    await vDev.restart();
    await whenChanged([fifthData], () => /^MOVED \S+ on /m.test(threeSays("fifth")) && memberAt(threeSays("fifth"), iDev.sub) === "member" && !personAt(threeSays("fifth"), iDev.sub), 120_000, () => `the first: ${firstSays()}`);
    for (const [x, n] of from) if (x.asked() !== n) throw new Error(`${x.name} asked the person: ${x.askedWhat(n).join("; ")}`);
    await inThree(iDev, fifthId, (s) => s.state === "online");
  });
  await check("I opens ivy's vault after the move", async () => {
    const o = await iDev.call("vault.open", { workspace: three, item: ivyVault.item });
    if (o?.plain?.fields?.value !== ivyVault.secret) throw new Error(`I opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  });
  await must("A enrolls a second station with the lock's hash and takes it into the lock by its code: both in the lock, alice bound", async () => {
    const made = await vDev.call("workspace.enroll", { account: vDev.sub, workspace: three, name: "second" });
    const at = `${dir}/enroll.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at);
    const said = readFileSync(`${process.env.E2E_WORK}/run/second-enroll.log`, "utf8");
    const code = said.match(/(?:code|安全码为)\s*([0-9A-Z-]{4,})/i)?.[1];
    if (!code) throw new Error(`no code in: ${said}`);
    sixthId = (await vDev.until({ topic: "workspace", workspace: three }, (v) => (v?.stations ?? []).find((s: J) => s.id !== fifthId), 60_000)).id as string;
    await vDev.call("lock.addStation", { workspace: three, station: sixthId, code });
    await whenChanged([fifthData, sixthData], () => [threeSays("fifth"), threeSays("sixth")].every((s) => /^STATIONS 2$/m.test(s) && personsAt(s) === 1), 60_000, () => `the first: ${threeSays("fifth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
    for (const id of both()) await inThree(vDev, id, (s) => s.state === "online", 120_000);
  });
  const pJoins = async () => {
    await must("P, alice's second app, joins her own lock face to face with A", async () => {
      await pDev.signIn();
      await joinVia(vDev, pDev);
    });
    await check("P, on alice's own lock, let in by both of the workspace's stations, signing", async () => {
      for (const id of both()) await inThree(pDev, id, (s) => s.state === "online");
      await pDev.lock(three, (l) => l.signs && l.me?.confirmed, 60_000);
    });
  };
  const pVault = async () => {
    await pDev.call("vault.setup", { workspace: three });
    await pDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((y: J) => y.id === threeVaults.get(vDev)!.vault && y.keyed), 90_000);
  };
  if (!auto) await pJoins();
  await must("X, alice's web page, approved in the workspace's lock by A face to face", async () => {
    await xDev.signIn();
    await approvedInThree(xDev, true);
  });
  await must("A adds frank as an admin and gina as a member; each one's first app approved by A face to face, each bound to a lock of their own", async () => {
    await vDev.call("workspace.addMembers", { account: vDev.sub, workspace: three, role: "admin", emails: ["frank@example.test"] });
    await vDev.call("workspace.addMembers", { account: vDev.sub, workspace: three, role: "member", emails: ["gina@example.test"] });
    for (const x of [qDev, rDev]) {
      await x.signIn();
      await approvedInThree(x);
      await x.personal((p) => p.standing === "member", 90_000);
    }
    await whenChanged([fifthData, sixthData], () => [threeSays("fifth"), threeSays("sixth")].every((s) => personsAt(s) === 3), 90_000, () => `persons: fifth ${personsAt(threeSays("fifth"))}, sixth ${personsAt(threeSays("sixth"))}`);
  });
  await must("G, gina's web page, approved in the workspace's lock by her app R face to face", async () => {
    await gDev.signIn();
    await approvedInThree(gDev, true, rDev);
  });
  const gId = await baseOf(gDev);
  const gLine = (s: string) => new RegExp(`^DEVICE ${gId.slice(0, 12)} ${rDev.sub} web `, "m").test(s);
  // A vault of `owner`'s in the workspace with an item, and how it is used: locked first (no key in memory), opened, an item
  // written; what its sealer was asked for that, a line each.
  const threeVaults = new Map<Device, { vault: string; item: string; secret: string }>();
  const vaultUse = async (x: Device): Promise<string[]> => {
    const v = threeVaults.get(x)!;
    const from = x.asked();
    await x.call("vault.lock", { workspace: three });
    const o = await x.call("vault.open", { workspace: three, item: v.item });
    if (o?.plain?.fields?.value !== v.secret) throw new Error(`${x.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
    await x.call("vault.putItem", {
      workspace: three, vault: v.vault,
      plain: { kind: "token", name: `w-${Date.now()}`, fields: { value: "w" }, domains: [], notes: "" },
      listing: { name: `w-${Date.now()}`, kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    });
    return x.askedWhat(from).map((l) => l.split(" ").slice(1, 3).join(" "));
  };
  const usedBefore = new Map<Device, string[]>();
  const atBoth = (what: string, ok: (said: string) => boolean, ms = 60_000) =>
    whenChanged([fifthData, sixthData], () => [threeSays("fifth"), threeSays("sixth")].every(ok), ms, () => `${what}: fifth ${threeSays("fifth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
  /// What `x`'s sealer was asked while `act` ran, a line each.
  const asksOf = async (x: Device, act: () => Promise<unknown>): Promise<string[]> => {
    const from = x.asked();
    await act();
    return x.askedWhat(from).map((l) => l.split(" ").slice(1).join(" "));
  };
  await must("A and R each set up a vault of their own in the workspace on the first station, keep an item, open and write it", async () => {
    for (const x of [vDev, rDev]) {
      await x.call("vault.setup", { workspace: three });
      await x.until({ topic: "vaults", workspace: three }, (v) => v?.setUp, 60_000);
      const secret = `ghp_three_${x.name}_${Date.now()}`;
      const vault = (await x.call("vault.create", { workspace: three, name: `three-${x.name}`, station: fifthId })).id as string;
      const item = (await x.call("vault.putItem", {
        workspace: three, vault,
        plain: { kind: "token", name: "three-token", fields: { value: secret }, domains: [], notes: "" },
        listing: { name: "three-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
      })).id as string;
      threeVaults.set(x, { vault, item, secret });
      usedBefore.set(x, await vaultUse(x));
      log(`  ${x.name}'s vault used on the chain, asked: ${usedBefore.get(x)!.join("; ") || "nothing"}`);
    }
    if (!auto) await pVault();
  });
  const threeDevices = [vDev, pDev, xDev, qDev, rDev];
  const askedAt = new Map(threeDevices.filter((x) => !auto || x !== pDev).map((x) => [x, x.asked()]));
  const rootOf = (said: string) => said.match(/^MOVED (\S+) (\S+)/m);
  const devicesIn = (s: string) => s.split("\n").filter((x) => x.startsWith("DEVICE ")).map((x) => x.split(" ").slice(1, 4).join(" ")).sort().join("; ");
  const personsIn3 = (s: string) => s.split("\n").filter((x) => x.startsWith("PERSON ")).sort().join("; ");
  // (the list as the chain has it at the first, before the move: what the state in force is held to after it)
  const onChain = threeSays("fifth");
  // (by itself: P, joining alice's own lock, is on her log and so in the state the move makes, though the chain never
  // named it; its line is held apart)
  let pLine = (_s: string) => false;
  if (auto) await must("A hands the workspace's chain over by itself, nothing calls lock.handOver, as it approves P on alice's own lock face to face: A asked once, for P", async () => {
    const t1 = Date.now();
    await pDev.signIn();
    const asked = await asksOf(vDev, () => joinVia(vDev, pDev));
    const pBase = await baseOf(pDev);
    pLine = (s: string) => new RegExp(`^DEVICE ${pBase.slice(0, 12)} `, "m").test(s);
    log(`  A asked: ${asked.join("; ")}`);
    if (asked.length !== 1) throw new Error(`A asked ${asked.length} times`);
    await atBoth("moved", (s) => rootOf(s)?.[2] === "on", 90_000);
    log(`  moved at both ${Date.now() - t1} ms after P began to join`);
  });
  else await must("A hands the workspace's chain over to its people's own logs: answered done, A asked nothing", async () => {
    const t1 = Date.now();
    const r = await vDev.call("lock.handOver", { workspace: three });
    log(`  lock.handOver answered ${JSON.stringify(r)?.slice(0, 200)} after ${Date.now() - t1} ms`);
    if (r !== null) throw new Error(`not handed over: ${JSON.stringify(r)?.slice(0, 300)}`);
    const asked = vDev.askedWhat(askedAt.get(vDev));
    log(`  A asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 0) throw new Error(`A asked ${asked.length} times`);
  });
  await check("both stations hold the workspace's chain moved to alice's own log and on, the list as the chain had it: two stations, three persons, the same devices, gina's web page too", async () => {
    const said = await whenChanged([fifthData, sixthData], () => {
      const s = [threeSays("fifth"), threeSays("sixth")];
      return s.every((x) => rootOf(x)?.[2] === "on" && /^LOCK on /m.test(x)) ? s : null;
    }, 60_000, () => `first: ${threeSays("fifth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}; sixth: ${threeSays("sixth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
    log(`  first: ${said[0]!.split("\n").filter((x) => !x.startsWith("DEVICE") && !x.startsWith("SAID")).join("; ")}`);
    const alice = said[0]!.match(new RegExp(`^PERSON ${vDev.sub} (\\S+)`, "m"))?.[1];
    if (rootOf(said[0]!)?.[1] !== alice || rootOf(said[1]!)?.[1] !== alice) throw new Error(`the root is not alice's own log (${alice})`);
    for (const s of said) {
      if (!/^STATIONS 2$/m.test(s)) throw new Error(`moved: ${s.split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
      if (personsIn3(s) !== personsIn3(onChain)) throw new Error(`persons on the chain ${personsIn3(onChain)}; moved ${personsIn3(s)}`);
      if (auto && !pLine(s)) throw new Error("P not in the state the move made");
      const notP = (x: string) => x.split("\n").filter((l) => !pLine(l)).join("\n");
      if (devicesIn(notP(s)) !== devicesIn(notP(onChain))) throw new Error(`devices on the chain ${devicesIn(onChain)}; moved ${devicesIn(s)}`);
      if (!gLine(onChain) || !gLine(s)) throw new Error(`G on the chain ${gLine(onChain)}, moved ${gLine(s)}`);
    }
    log(`  ${devicesIn(onChain).split("; ").length} devices, as on the chain: ${devicesIn(onChain).split("; ").map((x) => x.split(" ").slice(1).join(" ")).join(", ")}`);
  });
  if (auto) {
    await check("P, on alice's own lock, let in by both of the workspace's stations, signing", async () => {
      for (const id of both()) await inThree(pDev, id, (s) => s.state === "online");
      await pDev.lock(three, (l) => l.signs && l.me?.confirmed, 60_000);
    });
    await check("P's vault set up after the move: A's vault keyed for it", pVault);
    askedAt.set(pDev, pDev.asked());
  }
  await check("every device of the workspace's started anew: let in by both stations, its page in safe mode, confirmed; nobody but A asked", async () => {
    for (const x of threeDevices) {
      await x.restart();
      for (const id of both()) await inThree(x, id, (s) => s.state === "online");
      await x.lock(three, (l) => l.locked && l.me?.confirmed, 60_000);
    }
    const asked = threeDevices.filter((x) => x !== vDev).map((x) => `${x.name}: ${x.askedWhat(askedAt.get(x)).join(", ") || "nothing"}`);
    log(`  asked since the handover: ${asked.join("; ")}`);
    if (threeDevices.some((x) => x !== vDev && x.asked() !== askedAt.get(x))) throw new Error(`asked: ${asked.join("; ")}`);
  });
  await check("after the move, A's vault and R's read and written as on the chain, asked the same", async () => {
    for (const x of [vDev, rDev]) {
      const now = await vaultUse(x);
      log(`  ${x.name}'s vault used after the move, asked: ${now.join("; ") || "nothing"}`);
      if (now.join("; ") !== usedBefore.get(x)!.join("; ")) throw new Error(`${x.name} asked ${now.join("; ")}, on the chain ${usedBefore.get(x)!.join("; ")}`);
    }
  });
  await check("G, gina's web page on the chain: let in by both stations after the move, nobody asked; gina's second app T approved face to face by R, one ask on R, G still in", async () => {
    for (const id of both()) await inThree(gDev, id, (s) => s.state === "online");
    await gDev.lock(three, (l) => l.locked && l.me?.confirmed, 60_000);
    await tDev.signIn();
    const asked = await asksOf(rDev, () => joinVia(rDev, tDev));
    log(`  R asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`R asked ${asked.length} times`);
    await atBoth("G at both", gLine);
    for (const id of both()) await inThree(gDev, id, (s) => s.state === "online");
  });
  // ── round 20: the acts of a moved workspace, each end to end on the workspace after round 19's move (views/lock.ts: each a
  // statement in the actor's own log, `sayMoved`, which asks its person each time; client/core-ts/AGENTS.md, A lock
  // held here). A newcomer's first app approved face to face (`member` said by A, one ask) with the role A gave as it
  // added them; frank made an owner; frank's web page approved by his own app, renewed, taken off; a station added by
  // its code and taken out; P taken off alice's own lock, her vault waiting and keyed anew as A next opens it; gina
  // taken out, refused by both, her page's topic as it stands; off and on again by A (alice's, the root), frank, an
  // owner now, answered `lock_root_only` ──
  await check("frank made an owner by A: an owner at both stations, A asked once", async () => {
    const asked = await asksOf(vDev, () => vDev.call("workspace.setRole", { account: vDev.sub, workspace: three, member: qDev.sub, role: "owner" }));
    log(`  A asked: ${asked.join("; ") || "nothing"}`);
    await atBoth("frank an owner", (s) => memberAt(s, qDev.sub) === "owner");
    if (asked.length !== 1) throw new Error(`A asked ${asked.length} times`);
  });
  // (X, alice's web page, closed till round 21, started again there with the cloud frozen: one account's devices ask
  // the cloud ~2 reads each at every change of the workspace's, and all of alice's acts and reads of rounds 19 to 21
  // are past the cloud's 120 a minute for one account, account.ts LIMITS; the acts that need not be alice's are frank's,
  // an owner from here on, as an owner's acts mean the same whoever's they are)
  const xBase = await baseOf(xDev);
  await xDev.close();
  // (S begins hank's own log as it asks, its key made then: nobody asked on it, as before a move; views/pair.ts `ownLogFor`,
  // 2026-11-14: it was asked 「批准你的新设备」, the approver's words)
  await check("hank, added by frank (an owner) as a member after the move: his first app S approved by frank's app Q face to face, one ask on Q and none on S, a member at both stations, let in by both", async () => {
    await qDev.call("workspace.addMembers", { account: qDev.sub, workspace: three, role: "member", emails: ["hank@example.test"] });
    await sDev.signIn();
    const sFrom = sDev.asked();
    const asked = await asksOf(qDev, () => approvedInThree(sDev, false, qDev));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`Q asked ${asked.length} times`);
    if (sDev.asked() !== sFrom) throw new Error(`S asked the person: ${sDev.askedWhat(sFrom).join("; ")}`);
    await atBoth("hank a member", (s) => memberAt(s, sDev.sub) === "member");
    await sDev.personal((p) => p.standing === "member", 90_000);
  });
  let yId = "";
  await check("frank's web page Y approved by his own app Q face to face: let in by both stations, a web page of his there", async () => {
    await yDev.signIn();
    yId = await baseOf(yDev);
    const asked = await asksOf(qDev, () => approvedInThree(yDev, true, qDev));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    await atBoth("Y frank's web page", (s) => new RegExp(`^DEVICE ${yId.slice(0, 12)} ${qDev.sub} web `, "m").test(s));
  });
  // (which order the run covers: E2E_THIRD=last puts the third's id after one of the two's; first by default)
  const thirdFirst = process.env.E2E_THIRD !== "last";
  let thirdId = "";
  await check("a station enrolled by frank after the move, taken into its list by its code on Q: three at both, it holds the list moved and on; taken out: two again", async () => {
    const made = await qDev.call("workspace.enroll", { account: qDev.sub, workspace: three, name: "third" });
    const at = `${dir}/enroll-third.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    // (its key the run's, its id first of the three or not as E2E_THIRD says: the vault's fault #6056 mended showed only
    // where it sorted first and A had copied its vault there, round "P taken off alice's own lock by A")
    const seedFile = `${process.env.E2E_WORK}/run/third.seed`;
    for (;;) {
      const seed = randomBytes(32);
      const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]), format: "der", type: "pkcs8" });
      const id = Buffer.from(createPublicKey(key).export({ format: "jwk" }).x as string, "base64url").toString("hex");
      if ((id < fifthId && id < sixthId) === thirdFirst) {
        writeFileSync(seedFile, seed);
        break;
      }
    }
    try {
      stationDo("second-station", at, "third");
    } finally {
      rmSync(seedFile, { force: true });
    }
    const said = readFileSync(`${process.env.E2E_WORK}/run/third-enroll.log`, "utf8");
    const code = said.match(/(?:code|安全码为)\s*([0-9A-Z-]{4,})/i)?.[1];
    if (!code) throw new Error(`no code in: ${said}`);
    const id = (await qDev.until({ topic: "workspace", workspace: three }, (v) => (v?.stations ?? []).find((s: J) => s.id !== fifthId && s.id !== sixthId), 60_000)).id as string;
    thirdId = id;
    const asked = await asksOf(qDev, () => qDev.call("lock.addStation", { workspace: three, station: id, code }));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    await atBoth("three stations", (s) => /^STATIONS 3$/m.test(s));
    const third = `${process.env.E2E_STATION}-third/data`;
    await whenChanged([third], () => /^MOVED \S+ on /m.test(stationSays("lock-state", "third")), 60_000, () => `the third: ${stationSays("lock-state", "third").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
    await inThree(qDev, id, (s) => s.state === "online");
    await qDev.call("workspace.removeStation", { account: qDev.sub, workspace: three, station: id });
    await atBoth("two stations", (s) => /^STATIONS 2$/m.test(s));
    stationDo("second-down", "third");
  });
  // (renewed some seconds after it was approved: a `web` renewed in the same second ends when it did, and says nothing new)
  await check("Y renewed by Q: its end moved on at both stations", async () => {
    const exp = () => Number(threeSays("fifth").match(new RegExp(`^DEVICE ${yId.slice(0, 12)} \\S+ web own=\\S+ exp=(\\S+)`, "m"))?.[1] ?? NaN);
    const was = exp();
    const r = await qDev.call("lock.renew", { workspace: three, device: yId }).then((o: J) => o, (x: Error) => x);
    log(`  Q's lock.renew: ${r instanceof Error ? r.message.slice(0, 300) : JSON.stringify(r)?.slice(0, 200)}`);
    if (r instanceof Error) throw r;
    await atBoth("Y renewed", (s) => Number(s.match(new RegExp(`^DEVICE ${yId.slice(0, 12)} \\S+ web own=\\S+ exp=(\\S+)`, "m"))?.[1] ?? NaN) > was);
  });
  await check("Y taken off by Q on 设置 › 安全: listed by neither station, refused by both", async () => {
    await qDev.call("lock.removeDevice", { workspace: three, device: yId });
    await atBoth("Y off", (s) => !s.includes(`DEVICE ${yId.slice(0, 12)} `));
    for (const id of both()) log(`  Y sees ${id === fifthId ? "the first" : "the second"}: ${short(await inThree(yDev, id, (s) => s.state !== "online" && s.state !== "connecting"))}`);
  });
  // (the vault keyed anew without P as part of its removal, the box key read then if it must be, as before a move:
  // views/lock.ts `takeOffBound`; 2026-11-14, left waiting for A's next opening, it was shown to no device begun anew)
  await check("P taken off alice's own lock by A: refused by both; A's vault keyed anew without it as part of the removal", async () => {
    const pBase = await baseOf(pDev);
    const held = (await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault && x.keyed), 60_000)).devices as number;
    await vDev.call("lock.removeDevice", { workspace: three, device: pBase });
    await atBoth("P off", (s) => !s.includes(`DEVICE ${pBase.slice(0, 12)} `));
    for (const id of both()) await inThree(pDev, id, (s) => s.state !== "online" && s.state !== "connecting");
    const v = await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault && x.keyed && x.devices < held && !x.waits), 30_000);
    log(`  A's vault as P went: ${JSON.stringify({ keyed: v.keyed, devices: v.devices, waits: v.waits ?? null })}`);
    const copies = vDev.answers.filter((x) => thirdId !== "" && x.station.includes(thirdId) && x.path.includes("copy=1")).length;
    log(`  third first: ${thirdId !== "" && thirdId < fifthId && thirdId < sixthId ? "yes" : "no"}, copies: ${copies}`);
    const asked = await vaultUse(vDev);
    log(`  A used its vault, asked: ${asked.join("; ") || "nothing"}`);
    await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault && x.keyed && x.devices < held), 60_000);
  });
  // (no topic says who took a device out: views/lock.ts `outOf` covers a member taken out, and no page reads it yet. What
  // P holds is read where its host keeps alice's own log, a file of its storage, as the app holds it: hosts/node.ts)
  await check("P, taken off alice's own lock, holds who took it off and when: the removal on the log it keeps, signed by A's key there", async () => {
    const pBase = await baseOf(pDev);
    const file = join(dir, "P", "core", `personal-lock-${Buffer.from(vDev.sub).toString("hex")}`);
    const kept = (): J[] => (existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : []);
    const said = (es: J[]) => {
      const ids = new Map<string, string>();
      for (const e of es) {
        const d = e.kind === "genesis" ? e.body?.device : e.kind === "device" ? e.body : null;
        if (typeof d?.key === "string") ids.set(d.key, d.id);
      }
      const mine = [...ids].find(([, id]) => id === pBase)?.[0];
      const off = es.filter((e) => e.kind === "device.remove" && e.body?.key === mine).at(-1);
      return off === undefined ? null : { by: ids.get(off.sig?.key) ?? off.sig?.key, at: off.at };
    };
    await whenChanged([join(dir, "P", "core")], () => said(kept()), 60_000, () => `P keeps ${kept().length} entries of alice's log, no removal of it`);
    const o = said(kept())!;
    log(`  P holds: taken off by ${o.by === vBase ? "A" : o.by}, at ${new Date(o.at * 1000).toISOString()}`);
    if (o.by !== vBase) throw new Error(`taken off by ${o.by}, not A (${vBase})`);
    if (Math.abs(o.at * 1000 - Date.now()) > 300_000) throw new Error(`at ${o.at}, not now`);
  });
  await check("gina taken out by frank: out of the list at both stations; her app loses the workspace, nothing asked on it", async () => {
    const before = rDev.asked();
    const asked = await asksOf(qDev, () => qDev.call("workspace.removeMember", { account: qDev.sub, workspace: three, member: rDev.sub }));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    await atBoth("gina out", (s) => memberAt(s, rDev.sub) === null);
    // (taking a member out is the account's removal too, so her app loses the workspace as it does before a move: the
    // cloud says she is not in it. Who took a device out and when is told to one whose person is a member still by
    // the account: station/test/lock-told-out.test.ts, client/core-ts/test/lock-admits.test.ts)
    await rDev.until({ topic: "workspaces" }, (v) => ((v ?? []).every((a: J) => !(a.workspaces ?? []).some((w: J) => w.id === three)) ? true : undefined), 60_000);
    if (rDev.asked() !== before) throw new Error(`R asked the person: ${rDev.askedWhat(before).join("; ")}`);
  });
  await check("frank, an owner, turns safe mode off: answered lock_root_only", async () => {
    const r = await qDev.call("lock.disable", { workspace: three }).then(() => null, (x: Error) => x);
    log(`  Q's lock.disable: ${r?.message.slice(0, 300) ?? "done"}`);
    if (r === null || !/lock_root_only/.test(r.message)) throw new Error("not answered lock_root_only");
  });
  await check("A, the root's, turns safe mode off: off at both stations (the chain still moved), S and Q let in; on again: on at both", async () => {
    const off = await asksOf(vDev, () => vDev.call("lock.disable", { workspace: three }));
    log(`  off: A asked ${off.join("; ") || "nothing"}`);
    await atBoth("off", (s) => /^MOVED \S+ off /m.test(s) && /^LOCK off$/m.test(s));
    for (const x of [sDev, qDev]) for (const id of both()) await inThree(x, id, (s) => s.state === "online");
    const on = await asksOf(vDev, () => vDev.call("lock.open", { workspace: three }));
    log(`  on: A asked ${on.join("; ") || "nothing"}`);
    await atBoth("on", (s) => /^MOVED \S+ on /m.test(s) && /^LOCK on /m.test(s));
    for (const x of [vDev, sDev, qDev]) for (const id of both()) await inThree(x, id, (s) => s.state === "online");
  });
  // ── round 21: the cloud frozen (it answers nothing), and the workspace's stations apart. With the second stopped, A takes X,
  // alice's web page, off at the first (`web.remove` in her own log: nothing of the cloud's, as the acts of round 20
  // that change the cloud's lists are not); the second started: both hold one state in force, X off at both; S, hank's
  // app, started anew with its data kept, let in by both with the cloud still frozen ──
  stationDo("cloud-freeze");
  try {
    await xDev.restart();
    await check("the cloud frozen and the second stopped: A takes X off at the first, the first lists it no more", async () => {
      stationDo("second-stop");
      const r = await vDev.call("lock.removeDevice", { workspace: three, device: xBase });
      log(`  A's lock.removeDevice: ${JSON.stringify(r)?.slice(0, 200)}`);
      await whenChanged([fifthData], () => !threeSays("fifth").includes(`DEVICE ${xBase.slice(0, 12)} `), 60_000, () => "the first still lists X");
      log(`  X sees the first: ${short(await inThree(xDev, fifthId, (s) => s.state !== "online" && s.state !== "connecting"))}`);
    });
    await check("the second started, the cloud still frozen: both stations hold one state in force (the same devices, X off)", async () => {
      const t1 = Date.now();
      stationDo("second-again");
      const same = () => {
        const s = [threeSays("fifth"), threeSays("sixth")];
        return s.every((x) => /^MOVED \S+ on /m.test(x)) && devicesIn(s[0]!) === devicesIn(s[1]!) && personsIn3(s[0]!) === personsIn3(s[1]!) && !s[1]!.includes(`DEVICE ${xBase.slice(0, 12)} `) ? s : null;
      };
      await atBoth("one state", () => same() !== null, 30_000);
      log(`  one state at both ${Date.now() - t1} ms after the second was started: ${devicesIn(threeSays("sixth")).split("; ").length} devices`);
      log(`  X sees the second: ${short(await inThree(xDev, sixthId, (s) => s.state !== "online" && s.state !== "connecting"))}`);
    });
    await check("the cloud still frozen: S started anew, its data kept, let in by both stations", async () => {
      await sDev.restart();
      for (const id of both()) await inThree(sDev, id, (s) => s.state === "online");
      await sDev.lock(three, (l) => l.locked && l.me?.confirmed, 60_000);
    });
  } finally {
    stationDo("cloud-thaw");
  }
  // ── round 22: a new app of alice's after one was taken off (P, round 20), as a person's next phone: refused by both, its
  // page says it joins her own log and its refusal names her own trusted devices (no admin: after a move only her apps
  // put it on her log, views/lock.ts `offOwnLock`); it asks from the page that waits, A shows the code; let in by both
  // and given A's vault, which was keyed anew without P as P went, nothing done on A but the approval (2026-11-14: a
  // vault left waiting was shown to no device begun anew, 条目不存在, and setting one up made an empty 个人) ──
  await nDev.signIn();
  await check("N, alice's new app after P went, refused by both; its page says it joins her own log, its refusal names her trusted devices and no admin", async () => {
    for (const id of both()) {
      const s = await inThree(nDev, id, (s) => s.state !== "online" && s.state !== "connecting" && s.cause === "lock");
      log(`  N sees ${id === fifthId ? "the first" : "the second"}: ${short(s)}`);
      if (/管理员|admin/i.test(String(s.message))) throw new Error(`its refusal names an admin: ${s.message}`);
    }
    await nDev.lock(three, (l) => l.me?.waiting && l.me?.ownLock, 60_000);
  });
  await must("N asks from the page that waits, A shows the code: N on alice's own lock, let in by both, nothing asked on N, A asked once", async () => {
    const nFrom = nDev.asked();
    const asked = await asksOf(vDev, async () => {
      const shown = vDev.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
      await nDev.call("lock.pair", { workspace: three });
      const p = await shown;
      await nDev.lock(three, (l) => l.me?.pair?.state === "code", 60_000);
      await nDev.call("lock.pairCode", { workspace: three, code: p.code });
      await nDev.personal((p) => p.standing === "member", 90_000);
    });
    log(`  A asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`A asked ${asked.length} times`);
    if (nDev.asked() !== nFrom) throw new Error(`N asked the person: ${nDev.askedWhat(nFrom).join("; ")}`);
    for (const id of both()) await inThree(nDev, id, (s) => s.state === "online");
  });
  await check("N given A's vault (keyed anew without P as P went) and opens its item, nothing done on A", async () => {
    const v = threeVaults.get(vDev)!;
    const aFrom = vDev.asked();
    // (as its page has it: confirmed and signing once it has read the state in force; meanwhile the vault says it syncs
    // the list, vault_lock_waiting)
    await nDev.lock(three, (l) => l.signs && l.me?.confirmed, 90_000);
    await nDev.until({ topic: "vaults", workspace: three }, (x) => x?.canSign, 90_000);
    await nDev.call("vault.setup", { workspace: three });
    await nDev.until({ topic: "vaults", workspace: three }, (x) => (x?.vaults ?? []).find((y: J) => y.id === v.vault && y.keyed), 90_000);
    const o = await nDev.call("vault.open", { workspace: three, item: v.item });
    if (o?.plain?.fields?.value !== v.secret) throw new Error(`N opened: ${JSON.stringify(o)?.slice(0, 300)}`);
    if (vDev.asked() !== aFrom) throw new Error(`A asked the person: ${vDev.askedWhat(aFrom).join("; ")}`);
  });
  // ── round 23: ivy, carried with no log of her own (set up at round 19's start) ──
  await check("ivy and jade carried, bound to no log at both", async () => {
    await atBoth("ivy carried", (s) => memberAt(s, iDev.sub) === "member" && !personAt(s, iDev.sub));
    await atBoth("jade carried", (s) => memberAt(s, oDev.sub) === "member" && !personAt(s, oDev.sub));
  });
  await kDev.signIn();
  await must("K, ivy's third app, asks from the page that waits; I shows the code: one ask on I, nothing on K nor on A or Q; K in at both, ivy bound to a log of her own", async () => {
    await kDev.lock(three, (l) => l.me?.waiting, 90_000);
    const others = [vDev, qDev, kDev].map((x) => [x, x.asked()] as const);
    let typed = 0;
    const asked = await asksOf(iDev, async () => {
      const shown = iDev.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
      await kDev.call("lock.pair", { workspace: three });
      const p = await shown;
      await kDev.lock(three, (l) => l.me?.pair?.state === "code", 60_000);
      await kDev.call("lock.pairCode", { workspace: three, code: p.code });
      typed = Date.now();
      await kDev.personal((p) => p.standing === "member", 90_000);
    });
    log(`  I asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`I asked ${asked.length} times`);
    for (const [x, n] of others) if (x.asked() !== n) throw new Error(`${x.name} asked the person: ${x.askedWhat(n).join("; ")}`);
    for (const id of both()) await inThree(kDev, id, (s) => s.state === "online");
    log(`  K in at both ${Date.now() - typed} ms after its code was typed`);
    await atBoth("ivy bound", (s) => personAt(s, iDev.sub));
  });
  await check("K given ivy's vault and opens its item, nothing asked on I for it", async () => {
    const iFrom = iDev.asked();
    await kDev.lock(three, (l) => l.signs && l.me?.confirmed, 90_000);
    await kDev.call("vault.setup", { workspace: three });
    await kDev.until({ topic: "vaults", workspace: three }, (x) => (x?.vaults ?? []).find((y: J) => y.id === ivyVault.vault && y.keyed), 90_000);
    const o = await kDev.call("vault.open", { workspace: three, item: ivyVault.item });
    if (o?.plain?.fields?.value !== ivyVault.secret) throw new Error(`K opened: ${JSON.stringify(o)?.slice(0, 300)}`);
    if (iDev.asked() !== iFrom) throw new Error(`I asked the person: ${iDev.askedWhat(iFrom).join("; ")}`);
  });
  await check("W, ivy's web page, approved on I face to face: one ask on I, in at both", async () => {
    await wDev.signIn();
    const asked = await asksOf(iDev, () => approvedInThree(wDev, true, iDev));
    log(`  I asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`I asked ${asked.length} times`);
  });
  await check("J taken off by I as lost: one ask on I, J out at both and refused", async () => {
    const jBase = await baseOf(jDev);
    const asked = await asksOf(iDev, () => iDev.call("lock.removeDevice", { workspace: three, device: jBase }));
    log(`  I asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`I asked ${asked.length} times`);
    await atBoth("J out", (s) => !s.includes(`DEVICE ${jBase.slice(0, 12)} `));
    for (const id of both()) await inThree(jDev, id, (s) => s.state !== "online" && s.state !== "connecting");
  });
  // (frank's, an owner's, as round 20's acts: alice's devices ask the cloud at every change of the list, and by here
  // her account is near the cloud's 120 a minute, account.ts LIMITS: a setRole of A's was refused 429 here, the lead,
  // 2026-11-14; never a wait or a retry to get under it)
  log(`  requests signed as alice: ${requestsOf([vDev, pDev, xDev, nDev])}; as frank: ${requestsOf([qDev, yDev])}`);
  await check("frank (an owner) makes ivy an admin and takes her out, as any member: admin at both, then out at both", async () => {
    await qDev.call("workspace.setRole", { account: qDev.sub, workspace: three, member: iDev.sub, role: "admin" });
    await atBoth("ivy an admin", (s) => memberAt(s, iDev.sub) === "admin");
    await qDev.call("workspace.removeMember", { account: qDev.sub, workspace: three, member: iDev.sub });
    await atBoth("ivy out", (s) => memberAt(s, iDev.sub) === null);
  });
  // (jade, carried bound to no log, who never acted: taken out and added again, the list names no app of hers, so her new
  // app is a newcomer, its own log begun, an owner asked, as test/lock-left-out's in client/core-ts; the lead,
  // 2026-11-14: else nobody could let her in)
  await check("frank takes jade out and adds her again; her new app L, told the list names no app of hers, begins her log and is approved by frank's Q face to face: one ask on Q, nothing on L; in at both, jade bound", async () => {
    await qDev.call("workspace.removeMember", { account: qDev.sub, workspace: three, member: oDev.sub });
    await atBoth("jade out", (s) => memberAt(s, oDev.sub) === null);
    await qDev.call("workspace.addMembers", { account: qDev.sub, workspace: three, role: "member", emails: ["jade@example.test"] });
    // (the stations list her again only once her first device is admitted, views/lock.ts `added`, as hank in round 20)
    await lDev.signIn();
    const lFrom = lDev.asked();
    const asked = await asksOf(qDev, () => approvedInThree(lDev, false, qDev));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`Q asked ${asked.length} times`);
    if (lDev.asked() !== lFrom) throw new Error(`L asked the person: ${lDev.askedWhat(lFrom).join("; ")}`);
    await atBoth("jade bound", (s) => memberAt(s, oDev.sub) === "member" && personAt(s, oDev.sub));
  });
} catch (e) {
  fail("the run", e);
}
log(failures() === 0 ? "ALL PASSED" : `${failures()} FAILED`);
await within(Promise.all([vDev, pDev, xDev, qDev, rDev, sDev, yDev, gDev, tDev, nDev, iDev, jDev, kDev, wDev, mDev, oDev, lDev].map((x) => x.close())), 5000);
process.exit(failures() === 0 ? 0 : 1);
