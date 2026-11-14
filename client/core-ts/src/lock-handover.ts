// What this device says to hand a workspace's chain over to its people's own logs (views/lock.ts `handOver`): who may
// (an owner's own app device, by the signer the chain names it with, its person's own log bound there and pinned
// here), what the chain's list is at its head (the target), and what this person's log is still to say so that the
// state the rules make with that log as the root is that list (rules/src/lock/state4.mbt; the fourth round's model,
// station/test/lock-roster4-model.ts `m7`). Worked out against "as if moved": the state of the logs and bodies held
// plus what would be said, nothing signed, so a handover begun before says nothing twice. Pure: what is signed, kept
// and brought is the caller's.
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { type Entry, canonical, entryHash } from "./lock.ts";
import { fold, movedRoot } from "./lock-moved.ts";
import { type Body, type Said, bodiesOf, byHash, commitOf } from "./lock-statements.ts";
import { checkChain, crypto, personOf } from "./personal-lock.ts";
import { checkLock, signerIn } from "./vault/lock-check.ts";
import { COUNTED_FROM } from "./station/oldest.ts";
import { MOVED_FROM_BUILD } from "../../../station/src/api/moved-from.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);

/// The chain's list as the handover is to keep it: each member bound to a log of their own (their role, email, log),
/// the stations, the settings, the root's person's email, this person's web pages on the chain not run out, and each
/// app device of a member bound to a log that signs on the chain (by its id: its person and that signer), but the one
/// handing over, whose signer the same ask says (`#restate`).
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
/// A web page of this person's said on their log (`web {id, label, exp}`, personal-lock.ts `web`).
export type Web = { id: string; label: string; exp: number };

/// Who hands over: the device by its base key (`base`, its id on the chain) and the key it signs the chain with
/// (`signer`), its person and the genesis of their log pinned here, the key this device signs that log with (`key`).
export type Who = { sub: string; genesis: string; key: string; base: string; signer: string };

export type HandOverPlan =
  /// Not to be handed over by this device (why, the core's words).
  | { refused: string }
  /// Members the chain names with a device that signs and no log of their own bound: theirs take their own lock by
  /// themselves (views/lock.ts `ownLockFor`); the handover waits for them. So too a member bound to a log with an app
  /// device that signs on the chain and is not on that log as held here (or whose log is not held): the state as if
  /// moved names a member's devices by their log alone, so it would be out after the move: those devices (`devices`,
  /// by their id on the chain), which the owner's page names (views/lock.ts `upgradeOf`).
  | { waits: string[]; devices?: { sub: string; id: string }[] }
  /// What is still to be said (`says`, in order; `webs`), whom the chain names that is not said (no log of their own,
  /// no device that signs: `unsaid`, with the chain's role), the target, and the state as if moved once it is said.
  | { says: Said[]; webs: Web[]; unsaid: { sub: string; role: string; email: string }[]; target: Target; asIf: AsIf };

/// From when (unix seconds, by this device's clock) a workspace's chain is handed over by itself (views/lock.ts
/// `handsOver`): the day this was written (2026-11-14), so on every build from this one. Not a date anyone waits for (the
/// user, 2026-11-14: 无感迁移, no date, no switch, nobody told to update): what holds a workspace back is what uses it,
/// each station of its chain saying it serves what a moved chain is made of and each app device it lets in running a
/// build that takes one (`devicesWaited`), the writer's own log the same (views/lock.ts `mayWriteNew`). It is only
/// where `mayHandOver`'s fourteen days count from for a chain begun before it.
export const HAND_OVER_FROM: number | null = 1794614400;
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
/// For now, nor one whose root's log would pass this many entries with the handover's statements (`CHAIN_MOST`, 1024).
export const HAND_OVER_LOG_MOST = 512;

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
  const since = Math.max(-Infinity, ...of.flatMap((id) => (typeof seen.since[id] === "number" ? [seen.since[id]!] : [])));
  const out: string[] = [];
  for (const id of ids) {
    const d = seen.devices[id];
    if (d !== undefined ? !ableBuild(d.build) && now - d.at < IDLE_SECS : !(now - since >= IDLE_SECS)) out.push(id);
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
/// held (`chains`, by genesis; this person's own as it stands with what is pending after it), the bodies kept and this
/// device's clock (unix seconds).
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
  // The target: the chain's list at its head.
  const members = new Map<string, { role: string; email: string; lock: string }>();
  const waits: string[] = [];
  const unsaid: { sub: string; role: string; email: string }[] = [];
  for (const [sub, m] of f.members) {
    if (sub === who.sub) continue;
    const lock = f.persons.get(sub);
    if (lock !== undefined) members.set(sub, { role: m.role, email: m.email, lock });
    else if (checked.signed.has(sub)) waits.push(sub);
    else unsaid.push({ sub, role: m.role, email: m.email });
  }
  if (waits.length > 0) return { waits: waits.sort() };
  const webs = new Map<string, { label: string; exp: number }>();
  for (const [id, x] of checked.devices) {
    if (x.kind !== "web" || x.sub !== who.sub || typeof x.exp !== "number" || x.exp <= now) continue;
    webs.set(id, { label: String(f.devices.get(id)?.label ?? ""), exp: x.exp });
  }
  // Each app device of a member bound to a log that signs on the chain (`own`, not run out, a signer): to be in the state
  // as if moved by that signer, else its member waits (below). The one handing over is said in the ask itself.
  const apps = new Map<string, { sub: string; sign_key: string }>();
  for (const [id, x] of checked.devices) {
    if (id === who.base || x.kind !== "app" || typeof x.sign_key !== "string" || !f.persons.has(x.sub)) continue;
    const s = signerIn(checked, x.sign_key, now);
    if (s !== null && s.own && !s.passkey && s.sub === x.sub) apps.set(id, { sub: x.sub, sign_key: x.sign_key });
  }
  const target: Target = {
    members, stations: new Set(f.stations.keys()), webs, apps,
    settings: { origins: checked.origins, rp_id: checked.rp_id, cloud_keys: checked.cloudKeys },
    email: f.members.get(who.sub)?.email ?? "",
  };
  // What the state as if moved lacks of it.
  const before = asIfOf(ws, who, chains, bodies, now, crypto);
  const says: Said[] = [];
  const settings = canonical(target.settings);
  if (before.on !== "on" || before.settings !== settings || before.email !== target.email) says.push({ kind: "open", ...target.settings, email: target.email });
  const admits: Said[] = [];
  for (const [sub, m] of before.members) {
    if (sub === who.sub) continue;
    const t = members.get(sub);
    if (t !== undefined && t.role === m.role && t.email === m.email && t.lock === m.lock) continue;
    says.push({ kind: "member.remove", sub });
  }
  for (const [sub, t] of members) {
    const m = before.members.get(sub);
    if (m === undefined || m.role !== t.role || m.email !== t.email || m.lock !== t.lock) admits.push({ kind: "member", sub, email: t.email, lock: t.lock, role: t.role });
  }
  says.push(...admits);
  for (const key of before.stations) if (!target.stations.has(key)) says.push({ kind: "station.remove", key });
  for (const key of target.stations) if (!before.stations.has(key)) says.push({ kind: "station", key });
  const toWeb: Web[] = [];
  for (const [id, w] of webs) if ((before.webs.get(id) ?? 0) < w.exp) toWeb.push({ id, label: w.label, exp: w.exp });
  // And what it would be once said: the target, or this device cannot hand it over.
  const asIf = says.length === 0 && toWeb.length === 0 ? before : afterSaying(ws, who, chains, bodies, says, toWeb, now);
  const lacking = [...apps].filter(([id, a]) => !hasApp(asIf, id, a)).map(([id, a]) => ({ sub: a.sub, id }));
  if (lacking.length > 0) return { waits: [...new Set(lacking.map((x) => x.sub))].sort(), devices: lacking };
  const off = differs(target, asIf, who.sub);
  if (off !== null) return { refused: `said, the list would not be the chain's: ${off}` };
  return { says, webs: toWeb, unsaid, target, asIf };
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

/// The state the rules make with `who`'s log as the root (`asIf`), the logs and bodies given, by `c`.
function asIfOf(ws: string, who: Who, chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], now: number, c: typeof crypto): AsIf {
  const out = rules.state4_js(ws, who.genesis, [...chains.values()], bodies, now, c) as J;
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
    if (d.kind === "web" && d.sub === who.sub && typeof d.exp === "number") webs.set(String(id), d.exp);
  }
  return {
    on: String(out.on), settings: canonical({ origins: arr(s.origins), rp_id: String(s.rp_id ?? ""), cloud_keys: s.cloud_keys ?? null }),
    email: members.get(who.sub)?.email ?? null, members, stations: new Set(arr(s.stations).map(([key]) => String(key))), webs, devices,
  };
}

/// The state as if moved once `says` and `webs` are said on `who`'s log, each entry made here, its signature taken as
/// this device's key's by this crypto alone (as lock-statements.ts `plan` works one out): nothing signed.
function afterSaying(ws: string, who: Who, chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], says: readonly Said[], webs: readonly Web[], now: number): AsIf {
  const log = [...(chains.get(who.genesis) ?? [])];
  const made = new Set<string>();
  const put = (kind: string, body: unknown) => {
    const last = log[log.length - 1]!;
    const e = { v: 1 as const, ws: personOf(who.sub), seq: log.length, prev: entryHash(last), at: Math.max(last.at, now), kind, body };
    made.add(entryHash(e));
    log.push({ ...e, sig: { key: who.key, alg: "Ed25519", sig: "" } });
  };
  for (const w of webs) put("web", { id: w.id, label: w.label, exp: w.exp });
  let n = 0;
  const salt = () => (n++).toString(16).padStart(32, "0");
  const newBodies: Body[] = bodiesOf(ws, says, log, byHash(bodies), salt);
  for (const b of newBodies) put("ws", commitOf(ws, who.genesis, b));
  const c = { ...crypto, sigValid: (sig: J, hash: string) => (made.has(hash) && sig?.key === who.key) || crypto.sigValid(sig, hash) };
  const all = new Map(chains);
  all.set(who.genesis, log);
  return asIfOf(ws, who, all, [...bodies, ...newBodies], now, c);
}

/// The state as if moved of what is held now (the tests read it: what the rules would make once the `moved` is on).
export const asIfNow = (ws: string, who: Who, chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], now: number): AsIf => asIfOf(ws, who, chains, bodies, now, crypto);
