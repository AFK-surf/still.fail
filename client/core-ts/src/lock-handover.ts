// What this device works out to hand a workspace's chain over to its people's own logs (views/lock.ts `handOver`): who
// may (an owner's own app device, by the signer the chain names it with, its person's own log bound there and pinned
// here), what the chain's list is at its head (the target), and that the state the rules make of the logs held and the
// chain with a `moved` naming that log after it is that list (rules/src/lock/state4.mbt `state4_moved`; the fourth
// round's model, station/test/lock-roster4-model.ts D6 and `m8`). Nothing is said in anyone's log for it: the chain as
// it moved still says what the logs have not (the lead, 2026-11-14), so `moved` alone hands it over. Pure: what is
// signed, kept and brought is the caller's.
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { type Entry, canonical, entryHash } from "./lock.ts";
import { fold, movedRoot } from "./lock-moved.ts";
import { checkChain, crypto } from "./personal-lock.ts";
import { checkLock, signerIn } from "./vault/lock-check.ts";
import { COUNTED_FROM } from "./station/oldest.ts";
import { MOVED_FROM_BUILD } from "../../../station/src/api/moved-from.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);

/// The chain's list as the handover is to keep it: each member (their role, email, the log it binds them to, "" for
/// none), the stations, the settings, the root's person's email, each web page not run out, and each app device of a
/// member's own that signs on the chain (by its id: its person and that signer).
export type Target = {
  members: Map<string, { role: string; email: string; lock: string }>;
  stations: Set<string>;
  settings: { origins: string[]; rp_id: string; cloud_keys: unknown };
  email: string;
  webs: Map<string, { label: string; exp: number }>;
  apps: Map<string, { sub: string; sign_key: string }>;
};
/// What the rules' state rooted in this person's log lists, as compared with a target.
export type AsIf = {
  on: string;
  settings: string | null;
  email: string | null;
  members: Map<string, { role: string; email: string; lock: string }>;
  stations: Set<string>;
  webs: Map<string, number>;
  /// Each member's devices there (id, and an app's signer), for the tests to read.
  devices: Map<string, { sub: string; kind: string; sign_key?: string }>;
};
/// Who hands over: the device by its base key (`base`, its id on the chain) and the key it signs the chain with
/// (`signer`), its person and the genesis of their log pinned here, the key this device signs that log with (`key`).
export type Who = { sub: string; genesis: string; key: string; base: string; signer: string };

export type HandOverPlan =
  /// Not to be handed over by this device (why, the core's words); `differs`: not now, the state as if moved not the
  /// chain's list (a bound member's log not held yet; statements an earlier build's handover said that the chain has
  /// changed from since), which the caller waits out saying nothing (views/lock.ts `heldBack`'s like).
  | { refused: string; differs?: true }
  /// The chain's list at its head (`target`) and the state as if moved (`asIf`), the same: `moved` alone hands it over.
  | { target: Target; asIf: AsIf };

/// From when (unix seconds, by this device's clock) a workspace's chain is handed over by itself (views/lock.ts
/// `handsOver`): the day this was written (2026-11-14), so on every build from this one. Not a date anyone waits for (the
/// user, 2026-11-14: 无感迁移, no date, no switch, nobody told to update): what holds a workspace back is what uses it,
/// each station of its chain saying it serves what a moved chain is made of and each app device it lets in running a
/// build that takes one (`devicesWaited`). It is only
/// where `mayHandOver`'s fourteen days count from for a chain begun before it.
export const HAND_OVER_FROM: number | null = 1794614400;
/// Held for now (2026-11-14): no app hands a chain over by itself. The locks' rounds on real stations, run for the first
/// time on workspaces that had moved (the main branch's side run after #6102), showed what a moved workspace still
/// does wrong: a device approved after the move is let in and never given the vault, a new member's first device is
/// asked once more, a device asking from the page that waits is not let in. A move cannot be undone, so none is made
/// until those are mended; a host made for tests (`handOverByTests`, `handOverAuto`) goes on handing over, so what a
/// moved workspace does stays run. Taken out, by the change that mends the last of them.
export const HAND_OVER_HELD = true;
/// How long the person who turned safe mode on has to hand the chain over before another owner's device does (the
/// owner, 2026-11-14): from `HAND_OVER_FROM` or the genesis, whichever is later.
export const HAND_OVER_FIRST_SECS = 14 * 86400;

/// How long a device no station of the chain has seen is not waited for (the owner was told, 2026-11-14:
/// 「超过 7 天没上线的设备不等」): it uses nothing meanwhile, and as it comes back a station of a moved workspace tells a
/// core too old for it to update (station/src/mesh/serve.ts `movedTooOld`).
export const IDLE_SECS = 7 * 86400;
/// For now, a chain whose members bound to a log are more than this is not handed over: a workspace said in its people's
/// logs is bounded (`LOGS_MOST`, 256 logs a workspace) and one past it is a dead end.
export const HAND_OVER_MEMBERS_MOST = 200;

/// Whether a device that said `build` (its highest, as a station saw it ask: -1, none said) takes a moved workspace: a
/// release's (COUNTED_FROM on) from MOVED_FROM_BUILD on; one under COUNTED_FROM, a development build's or an iOS app's
/// (its TestFlight number, libs/mbui/scripts/ios.sh), cannot be told apart and is taken as able (the tests' devices say
/// such builds; the iOS app updates by TestFlight); none said is not.
export const ableBuild = (build: number): boolean => build >= 0 && (build < COUNTED_FROM || build >= MOVED_FROM_BUILD);

/// What the stations said of the devices' builds (GET /lock `builds`, GET /lock/person), kept beside a lock: each
/// station's `since` by its id, and per device the highest build and the latest `at` any of them said.
export type BuildsSeen = { since: Record<string, number>; devices: Record<string, { build: number; at: number }> };

/// Of the devices `ids`, those a handover (or a write of a kind an older app refuses) waits for, by what the stations
/// `of` said (`seen`): one seen on a build not able (`ableBuild`) within IDLE_SECS of `now`, and one never seen while the
/// latest `since` of those stations is within IDLE_SECS (none said: every one not seen is waited for). One not seen
/// for IDLE_SECS uses nothing, and is not waited for.
export function devicesWaited(ids: Iterable<string>, seen: BuildsSeen, of: readonly string[], now: number): string[] {
  const said = of.flatMap((id) => (typeof seen.since[id] === "number" ? [seen.since[id]!] : []));
  const since = said.length === 0 ? null : Math.max(...said);
  const out: string[] = [];
  for (const id of ids) {
    const d = seen.devices[id];
    if (d !== undefined ? !ableBuild(d.build) && now - d.at < IDLE_SECS : since === null || now - since < IDLE_SECS) out.push(id);
  }
  return out.sort();
}

/// Who turned safe mode on: the person of the device the genesis names with the key that signed it (its body's
/// `owner` where it names none so).
export function genesisPerson(entries: readonly Entry[]): string | null {
  const g = entries[0];
  if (g === undefined || g.kind !== "genesis") return null;
  const b = g.body as J;
  const d = arr(b?.devices).find((x) => typeof x?.sign_key === "string" && x.sign_key === g.sig?.key);
  return typeof d?.sub === "string" ? d.sub : typeof b?.owner === "string" ? b.owner : null;
}

/// Whether `sub`'s device is the one to hand the chain `entries` over by itself (the owner, 2026-11-14): an owner
/// on it, and the person who turned safe mode on (`genesisPerson`) while still an owner there; another owner only
/// once `now` is HAND_OVER_FIRST_SECS past `from` (HAND_OVER_FROM) and the genesis, or at once where that person is no
/// owner on it any more (taken out, or a role below). By the chain as held and this device's clock (unix seconds).
/// Whether this device may (its person's own app device, by the chain's signer, its log pinned) is the plan's.
export function mayHandOver(entries: readonly Entry[], sub: string, from: number, now: number): boolean {
  if (entries.length === 0 || movedRoot(entries) !== null) return false;
  const f = fold(entries);
  if (f.members.get(sub)?.role !== "owner") return false;
  const first = genesisPerson(entries);
  if (first === sub) return true;
  if (first === null || f.members.get(first)?.role !== "owner") return true;
  return now >= Math.max(from, entries[0]!.at) + HAND_OVER_FIRST_SECS;
}

/// The handover's plan for workspace `ws` by `who`, of the chain held (`entries`, its active chain), the person logs
/// held (`chains`, by genesis), the bodies kept and this device's clock (unix seconds). Nothing is said for it (the
/// lead's, 2026-11-14): once a chain moved, what the logs have not said yet of those it named, the chain as it moved
/// still says (rules/src/lock/state4.mbt `state4_moved`, the model's D6), so `moved` alone hands it over and nobody is
/// waited for or asked. What is checked is that the state as if moved, the rules' of the logs held and the chain with
/// that `moved` after it, is the chain's list at its head (`differs`): nobody dropped or added by the move. A bound
/// member's log not held carries nothing of theirs (rules: what it said is not known), so it would differ: the logs
/// the chain binds are read first (views/lock.ts `readBound`).
export function handOverPlan(ws: string, entries: readonly Entry[], who: Who, chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], now: number): HandOverPlan {
  if (entries.length === 0) return { refused: "the workspace has no lock" };
  if (movedRoot(entries) !== null) return { refused: "the chain moved already" };
  let checked: ReturnType<typeof checkLock>;
  try {
    checked = checkLock([...entries], now);
  } catch (e) {
    return { refused: `the chain held does not check: ${(e as Error).message}` };
  }
  if (checked.disabled) return { refused: "the lock is off" };
  const f = fold(entries);
  // Who: an owner's own app device, signing the chain with the signer it names; its person bound to their log, which
  // is pinned here with this device on it.
  const d = checked.devices.get(who.base);
  const by = signerIn(checked, who.signer, now);
  if (d === undefined || d.kind !== "app" || d.sub !== who.sub || d.sign_key !== who.signer || !d.own) return { refused: "this device is not its person's own app device on the chain" };
  if (by === null || by.role !== "owner" || !by.own || by.passkey) return { refused: "only an owner's own device hands the chain over" };
  if (f.persons.get(who.sub) !== who.genesis) return { refused: "the chain does not bind this person to the log pinned here" };
  const log = chains.get(who.genesis);
  const mine = log === undefined ? null : checkChain(log, who.sub);
  if (log === undefined || mine === null || !mine.devices.has(who.key)) return { refused: "this device is not on its person's own log" };
  // The target: the chain's list at its head, everyone (bound or not), each web page not run out, each own app device
  // that signs (one not its person's own is left behind, the lead, 2026-11-13).
  const members = new Map<string, { role: string; email: string; lock: string }>();
  for (const [sub, m] of f.members) members.set(sub, { role: m.role, email: m.email, lock: f.persons.get(sub) ?? "" });
  const webs = new Map<string, { label: string; exp: number }>();
  const apps = new Map<string, { sub: string; sign_key: string }>();
  for (const [id, x] of checked.devices) {
    if (x.kind === "web" && typeof x.exp === "number" && x.exp > now) webs.set(id, { label: String(f.devices.get(id)?.label ?? ""), exp: x.exp });
    if (x.kind !== "app" || typeof x.sign_key !== "string" || !x.own) continue;
    const s = signerIn(checked, x.sign_key, now);
    if (s !== null && s.own && !s.passkey && s.sub === x.sub) apps.set(id, { sub: x.sub, sign_key: x.sign_key });
  }
  const target: Target = {
    members, stations: new Set(f.stations.keys()), webs, apps,
    settings: { origins: checked.origins, rp_id: checked.rp_id, cloud_keys: checked.cloudKeys },
    email: f.members.get(who.sub)?.email ?? "",
  };
  const asIf = asIfOf(ws, who, entries, chains, bodies, now);
  const off = differs(target, asIf, who.sub);
  if (off !== null) return { refused: `moved, the list would not be the chain's: ${off}`, differs: true };
  return { target, asIf };
}

/// Whether a state as if moved names app device `id` as the target does: its person's, by that signer.
const hasApp = (s: AsIf, id: string, a: { sub: string; sign_key: string }): boolean => {
  const d = s.devices.get(id);
  return d !== undefined && d.kind === "app" && d.sub === a.sub && d.sign_key === a.sign_key;
};

/// What differs between the target and a state as if moved (null: nothing): the members bound to a log of their own,
/// each one's role, email and log; the stations; the settings; this person's web pages; the app devices that sign.
export function differs(t: Target, s: AsIf, sub: string): string | null {
  if (s.on !== "on") return `state ${s.on}`;
  if (s.settings !== canonical(t.settings)) return "settings";
  if (s.email !== t.email) return `email ${sub}`;
  for (const k of new Set([...t.members.keys(), ...s.members.keys()])) {
    if (k === sub) continue;
    const a = t.members.get(k), b = s.members.get(k);
    if (a === undefined || b === undefined) return `member ${k}`;
    if (a.role !== b.role) return `role ${k}`;
    if (a.email !== b.email) return `email ${k}`;
    if (a.lock !== b.lock) return `log ${k}`;
  }
  if (s.members.get(sub)?.role !== "owner") return `role ${sub}`;
  if ([...t.stations].sort().join() !== [...s.stations].sort().join()) return "stations";
  for (const [id, w] of t.webs) if ((s.webs.get(id) ?? 0) < w.exp) return `web ${id}`;
  for (const [id, a] of t.apps) if (!hasApp(s, id, a)) return `device ${id}`;
  return null;
}

/// The state as if moved: the rules' of the logs and bodies given and the chain `entries` with `moved {root}` after it
/// (made here, its signature taken as `who`'s chain signer's by this crypto alone: nothing signed).
function asIfOf(ws: string, who: Who, entries: readonly Entry[], chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], now: number): AsIf {
  const last = entries[entries.length - 1]!;
  const e = { v: 1 as const, ws, seq: last.seq + 1, prev: entryHash(last), at: Math.max(last.at, now), kind: "moved", body: { root: who.genesis } };
  const h = entryHash(e as Entry);
  const moved = { ...e, sig: { key: who.signer, alg: "Ed25519", sig: "" } };
  const c = { ...crypto, sigValid: (sig: J, hash: string, ...rest: J[]) => (hash === h && sig?.key === who.signer) || (crypto.sigValid as J)(sig, hash, ...rest) };
  const out = rules.state4_moved_js(ws, [...entries, moved], [...chains.values()], bodies, now, c) as J;
  const none: AsIf = { on: "error" in out ? "refused" : String(out.on), settings: null, email: null, members: new Map(), stations: new Set(), webs: new Map(), devices: new Map() };
  if ("error" in out || (out.on !== "on" && out.on !== "off")) return none;
  const s = out.state as J;
  const persons = new Map<string, string>(arr(s.persons).map(([sub, g]) => [String(sub), String(g)]));
  const members = new Map<string, { role: string; email: string; lock: string }>();
  for (const [sub, m] of arr(s.members)) members.set(String(sub), { role: String(m?.role ?? ""), email: String(m?.email ?? ""), lock: persons.get(String(sub)) ?? "" });
  const devices = new Map<string, { sub: string; kind: string; sign_key?: string }>();
  const webs = new Map<string, number>();
  for (const [id, d] of arr(s.devices)) {
    devices.set(String(id), { sub: String(d.sub), kind: String(d.kind), ...(typeof d.sign_key === "string" ? { sign_key: d.sign_key } : {}) });
    if (d.kind === "web" && typeof d.exp === "number") webs.set(String(id), d.exp);
  }
  return {
    on: String(out.on), settings: canonical({ origins: arr(s.origins), rp_id: String(s.rp_id ?? ""), cloud_keys: s.cloud_keys ?? null }),
    email: members.get(who.sub)?.email ?? null, members, stations: new Set(arr(s.stations).map(([key]) => String(key))), webs, devices,
  };
}
