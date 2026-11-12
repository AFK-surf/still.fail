// What this device keeps of one log, a workspace's lock or a person's own: the chain it goes by (`entries`, from the
// genesis, what every reader of it reads) and the entries a station showed it that are off that chain (`aside`). The
// chain is the rules' fork choice among all of them (rules/src/lock/chain.mbt `lock_chain`, `person_chain`), as a
// station's is (station/src/cloud/log-keep.ts, its twin: the same rules, not the same file), so a device that read a
// station on another branch goes by the branch the rules choose, and comes to the chain the stations come to
// (station/test/lock-fork-choice-model.ts). It drops nothing a station showed it but past the bound: an entry that lost
// its place stays aside, and wins again where the rules say so once more is known below its parent. Pure: where it is
// written and who is told is the caller's.
//
// Bounded as a station's is (ASIDE_MOST, log-keep.ts says why): past it, what would land aside is not kept, and the
// oldest kept aside go (with what hangs below them). Nothing on the chain gone by is dropped for it.
import { type Entry, entryHash } from "./lock.ts";

/// The most entries a log keeps off its chain (station/src/cloud/log-keep.ts ASIDE_MOST).
export const ASIDE_MOST = 256;

/// A log as kept: its chain gone by from the genesis, and the entries off it, in the order they were kept.
export type Kept = { entries: Entry[]; aside: Entry[] };

/// Why an entry given is off a log's chain, as the rules say it (station/src/cloud/lock.ts `Off`; `at` its place among
/// those given).
export type Off = { at: number; why: "refused" | "no parent" | "beaten" | "below" | "again"; refusal?: string; winner?: string; step?: string; under?: string };
/// A log's chain among entries given in any order, branching: their places on it from the genesis, its hashes, and why
/// each other one is off it.
export type Chain = { at: number[]; hashes: string[]; off: Off[] };

/// What a log's rules say for keeping: its chain among entries given (throwing where there is none); why an entry is
/// refused before the rules weigh it (another log's, a kind not taken yet).
export type LogRules = {
  chain(all: Entry[]): Chain;
  pre?(e: Entry): string | null;
};

export type Took = {
  kept: Kept;
  /// Whether the chain's head is another now.
  moved: boolean;
  /// Whether anything kept changed (to be written).
  changed: boolean;
};

const hashes = new WeakMap<object, string>();
/// An entry's hash, made once.
export function hashOf(e: Entry): string {
  let h = hashes.get(e);
  if (h === undefined) {
    h = entryHash(e);
    hashes.set(e, h);
  }
  return h;
}

/// Whether `entries` go on hop by hop from the genesis: each at its place, each `prev` the hash of the one before.
export function links(entries: readonly Entry[], from = 0): boolean {
  for (let i = Math.max(from, 0); i < entries.length; i++) {
    const e = entries[i]!;
    if (e?.seq !== i || (i === 0 ? e.prev !== null : e.prev !== hashOf(entries[i - 1]!))) return false;
  }
  return true;
}

/// `was` with `brought` taken: each entry the rules take after a parent kept (or brought with it) kept, the chain
/// chosen again among all of them. Throws where the rules find no chain of what was kept, or refuse an entry of the
/// chain held.
export function keep(was: Kept, brought: readonly Entry[], rules: LogRules): Took {
  const kept = new Set<string>();
  for (const e of [...was.entries, ...was.aside]) kept.add(hashOf(e));
  const seen = new Set<string>();
  const fresh: Entry[] = [];
  for (const e of brought) {
    const h = hashOf(e);
    if (kept.has(h) || seen.has(h)) continue;
    seen.add(h);
    if ((rules.pre?.(e) ?? null) === null) fresh.push(e);
  }
  if (fresh.length === 0) return { kept: was, moved: false, changed: false };
  const all = [...was.entries, ...was.aside, ...fresh];
  const r = rules.chain(all);
  const active = r.at.map((i) => all[i]!);
  const on = new Set(r.hashes);
  const offBy = new Map<string, Off>();
  for (const o of r.off) offBy.set(hashOf(all[o.at]!), o);
  const aside = (e: Entry) => {
    const o = offBy.get(hashOf(e));
    return o !== undefined && (o.why === "beaten" || o.why === "below");
  };
  // The chain held left only for one the rules choose over it: one of its own the rules refuse (taken unchecked of the
  // cloud, which only carries the lock) is no choice between branches, and what is held stays (the caller's).
  if (was.entries.some((e) => !on.has(hashOf(e)) && !aside(e))) throw new Error("the chain held does not hold by the rules");
  // Aside: what was, what the chain left, what is new; past the bound, what is new is not kept and the oldest go.
  const old = [...was.aside.filter(aside), ...was.entries.filter((e) => !on.has(hashOf(e)) && aside(e))];
  let room = ASIDE_MOST - old.length;
  const added: Entry[] = [];
  for (const e of [...fresh].sort((a, b) => a.seq - b.seq)) {
    if (on.has(hashOf(e)) || !aside(e) || room <= 0) continue;
    added.push(e);
    room--;
  }
  let side = [...old, ...added];
  if (side.length > ASIDE_MOST) side = side.slice(side.length - ASIDE_MOST);
  // What hangs below an entry not kept goes with it.
  const keptNow = new Set(on);
  for (const e of [...side].sort((a, b) => a.seq - b.seq)) if (e.prev !== null && keptNow.has(e.prev)) keptNow.add(hashOf(e));
  side = side.filter((e) => keptNow.has(hashOf(e)));
  const head = (es: readonly Entry[]) => (es.length === 0 ? "" : hashOf(es[es.length - 1]!));
  const same = (a: readonly Entry[], b: readonly Entry[]) => a.length === b.length && a.every((e, i) => hashOf(e) === hashOf(b[i]!));
  const was0 = new Set([...was.entries, ...was.aside].map(hashOf));
  const changed = !same(active, was.entries) || side.length !== was.aside.length || side.some((e) => !was0.has(hashOf(e)));
  return { kept: changed ? { entries: active, aside: side } : was, moved: head(active) !== head(was.entries), changed };
}
