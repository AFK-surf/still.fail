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
} catch (e) {
  fail("the run", e);
}
log(failures() === 0 ? "ALL PASSED" : `${failures()} FAILED`);
await within(Promise.all([vDev, pDev, xDev, qDev, rDev].map((x) => x.close())), 5000);
process.exit(failures() === 0 ? 0 : 1);
