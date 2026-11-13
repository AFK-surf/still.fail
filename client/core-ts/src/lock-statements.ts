// What this device says of a workspace whose chain moved to its people's own logs (src/lock-moved.ts reads it): a
// statement is an entry `ws {t, h}` on its person's own log and its body `{ws, kind, …, prev, salt}` kept apart, made
// as the fourth round's model makes one (station/test/lock-roster4-model.ts `World4.make`, its defaults: `order=whole`,
// `cancels=h`) and checked against the rules (rules/src/lock/roster.mbt) before anything is signed. Pure: what is
// signed, kept and brought is the caller's (personal-lock.ts `say`, views/lock.ts).
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { type Entry, entryHash } from "./lock.ts";
import { bodyHash, wsTag } from "./lock-moved.ts";
import { crypto, personOf } from "./personal-lock.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);

/// What a statement says, before it names the one before it and is salted (rules/src/lock/body.mbt `body_why`).
export type Said =
  | { kind: "member"; sub: string; email: string; lock: string; role: string }
  | { kind: "member.remove"; sub: string }
  | { kind: "station"; key: string }
  | { kind: "station.remove"; key: string }
  | { kind: "open"; origins: string[]; rp_id: string; cloud_keys: unknown; email: string }
  | { kind: "off" };
export type Body = { ws: string; kind: string; prev: string | null; salt: string; [k: string]: unknown };

/// The bodies kept here by their hash (one with none is no statement's: left out).
export function byHash(bodies: Iterable<unknown>): Map<string, J> {
  const out = new Map<string, J>();
  for (const b of bodies) {
    const h = bodyHash(b);
    if (h !== null && !out.has(h)) out.set(h, b);
  }
  return out;
}

/// `prev` (`order=whole`): the `h` of the latest statement of `ws`'s tag on `log` (the chain the statement is signed
/// after, its genesis first) whose body this device keeps and so every body along that one's own `prev` chain; null
/// where there is none. One whose body or chain is not all here is passed over: a keeper counts a statement only where
/// it keeps its whole chain, so naming it would hold this one up behind a body that may never come.
export function prevOf(ws: string, log: readonly Entry[], kept: ReadonlyMap<string, J>): string | null {
  if (log.length === 0) return null;
  const t = wsTag(ws, entryHash(log[0]!));
  const whole = (h: string): boolean => {
    for (let p: string | null = h, n = 0; p !== null && n < 10_000; n++) {
      const b = kept.get(p);
      if (b === undefined) return false;
      p = typeof b.prev === "string" ? b.prev : null;
    }
    return true;
  };
  for (let i = log.length - 1; i > 0; i--) {
    const b = log[i]!.body as J;
    if (log[i]!.kind === "ws" && b?.t === t && typeof b.h === "string" && whole(b.h)) return b.h;
  }
  return null;
}

/// What a removal takes back (`cancels=h`): every body kept here that admits whom it removes in `ws` (each `member` of
/// that sub, each `station` of that key), whoever signed it; sorted, each once.
export function cancelsOf(ws: string, said: { kind: "member.remove"; sub: string } | { kind: "station.remove"; key: string }, kept: ReadonlyMap<string, J>): string[] {
  const out: string[] = [];
  for (const [h, b] of kept) {
    if (b?.ws !== ws) continue;
    if (said.kind === "member.remove" ? b.kind === "member" && b.sub === said.sub : b.kind === "station" && b.key === said.key) out.push(h);
  }
  return out.sort();
}

/// The body of `said` in `ws`, signed after `log` by this device, of what it keeps (`kept`, its own bodies among them),
/// salted with `salt` (16 random bytes, hex).
export function bodyOf(ws: string, said: Said, log: readonly Entry[], kept: ReadonlyMap<string, J>, salt: string | (() => string)): Body {
  const prev = prevOf(ws, log, kept);
  const more: Record<string, unknown> = { ...said };
  if (said.kind === "member.remove" || said.kind === "station.remove") more.cancels = cancelsOf(ws, said, kept);
  return { ...more, ws, kind: said.kind, prev, salt: typeof salt === "string" ? salt : salt() } as Body;
}

/// The bodies of `says`, signed one after another after `log` (each next one's `prev` the one before it, whose chain is
/// whole here as the first's is), each salted by `salt()`.
export function bodiesOf(ws: string, says: readonly Said[], log: readonly Entry[], kept: ReadonlyMap<string, J>, salt: () => string): Body[] {
  const have = new Map(kept);
  const out: Body[] = [];
  for (const s of says) {
    const b = bodyOf(ws, s, log, have, salt);
    if (out.length > 0) b.prev = bodyHash(out[out.length - 1])!;
    have.set(bodyHash(b)!, b);
    out.push(b);
  }
  return out;
}

/// The commitment of `body` in `sub`'s log of genesis `genesis`: the entry's body.
export const commitOf = (ws: string, genesis: string, body: unknown): { t: string; h: string } => ({ t: wsTag(ws, genesis), h: bodyHash(body)! });

/// What `roster_js` lists, as compared here: each member's role and log, the stations, the newest of open and off.
type Listed = { members: Map<string, { role: string; lock: string; email: string | null }>; stations: Set<string>; newest: string | null; statements: Map<string, J> };
function listed(ws: string, root: string, chains: readonly (readonly Entry[])[], bodies: readonly unknown[], c: typeof crypto): Listed | null {
  const r = rules.roster_js(ws, root, chains, bodies, [], c) as J;
  if (r === null || typeof r !== "object" || "error" in r || r.rooted !== true) return null;
  const inForce = new Map<string, string>(arr(r.in_force).map((x) => [String(x.entry), String(x.body)]));
  const kept = byHash(bodies);
  const members = new Map<string, { role: string; lock: string; email: string | null }>();
  for (const m of arr(r.members)) {
    const admit = typeof m.admit === "string" ? kept.get(inForce.get(m.admit) ?? "") : undefined;
    members.set(String(m.sub), { role: String(m.role), lock: String(m.lock), email: typeof admit?.email === "string" ? admit.email : null });
  }
  return { members, stations: new Set(arr(r.stations).map(String)), newest: typeof r.newest === "string" ? r.newest : null, statements: new Map(arr(r.statements).map((s) => [String(s.hash), s])) };
}

/// How many rounds the take-over is worked out in at most: each says again those its last round would have dropped.
export const TAKE_OVER_ROUNDS = 4;

/// What this device signs for an act (`meant`, in order) on `ws`, rooted in `root`, of the person logs it holds
/// (`chains`, each its active chain; its own `own.genesis` among them as pinned, with what is pending after it) and the
/// bodies it keeps: `meant` with, first, a `member` or `station` of its own saying again each that its statements would
/// otherwise drop (a statement counts only while its signer stands as an owner or admin: the model's `adopt`, so that
/// taking someone out takes nobody else with them), worked out with the rules on what would be (nothing signed: each
/// entry is made here, its signature taken as this device's key's), until the list differs from the one in force only
/// by what was meant. `why` where that cannot be reached in TAKE_OVER_ROUNDS, or the act would change nothing of what
/// it means (its signer no owner or admin, a role it may not give, a circle of removals), or the root's log is not
/// held: then nothing is to be signed.
export function plan(ws: string, root: string, chains: ReadonlyMap<string, readonly Entry[]>, bodies: readonly unknown[], own: { genesis: string; sub: string; key: string }, meant: readonly Said[], nowSecs: number): { says: Said[] } | { why: string } {
  const before = listed(ws, root, [...chains.values()], bodies, crypto);
  if (before === null) return { why: "the workspace's root log is not held here" };
  const log = chains.get(own.genesis);
  if (log === undefined || log.length === 0) return { why: "this device's person log is not held here" };
  const extra: Said[] = [];
  for (let round = 0; round < TAKE_OVER_ROUNDS; round++) {
    const says = [...extra, ...meant];
    // (each signed after the one before, made here: its signature is taken as this device's key's by this crypto alone)
    const made = new Set<string>();
    const kept = byHash(bodies);
    const chain = [...log];
    const newBodies: Body[] = [];
    for (const s of says) {
      const b = bodyOf(ws, s, chain, kept, "0".repeat(32 - String(newBodies.length).length) + newBodies.length);
      const h = bodyHash(b)!;
      kept.set(h, b);
      newBodies.push(b);
      const last = chain[chain.length - 1]!;
      const e = { v: 1 as const, ws: personOf(own.sub), seq: chain.length, prev: entryHash(last), at: Math.max(last.at, nowSecs), kind: "ws", body: commitOf(ws, own.genesis, b) };
      const eh = entryHash(e);
      made.add(eh);
      chain.push({ ...e, sig: { key: own.key, alg: "Ed25519", sig: "" } });
    }
    const c = { ...crypto, sigValid: (sig: J, hash: string) => (made.has(hash) && sig?.key === own.key) || crypto.sigValid(sig, hash) };
    const others = [...chains].filter(([g]) => g !== own.genesis).map(([, es]) => es);
    const after = listed(ws, root, [...others, chain], [...bodies, ...newBodies], c);
    if (after === null) return { why: "the workspace's root log is not held here" };
    const off = otherwise(before, after, meant);
    if (off.why !== null) return { why: off.why };
    if (off.again.length === 0) return { says };
    let more = false;
    for (const a of off.again) {
      if (extra.some((x) => sameSubject(x, a))) continue;
      extra.push(a);
      more = true;
    }
    if (!more) return { why: "what it would take out besides cannot be said again by this device" };
  }
  return { why: "what it would take out besides cannot be said again by this device" };
}

const sameSubject = (a: Said, b: Said): boolean =>
  ("sub" in a && "sub" in b && a.sub === b.sub) || ("key" in a && "key" in b && a.key === b.key);

/// How the list `after` this device's statements differs from `before` but for what was `meant`: whom to say again
/// (as before had them: a member's log, role and email; a station's key), or why it cannot (the act would not do what
/// it means; someone not meant would come in or change in a way saying them again does not undo).
function otherwise(before: Listed, after: Listed, meant: readonly Said[]): { again: Said[]; why: string | null } {
  const subs = new Set(meant.flatMap((m) => ("sub" in m ? [m.sub] : [])));
  const keys = new Set(meant.flatMap((m) => ("key" in m ? [m.key] : [])));
  // what was meant, done: of each member and station named, the last that said it; on or off
  const undone = { again: [], why: "the change would not take effect by the rules" };
  for (const sub of subs) {
    const m = [...meant].reverse().find((x) => x.kind === "member" && x.sub === sub) as Extract<Said, { kind: "member" }> | undefined;
    const now = after.members.get(sub);
    if (m !== undefined ? now?.role !== m.role || now.lock !== m.lock : now !== undefined) return undone;
  }
  for (const key of keys) {
    const last = [...meant].reverse().find((x) => "key" in x && x.key === key)!;
    if (after.stations.has(key) !== (last.kind === "station")) return undone;
  }
  const onOff = [...meant].reverse().find((x) => x.kind === "open" || x.kind === "off");
  if (onOff !== undefined && after.newest !== onOff.kind) return undone;
  const again: Said[] = [];
  for (const [sub, m] of before.members) {
    if (subs.has(sub)) continue;
    const now = after.members.get(sub);
    if (now !== undefined && now.role === m.role && now.lock === m.lock) continue;
    // (the root has no admit: nothing says it again, nor need it)
    if (m.email === null) return { again: [], why: "it would change someone it does not mean" };
    again.push({ kind: "member", sub, email: m.email, lock: m.lock, role: m.role });
  }
  for (const [sub] of after.members) if (!subs.has(sub) && !before.members.has(sub)) return { again: [], why: "it would change someone it does not mean" };
  for (const key of before.stations) if (!keys.has(key) && !after.stations.has(key)) again.push({ kind: "station", key });
  for (const key of after.stations) if (!keys.has(key) && !before.stations.has(key)) return { again: [], why: "it would change someone it does not mean" };
  return { again, why: null };
}
