// What a workspace's lock says is in force, as this device reads it: its chain folded (`fold`), or, once the chain
// held holds `moved {root}`, the rules' state of its people's own logs and the statements' bodies this device keeps
// (rules/src/lock/state4.mbt, station/test/lock-roster4-model.ts D4, its defaults), by this device's clock, as a
// station's `Cloud.locked` gives it (station/src/cloud/state.ts). Pure: what is kept, read and told is the caller's
// (views/lock.ts).
//
// Where the station is stricter than the model it is so here too: a state the model calls "not on" (no `open` or
// `off` in force here yet) or "no root" (the root's log not kept here) is `waiting`, naming nobody and nothing, never
// the folded chain's list.
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { type Entry, canonical } from "./lock.ts";
import { crypto } from "./personal-lock.ts";
import { type Checked, checkedOf } from "./vault/lock-check.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);

/// What is folded from the entries, unchecked (the stations check them): who and what is in the lock. Read only: one
/// made of a moved chain is kept and given to every reader (views/lock.ts `inForceOf`).
export type Folded = { readonly members: ReadonlyMap<string, { email: string; role: string }>; readonly devices: ReadonlyMap<string, J>; readonly stations: ReadonlyMap<string, string>; readonly disabled: boolean; readonly added: ReadonlyMap<string, number>; readonly persons: ReadonlyMap<string, string> };
/// One being made.
type Making = { members: Map<string, { email: string; role: string }>; devices: Map<string, J>; stations: Map<string, string>; disabled: boolean; added: Map<string, number>; persons: Map<string, string> };

const none = (): Making => ({ members: new Map(), devices: new Map(), stations: new Map(), disabled: false, added: new Map(), persons: new Map() });

export function fold(entries: readonly Entry[]): Folded {
  const f = none();
  for (const e of entries) {
    const b = (e.body ?? {}) as J;
    switch (e.kind) {
      case "genesis":
        for (const m of arr(b.members)) f.members.set(m.sub, { email: m.email, role: m.role });
        for (const d of arr(b.devices)) f.devices.set(d.id, d);
        for (const s of arr(b.stations)) f.stations.set(s.key, s.name);
        break;
      case "member":
        f.members.set(b.sub, { email: b.email, role: b.role });
        break;
      case "member.remove":
        f.members.delete(b.sub);
        for (const [k, d] of f.devices) if (d.sub === b.sub) f.devices.delete(k);
        f.persons.delete(b.sub);
        break;
      case "person":
        f.persons.set(b.sub, b.person);
        break;
      case "device":
        if (!f.devices.has(b.id)) f.added.set(b.id, e.at);
        f.devices.set(b.id, b);
        break;
      case "device.remove":
        f.devices.delete(b.id);
        break;
      case "station":
        f.stations.set(b.key, b.name);
        break;
      case "station.remove":
        f.stations.delete(b.key);
        break;
      case "disable":
        f.disabled = true;
        break;
    }
  }
  return f;
}

/// The root a chain moved to (the genesis hash of the person log its state is said in from then on), or null: the
/// chain's own `disable` turns it off before anything moved says otherwise, as a station reads it (`Cloud.forceChanged`).
export function movedRoot(entries: readonly Entry[]): string | null {
  let root: string | null = null;
  for (const e of entries) {
    if (e.kind === "disable") return null;
    if (e.kind === "moved" && typeof (e.body as J)?.root === "string") root = (e.body as J).root;
  }
  return root;
}

/// The longest body taken, in its canonical form (station/src/cloud/lock-bodies.ts BODY_MOST).
export const BODY_MOST = 16 * 1024;
/// How far up its log a commitment is walked to its genesis (station/src/mesh/person-chains.ts CHAIN_MOST).
export const CHAIN_MOST = 1024;

/// A statement's body's hash (what its commitment carries as `h`); null where it has none.
export function bodyHash(body: unknown): string | null {
  const h: string = rules.body_hash_js(body, crypto);
  return h.startsWith("!") ? null : h;
}

/// Workspace `ws`'s tag in the person log of genesis hash `genesis` (what its commitments there carry as `t`).
export const wsTag = (ws: string, genesis: string): string => rules.ws_tag_js(ws, genesis, crypto);

/// Every `ws` entry kept of a log in `logs` (by genesis hash, everything kept of it, its chain and what is aside) that
/// commits to body hash `h`, each with its log from the genesis to it.
function commitsTo(h: string, logs: Iterable<readonly [string, readonly Entry[]]>, hashOf: (e: Entry) => string): { genesis: string; chain: Entry[] }[] {
  const out: { genesis: string; chain: Entry[] }[] = [];
  for (const [genesis, all] of logs) {
    let by: Map<string, Entry> | null = null;
    for (const e of all) {
      if (e.kind !== "ws" || (e.body as J)?.h !== h) continue;
      by ??= new Map(all.map((x) => [hashOf(x), x]));
      const chain: Entry[] = [];
      for (let at: Entry | undefined = e; at !== undefined && chain.length <= CHAIN_MOST; at = at.prev === null ? undefined : by.get(at.prev)) chain.unshift(at);
      if (chain.length > 0 && chain[0]!.prev === null) out.push({ genesis, chain });
    }
  }
  return out;
}

/// Why a keeper of workspace `ws` does not take `body`, or null, with the body's hash where it has one: taken only where
/// an entry kept commits to it under the workspace's tag and its shape is a statement's (rules/src/lock/body.mbt
/// `body_refusal`), BODY_MOST at most. The station's `LockBodies.take` is the same rule (its file reads and writes the
/// station's disk, so it is mirrored here, not shared).
export function bodyRefused(ws: string, body: unknown, logs: Iterable<readonly [string, readonly Entry[]]>, hashOf: (e: Entry) => string): { hash: string | null; why: string | null } {
  let text: string;
  try {
    text = canonical(body);
  } catch {
    return { hash: null, why: "a body is {ws, kind, …, salt}" };
  }
  if (text.length > BODY_MOST) return { hash: null, why: "a body this long is no statement" };
  const h = bodyHash(body);
  if (h === null) return { hash: null, why: "a body is {ws, kind, …, salt}" };
  const why: string | null = rules.body_refusal_js(ws, body, commitsTo(h, logs, hashOf), crypto);
  return { hash: h, why };
}

/// The statements of `ws` on the active chain of a log in `chains` whose body is not in `kept`, by the body's hash.
export function lackingOf(ws: string, chains: Iterable<readonly [string, readonly Entry[]]>, kept: (h: string) => boolean): string[] {
  const out = new Set<string>();
  for (const [g, es] of chains) {
    const t = wsTag(ws, g);
    for (const e of es) {
      const b = e.body as J;
      if (e.kind === "ws" && b?.t === t && typeof b.h === "string" && !kept(b.h)) out.add(b.h);
    }
  }
  return [...out];
}

/// What is in force: `chain`, the chain held folded (it moved nowhere, or its own `disable` turned it off); `on` or
/// `off`, the rules' state of the people's logs (`off`: `disabled`, the list as it stands); `waiting`, moved but not
/// said here yet (no `open` or `off` in force, the root's log not kept): nobody and nothing. `settings`: the root's
/// newest `open`'s, where moved and said.
export type Settings = { origins: string[]; rp_id: string; cloud_keys: unknown };
/// `checked`, where moved: the same state as the rules give it for the vaults (vault/lock-check.ts `checkedOf`), as a
/// station's vaults go by it (station/src/cloud/state.ts `Cloud.locked`); `waiting`'s names nobody, as a station's
/// does then.
export type InForce = { said: "chain" | "on" | "off" | "waiting"; root: string | null; f: Folded; settings?: Settings; checked?: Checked };

/// How far ahead of this device's clock a web device's `at` may be and still count (rules/src/lock/state4.mbt
/// `web_skew_secs`, station/src/cloud/state.ts WEB_SKEW).
export const WEB_SKEW = 600;

/// From when until when (unix seconds, `[from, until)`) the state made at `now` of `chains` stands by the clock alone:
/// between the nearest web device's `at - WEB_SKEW` or `exp` passed and the nearest to come, as a station's `forceOf`
/// bounds it. Nothing else the rules' state reads depends on the clock.
export function goodFor(chains: Iterable<readonly Entry[]>, now: number): { from: number; until: number } {
  let from = -Infinity, until = Infinity;
  for (const es of chains) {
    for (const e of es) {
      if (e.kind !== "web") continue;
      for (const x of [e.at - WEB_SKEW, Number((e.body as J)?.exp)]) {
        if (!Number.isFinite(x)) continue;
        if (x <= now) from = Math.max(from, x);
        else until = Math.min(until, x);
      }
    }
  }
  return { from, until };
}

/// How often `inForce` was run: what the rules' state costs, counted for test/lock-moved.test.ts (views/lock.ts makes
/// it once while what it is made of stands, `inForceOf`).
export const made: { count: number } = { count: 0 };

/// What workspace `ws` is in force by the chain held (`entries`, its active chain), each person log's active chain
/// kept here (by its genesis hash), the bodies kept and this device's clock (`nowMs`). `name`: a station's name by its
/// key where its chain moved (a `station` body has none; what the workspace's view lists, deciding nothing), else its
/// key's first characters.
export function inForce(ws: string, entries: readonly Entry[], chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], nowMs: number, name: (key: string) => string | undefined = () => undefined): InForce {
  made.count++;
  const root = movedRoot(entries);
  if (root === null) return { said: "chain", root: null, f: fold(entries) };
  const now = Math.floor(nowMs / 1000);
  const out = rules.state4_js(ws, root, [...chains.values()], bodies, now, crypto) as J;
  // (a state the rules cannot make of what is kept is none: nobody is listed)
  if ("error" in out || (out.on !== "on" && out.on !== "off")) return { said: "waiting", root, f: none(), checked: checkedOf(rules.state4_js(ws, root, [], [], now, crypto)) };
  const s = out.state as J;
  const f = none();
  f.disabled = out.on === "off";
  for (const [sub, m] of arr(s.members)) f.members.set(sub, { email: String(m?.email ?? ""), role: String(m?.role ?? "") });
  for (const [sub, g] of arr(s.persons)) f.persons.set(sub, g);
  for (const [id, d] of arr(s.devices)) {
    const dev: J = { id, sub: d.sub, kind: d.kind, label: d.label };
    if (typeof d.sign_key === "string") dev.sign_key = d.sign_key;
    if (typeof d.exp === "number") dev.exp = d.exp;
    f.devices.set(id, dev);
  }
  for (const [key] of arr(s.stations)) f.stations.set(key, name(key) || key.slice(0, 8));
  // (when each device was put on: the `at` of the entry of its person's log that put it on last)
  for (const g of new Set(f.persons.values())) {
    const at = new Map<string, number>();
    const ids = new Map<string, string>();
    for (const e of chains.get(g) ?? []) {
      const b = (e.body ?? {}) as J;
      const d = e.kind === "genesis" ? b.device : b;
      if (e.kind === "genesis" || e.kind === "device") {
        if (typeof d?.id !== "string") continue;
        if (!ids.has(d.key)) at.set(d.id, e.at);
        ids.set(d.key, d.id);
      } else if (e.kind === "device.remove") {
        const id = ids.get(b.key);
        ids.delete(b.key);
        if (id !== undefined) at.delete(id);
      } else if (e.kind === "web") {
        if (!at.has(b.id)) at.set(b.id, e.at);
      } else if (e.kind === "web.remove") at.delete(b.id);
    }
    for (const [id, t] of at) if (f.persons.get(f.devices.get(id)?.sub) === g) f.added.set(id, t);
  }
  return { said: f.disabled ? "off" : "on", root, f, settings: { origins: arr(s.origins).map(String), rp_id: String(s.rp_id ?? ""), cloud_keys: s.cloud_keys ?? null }, checked: checkedOf(out) };
}
