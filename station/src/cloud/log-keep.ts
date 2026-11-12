// What a station keeps of one log, a workspace's lock or a person's own: every entry the rules take after a parent it
// keeps, not only those that follow its head. It goes by the active chain the rules' fork choice gives of them
// (cloud/lock.ts `lockChain`, `personChain`); the rest are kept aside, so that two stations that took different entries
// at one place come to one chain once each has the other's (station/test/lock-fork-choice-model.ts). Pure: where it is
// written and who is told is the caller's.
//
// Bounded: a signer taken out of a log can still sign any number of entries the rules take after a parent from before
// (and after its own), each losing its place. At most ASIDE_MOST are kept aside a log; past it, what would land aside
// is not kept, and where another branch winning pushes the rest past it, the oldest kept aside go (with what hangs
// below them). Nothing on the active chain is ever refused or dropped for it: an entry aside lost to one the station
// keeps, so to one every station that has both goes by, and none of the chain all of them come to is ever aside at
// any of them. So the bound leaves what is kept aside differing between stations, never the chain they go by. (The
// model's `retain`, which refused an entry by how far its parent is behind the head, refused the winners of a station
// away for long, and left it on a chain of its own.)
import { type Chain, type Entry, type Off, entryHash } from "./lock.ts";

/// The most entries a log keeps off its active chain. An honest history leaves one a time two devices signed at once
/// and the one that lost had not signed again since: a few a year.
export const ASIDE_MOST = 256;

/// A log as kept: its active chain from the genesis, and the entries off it, in the order they were kept.
export type Kept = { entries: Entry[]; aside: Entry[] };

/// Why an entry brought is not on the active chain after it was taken: as the rules say it (`Off`), refused before
/// (`refused`, why), or, brought by a device itself, not going on from the head (`not on the head`: not kept,
/// cloud/state.ts `keepLock`); its hash and place, and whether it is kept aside.
export type OffChain = Omit<Off, "at" | "why"> & { why: Off["why"] | "not on the head"; hash: string; seq: number; kept: boolean };

export type Took = {
  kept: Kept;
  /// Entries brought kept now that were not before (on the chain or aside).
  taken: number;
  /// Each entry brought (once) that is not on the active chain now, and why.
  off: OffChain[];
  /// Whether the active chain's head is another now.
  moved: boolean;
  /// Whether anything kept changed (to be written).
  changed: boolean;
};

/// What a log's rules say for keeping: its active chain among entries given; why an entry is refused before the rules
/// weigh it (another log's, a kind this station does not take yet); why the rules refuse it after its parent with the
/// station's time (`now`: the workspace lock's devices that ran out; `find` any entry kept or taken with it).
export type LogRules = {
  chain(all: Entry[]): Chain;
  pre?(e: Entry): string | null;
  now?(parent: string, e: Entry, find: (hash: string) => Entry | undefined): string | null;
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

/// `was` with `brought` taken: each entry the rules take after a parent kept (or brought with it) kept, the active chain
/// chosen again among all of them. Throws only where the rules find no chain of what was kept.
export function keep(was: Kept, brought: Entry[], rules: LogRules): Took {
  const kept = new Map<string, Entry>();
  for (const e of [...was.entries, ...was.aside]) kept.set(hashOf(e), e);
  const before = new Set(was.entries.map(hashOf));
  const why = new Map<string, OffChain>();
  const said = (e: Entry, refusal: string) => why.set(hashOf(e), { why: "refused", refusal, hash: hashOf(e), seq: e.seq, kept: false });
  const seen = new Set<string>();
  const candidates: Entry[] = [];
  for (const e of brought) {
    const h = hashOf(e);
    if (kept.has(h) || seen.has(h)) continue;
    seen.add(h);
    const pre = rules.pre?.(e) ?? null;
    if (pre !== null) said(e, pre);
    else candidates.push(e);
  }
  // Checked with the station's time after their parents, parents first; one with no parent kept or taken is the
  // chain's to say.
  let accepted = candidates;
  if (rules.now !== undefined) {
    const ok = new Map<string, Entry>();
    for (const c of [...candidates].sort((a, b) => a.seq - b.seq)) {
      const p = c.prev;
      if (p !== null && (kept.has(p) || ok.has(p))) {
        const refused = rules.now(p, c, (x) => kept.get(x) ?? ok.get(x));
        if (refused !== null) {
          said(c, refused);
          continue;
        }
      }
      ok.set(hashOf(c), c);
    }
    accepted = candidates.filter((c) => !why.has(hashOf(c)));
  }
  const broughtAside = brought.some((e) => !before.has(hashOf(e)) && kept.has(hashOf(e)));
  if (accepted.length === 0 && !broughtAside) return { kept: was, taken: 0, off: offOf(brought, why, before), moved: false, changed: false };
  return settle(was, accepted, rules, brought, why);
}

/// The chain chosen again among all `was` keeps (a log read from its file).
export function rechoose(was: Kept, rules: LogRules): Took {
  return settle(was, [], rules, [], new Map());
}

function settle(was: Kept, accepted: Entry[], rules: LogRules, brought: Entry[], why: Map<string, OffChain>): Took {
  const all = [...was.entries, ...was.aside, ...accepted];
  const r = rules.chain(all);
  const active = r.at.map((i) => all[i]!);
  const on = new Set(r.hashes);
  const offBy = new Map<string, Off>();
  for (const o of r.off) offBy.set(hashOf(all[o.at]!), o);
  const aside = (e: Entry) => {
    const o = offBy.get(hashOf(e));
    return o !== undefined && (o.why === "beaten" || o.why === "below");
  };
  // Aside: what was, what the chain left, what is new; past the bound, what is new is not kept and the oldest go.
  const old = [...was.aside.filter(aside), ...was.entries.filter((e) => !on.has(hashOf(e)) && aside(e))];
  let room = ASIDE_MOST - old.length;
  const fresh: Entry[] = [];
  for (const e of [...accepted].sort((a, b) => a.seq - b.seq)) {
    if (on.has(hashOf(e)) || !aside(e)) continue;
    if (room > 0) {
      fresh.push(e);
      room--;
    }
  }
  let side = [...old, ...fresh];
  if (side.length > ASIDE_MOST) side = side.slice(side.length - ASIDE_MOST);
  // What hangs below an entry not kept goes with it.
  const keptNow = new Set([...on]);
  for (const e of [...side].sort((a, b) => a.seq - b.seq)) if (e.prev !== null && keptNow.has(e.prev)) keptNow.add(hashOf(e));
  side = side.filter((e) => keptNow.has(hashOf(e)));
  const kept: Kept = { entries: active, aside: side };
  for (const e of brought) {
    const h = hashOf(e);
    if (on.has(h) || why.has(h)) continue;
    const o = offBy.get(h);
    if (o === undefined) continue;
    const { at: _, ...rest } = o;
    why.set(h, { ...rest, hash: h, seq: e.seq, kept: keptNow.has(h) });
  }
  const was0 = new Set([...was.entries, ...was.aside].map(hashOf));
  const taken = accepted.filter((e) => keptNow.has(hashOf(e))).length;
  const head = (es: Entry[]) => (es.length === 0 ? "" : hashOf(es.at(-1)!));
  const moved = head(active) !== head(was.entries);
  const same = (a: Entry[], b: Entry[]) => a.length === b.length && a.every((e, i) => hashOf(e) === hashOf(b[i]!));
  const changed = taken > 0 || !same(active, was.entries) || side.length !== was.aside.length || side.some((e) => !was0.has(hashOf(e)));
  return { kept, taken, off: offOf(brought, why, on), moved, changed };
}

/// Each entry brought (once) not on the chain `on`, with why.
function offOf(brought: Entry[], why: Map<string, OffChain>, on: Set<string>): OffChain[] {
  const out: OffChain[] = [];
  const seen = new Set<string>();
  for (const e of brought) {
    const h = hashOf(e);
    if (on.has(h) || seen.has(h)) continue;
    seen.add(h);
    const w = why.get(h);
    if (w !== undefined) out.push(w);
  }
  return out;
}
