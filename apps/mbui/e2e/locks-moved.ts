// The locks of a workspace whose chain moved to its people's own logs, end to end against the local still.fail
// (scripts/e2e-local.sh locks-moved, after up; locks-moved-all, the side run's): a run of its own beside e2e/locks.ts,
// a fresh cloud and stations, so that the earlier rounds' devices and history (and their share of an account's
// requests a minute, account.ts) are not in it. Its devices are e2e/device.ts's, as locks.ts's. The dev cloud's "Dev"
// workspace, its test station (the first) and a second taken into its lock by its code:
//   19 alice, its owner, with two apps (A, P) and a web page (X); frank an admin and gina a member, each with an app
//     approved face to face and bound to a lock of their own; a vault of alice's and one of gina's. A hands the chain
//     over (`lock.handOver`, offered by this driver's host only, device.ts): asked once; both stations hold it moved
//     and on with the chain's list (lock-state: `MOVED <root> <on>`); every device started anew let in by both, nobody
//     else asked; the vaults used with the asks of before.
//   20 the acts of the moved workspace, each a statement in its actor's own log: frank made an owner by A; hank's
//     first app (S) approved by frank's Q with the role frank gave; frank's web page (Y) approved by his own app,
//     renewed, taken off; a station added by frank by its code and taken out; P off alice's own lock, her vault
//     waiting then keyed anew; gina taken out by frank; frank answered `lock_root_only`; off and on again by A. X is
//     closed meanwhile (one account's requests a minute, the cloud's 120).
//   21 the cloud frozen and the stations apart: X off at the first, one state at both once the second is back; S
//     started anew let in by both.
// Each check says PASS or FAIL; it goes on after a failure where it can, and exits 1 if any failed. E2E_SF_SRC,
// E2E_ORIGIN, E2E_PEER_DATA as peer.ts; E2E_WORK, E2E_STATION as e2e-local.sh's.
import { readFileSync, writeFileSync } from "node:fs";
import { check, Device, dir, fail, failures, type J, log, must, stationDo, stationSays, whenChanged, within } from "./device.ts";

const short = (s: J) => JSON.stringify({ state: s.state, cause: s.cause, message: s.message });

// alice's two apps and her web page; frank, an admin, and gina, a member, an app each
const vDev = new Device("A");
const pDev = new Device("P");
const xDev = new Device("X", "alice", { page: true });
const qDev = new Device("Q", "frank");
const rDev = new Device("R", "gina");
// hank, a member after the move (his first app); frank's web page
const sDev = new Device("S", "hank");
const yDev = new Device("Y", "frank", { page: true });
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
  /// `x` approved into the workspace's lock from its waiting page, the code shown on `approver` (as locks.ts's `approvedBy`).
  const approvedInThree = async (x: Device, page = false, approver: Device = vDev) => {
    await x.lock(three, (l) => l.me?.waiting && !l.me?.ownLock, 90_000);
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await x.call("lock.pair", { workspace: three });
    const p = await shown;
    await x.lock(three, (l) => l.me?.pair?.state === "code", 60_000);
    await x.call("lock.pairCode", { workspace: three, code: p.code });
    await x.lock(three, (l) => (page || l.signs) && l.me?.confirmed, 90_000);
    for (const id of both()) await inThree(x, id, (s) => s.state === "online");
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
  await must("P, alice's second app, joins her own lock face to face with A", async () => {
    await pDev.signIn();
    await joinVia(vDev, pDev);
  });
  await check("P, on alice's own lock, let in by both of the workspace's stations, signing", async () => {
    for (const id of both()) await inThree(pDev, id, (s) => s.state === "online");
    await pDev.lock(three, (l) => l.signs && l.me?.confirmed, 60_000);
  });
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
    await pDev.call("vault.setup", { workspace: three });
    await pDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((y: J) => y.id === threeVaults.get(vDev)!.vault && y.keyed), 90_000);
  });
  const threeDevices = [vDev, pDev, xDev, qDev, rDev];
  const askedAt = new Map(threeDevices.map((x) => [x, x.asked()]));
  const rootOf = (said: string) => said.match(/^MOVED (\S+) (\S+)/m);
  const devicesIn = (s: string) => s.split("\n").filter((x) => x.startsWith("DEVICE ")).map((x) => x.split(" ").slice(1, 4).join(" ")).sort().join("; ");
  const personsIn3 = (s: string) => s.split("\n").filter((x) => x.startsWith("PERSON ")).sort().join("; ");
  // (the list as the chain has it at the first, before the move: what the state in force is held to after it)
  const onChain = threeSays("fifth");
  await must("A hands the workspace's chain over to its people's own logs: answered done, A asked once", async () => {
    const t1 = Date.now();
    const r = await vDev.call("lock.handOver", { workspace: three });
    log(`  lock.handOver answered ${JSON.stringify(r)?.slice(0, 200)} after ${Date.now() - t1} ms`);
    if (r !== null) throw new Error(`not handed over: ${JSON.stringify(r)?.slice(0, 300)}`);
    const asked = vDev.askedWhat(askedAt.get(vDev));
    log(`  A asked: ${asked.join("; ")}`);
    if (asked.length !== 1) throw new Error(`A asked ${asked.length} times`);
  });
  await check("both stations hold the workspace's chain moved to alice's own log and on, the list as the chain had it: two stations, three persons, the same devices", async () => {
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
      if (devicesIn(s) !== devicesIn(onChain)) throw new Error(`devices on the chain ${devicesIn(onChain)}; moved ${devicesIn(s)}`);
    }
    log(`  ${devicesIn(onChain).split("; ").length} devices, as on the chain: ${devicesIn(onChain).split("; ").map((x) => x.split(" ").slice(1).join(" ")).join(", ")}`);
  });
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
  // ── round 20: the acts of a moved workspace, each end to end on the workspace after round 19's move (views/lock.ts: each a
  // statement in the actor's own log, `sayMoved`, which asks its person each time; client/core-ts/AGENTS.md, A lock
  // held here). A newcomer's first app approved face to face (`member` said by A, one ask) with the role A gave as it
  // added them; frank made an owner; frank's web page approved by his own app, renewed, taken off; a station added by
  // its code and taken out; P taken off alice's own lock, her vault waiting and keyed anew as A next opens it; gina
  // taken out, refused by both, her page's topic as it stands; off and on again by A (alice's, the root), frank, an
  // owner now, answered `lock_root_only` ──
  const memberAt = (said: string, who: string) => said.match(new RegExp(`^MEMBER ${who} (\\S+)`, "m"))?.[1] ?? null;
  const atBoth = (what: string, ok: (said: string) => boolean, ms = 60_000) =>
    whenChanged([fifthData, sixthData], () => [threeSays("fifth"), threeSays("sixth")].every(ok), ms, () => `${what}: fifth ${threeSays("fifth").split("\n").filter((x) => !x.startsWith("DEVICE")).join("; ")}`);
  /// What `x`'s sealer was asked while `act` ran, a line each.
  const asksOf = async (x: Device, act: () => Promise<unknown>): Promise<string[]> => {
    const from = x.asked();
    await act();
    return x.askedWhat(from).map((l) => l.split(" ").slice(1).join(" "));
  };
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
  await check("hank, added by frank (an owner) as a member after the move: his first app S approved by frank's app Q face to face, one ask on Q, a member at both stations, let in by both", async () => {
    await qDev.call("workspace.addMembers", { account: qDev.sub, workspace: three, role: "member", emails: ["hank@example.test"] });
    await sDev.signIn();
    const asked = await asksOf(qDev, () => approvedInThree(sDev, false, qDev));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    if (asked.length !== 1) throw new Error(`Q asked ${asked.length} times`);
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
  await check("a station enrolled by frank after the move, taken into its list by its code on Q: three at both, it holds the list moved and on; taken out: two again", async () => {
    const made = await qDev.call("workspace.enroll", { account: qDev.sub, workspace: three, name: "third" });
    const at = `${dir}/enroll-third.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at, "third");
    const said = readFileSync(`${process.env.E2E_WORK}/run/third-enroll.log`, "utf8");
    const code = said.match(/(?:code|安全码为)\s*([0-9A-Z-]{4,})/i)?.[1];
    if (!code) throw new Error(`no code in: ${said}`);
    const id = (await qDev.until({ topic: "workspace", workspace: three }, (v) => (v?.stations ?? []).find((s: J) => s.id !== fifthId && s.id !== sixthId), 60_000)).id as string;
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
  await check("P taken off alice's own lock by A: refused by both; A's vault waits, keyed anew as A next opens it", async () => {
    const pBase = await baseOf(pDev);
    const held = (await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault && x.keyed), 60_000)).devices as number;
    await vDev.call("lock.removeDevice", { workspace: three, device: pBase });
    await atBoth("P off", (s) => !s.includes(`DEVICE ${pBase.slice(0, 12)} `));
    for (const id of both()) await inThree(pDev, id, (s) => s.state !== "online" && s.state !== "connecting");
    const v = await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault), 30_000);
    log(`  A's vault as P went: ${JSON.stringify({ keyed: v.keyed, devices: v.devices, waiting: v.waiting ?? null })}`);
    const asked = await vaultUse(vDev);
    log(`  A used its vault, asked: ${asked.join("; ") || "nothing"}`);
    await vDev.until({ topic: "vaults", workspace: three }, (v) => (v?.vaults ?? []).find((x: J) => x.id === threeVaults.get(vDev)!.vault && x.keyed && x.devices < held), 60_000);
  });
  await check("gina taken out by frank: out of the list at both, R refused by both; what R's lock topic says", async () => {
    const asked = await asksOf(qDev, () => qDev.call("workspace.removeMember", { account: qDev.sub, workspace: three, member: rDev.sub }));
    log(`  Q asked: ${asked.join("; ") || "nothing"}`);
    await atBoth("gina out", (s) => memberAt(s, rDev.sub) === null);
    // (gina is no member of the workspace at the cloud either now: her app's view of it is gone, `workspace_not_found`,
    // and it reaches neither station)
    const gone = await rDev.until({ topic: "stations", scope: three }, (v) => (v?.code === "workspace_not_found" ? v : undefined), 60_000);
    log(`  R's stations: ${gone.code}`);
    const l = await rDev.until({ topic: "lock", workspace: three }, (v) => v, 30_000).catch((x: Error) => ({ error: x.message.slice(0, 200) }));
    log(`  R's lock topic: ${JSON.stringify({ locked: l?.locked, me: l?.me, error: l?.error })?.slice(0, 500)}`);
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
} catch (e) {
  fail("the run", e);
}
log(failures() === 0 ? "ALL PASSED" : `${failures()} FAILED`);
await within(Promise.all([vDev, pDev, xDev, qDev, rDev, sDev, yDev].map((x) => x.close())), 5000);
process.exit(failures() === 0 ? 0 : 1);
