// Each person's own lock this station has heard: every entry the rules take after a parent it keeps, and the active
// chain the rules' fork choice gives of them (cloud/log-keep.ts), the rest kept aside. A device taken off a lock could
// bring the chain from before: as part of the one kept, it changes nothing; where it goes on from there, it is weighed
// at the place it parts from the one kept, and a removal there wins over what it signed. Kept on disk, so a restart does
// not forget a device was taken off.
//
// The station is also where a person's devices find their lock (the root AGENTS.md, The cloud is the account system): a
// device brings the chain as it grows (POST /lock/person) and reads it (GET /lock/person), the person's streams are told
// its head moved (`person`), and the stations of the workspaces it was heard in keep each other level (person-sync.ts). So it
// keeps, by each chain, the workspaces it was heard in, and a few chains a person (each begun anew) at most.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { type Entry, LockRefusal, asEntry, personChain } from "../cloud/lock.ts";
import { type Kept, type LogRules, type OffChain, hashOf, keep, rechoose } from "../cloud/log-keep.ts";

/// At most this many chains of one person (a lock begun anew when all their devices were lost): the oldest go.
export const CHAINS_A_PERSON = 4;
/// At most this many entries in a chain: a person's devices, added and removed (as the cloud kept, cloud/src/personal-lock.ts).
export const CHAIN_MOST = 1024;

/// What a station answers a chain at odds with the one kept (it lost its place where it parts from it): as before it
/// kept every branch.
export const AT_ODDS = "this device brought a lock at odds with the one its person has here";

/// Round three's statements of a workspace in the clear, which no log ever carried and the rules refuse now
/// (rules/src/lock/person.mbt `fold_person`: a workspace's statement is a commitment, `ws`): refused here as they were.
const STATEMENTS = new Set(["ws.member", "ws.member.remove", "ws.station", "ws.station.remove"]);

/// Whose a chain is: its entries name the person's lock (`person:<sub>`).
export function subOf(chain: readonly unknown[]): string | null {
  const ws = (chain[0] as { ws?: unknown } | undefined)?.ws;
  return typeof ws === "string" && ws.startsWith("person:") ? ws.slice("person:".length) : null;
}

/// A person log's rules for keeping, of the log of genesis hash `genesis` named `person:<sub>`.
function personRules(genesis: string, ws: string): LogRules {
  return {
    chain: (all) => personChain(all, genesis),
    pre: (e) => (e.ws !== ws ? "an entry of another lock" : STATEMENTS.has(e.kind) ? `unknown entry kind ${e.kind}` : null),
  };
}

/// What taking a person's entries did: the chain gone by now, how many were kept that were not, each brought that is
/// not on the chain and why, and whether the last brought is on it.
export type PersonTook = { chain: Entry[]; taken: number; off: OffChain[]; on: boolean };

export class PersonChains {
  /// Each log's active chain, by its genesis.
  readonly #kept = new Map<string, Entry[]>();
  /// Each log's entries kept off it.
  readonly #aside = new Map<string, Entry[]>();
  /// The workspaces each chain was heard in (`""`: none said).
  readonly #heard = new Map<string, Set<string>>();
  readonly #path: string | null;
  readonly #told = new Set<(genesis: string) => void>();
  readonly #changed = new Set<(genesis: string) => void>();

  constructor(path: string | null = null) {
    this.#path = path;
    if (path === null) return;
    try {
      const read = JSON.parse(readFileSync(path, "utf8"));
      // Written before the workspaces were kept: the chains alone.
      const chains = read?.chains !== undefined && typeof read.chains === "object" ? read.chains : read;
      for (const [genesis, chain] of Object.entries(chains ?? {})) if (Array.isArray(chain)) this.#kept.set(genesis, chain);
      for (const [genesis, ws] of Object.entries(read?.heard ?? {})) if (Array.isArray(ws)) this.#heard.set(genesis, new Set(ws.filter((w): w is string => typeof w === "string")));
      // Absent from files of before 2026-11-12 and while none is: the entries kept off each chain, the chain chosen
      // again among all as it is read.
      for (const [genesis, aside] of Object.entries(read?.aside ?? {})) {
        const chain = this.#kept.get(genesis);
        const entries = Array.isArray(aside) ? aside.map(asEntry).filter((e): e is Entry => e !== null) : [];
        if (chain === undefined || entries.length === 0) continue;
        try {
          const { kept } = rechoose({ entries: chain, aside: entries }, personRules(genesis, chain[0]!.ws));
          this.#kept.set(genesis, kept.entries);
          if (kept.aside.length > 0) this.#aside.set(genesis, kept.aside);
        } catch {}
      }
    } catch {}
  }

  /// Which of what is kept and what is `brought` to judge by: the chain the rules choose among both, where the last
  /// entry brought is on it (nothing is kept: `take` keeps). Throws a LockRefusal where it is not (it lost its place).
  newest(genesis: string, sub: string, brought: unknown[]): unknown[] {
    const had = this.#kept.get(genesis);
    if (had === undefined) return brought;
    const entries = entriesOf(brought);
    if (entries === null) throw new LockRefusal(AT_ODDS);
    const { line } = this.#onHead(genesis, entries);
    const t = keep({ entries: had, aside: this.#aside.get(genesis) ?? [] }, line, personRules(genesis, `person:${sub}`));
    if (!onChain(t.kept.entries, entries)) throw new LockRefusal(AT_ODDS);
    return t.kept.entries;
  }

  /// Of `entries` brought by a device itself: those kept already, and of the rest those that go on from the chain gone
  /// by's head, in order (none kept: from the genesis); the first that does not, not kept (cloud/state.ts `keepLock`).
  #onHead(genesis: string, entries: Entry[]): { line: Entry[]; stop: OffChain | null } {
    const kept = this.#kept.get(genesis) ?? [];
    const known = new Set([...kept, ...(this.#aside.get(genesis) ?? [])].map(hashOf));
    let head = kept.length === 0 ? null : hashOf(kept.at(-1)!);
    const line: Entry[] = [];
    for (const e of entries) {
      const h = hashOf(e);
      if (known.has(h)) {
        line.push(e);
        continue;
      }
      if (e.prev !== head) return { line, stop: { why: "not on the head", hash: h, seq: e.seq, kept: false } };
      known.add(h);
      line.push(e);
      head = h;
    }
    return { line, stop: null };
  }

  /// The chain the rules choose among what is kept and `brought`, nothing kept (none: the rules find none).
  chosen(genesis: string, sub: string, brought: unknown[]): Entry[] {
    const { line } = this.#onHead(genesis, entriesOf(brought) ?? []);
    return keep({ entries: this.#kept.get(genesis) ?? [], aside: this.#aside.get(genesis) ?? [] }, line, personRules(genesis, `person:${sub}`)).kept.entries;
  }

  /// `brought` (a chain, or entries in any order of the log of genesis `genesis`) taken, as heard in `ws` when said:
  /// with `fork` (a station's, or a device's saying another keeper took it) each entry the rules take after a parent
  /// kept, also off the chain gone by; else, brought by a device itself, only what goes on from the chain gone by's head
  /// (#onHead), as cloud/state.ts `keepLock` says why. Whoever listens told when the chain gone by moved (a device taken
  /// off it may be connected still). Throws why where the rules find no chain (its genesis not among them).
  take(genesis: string, sub: string, brought: unknown[], ws: string | null = null, fork = false): PersonTook {
    const had = this.#kept.get(genesis);
    const was: Kept = { entries: had ?? [], aside: this.#aside.get(genesis) ?? [] };
    const all = entriesOf(brought) ?? brought.map(asEntry).filter((e): e is Entry => e !== null);
    const { line, stop } = fork ? { line: all, stop: null } : this.#onHead(genesis, all);
    const entries = line;
    const t = keep(was, entries, personRules(genesis, `person:${sub}`));
    if (stop !== null) t.off.push(stop);
    if (t.kept.entries.length === 0) return { chain: had ?? [], taken: 0, off: t.off, on: false };
    this.#store(genesis, t.kept, ws, t.changed, t.moved);
    return { chain: t.kept.entries, taken: t.taken, off: t.off, on: onChain(t.kept.entries, all) && all.length === brought.length };
  }

  /// The chain gone by of the lock: none, none heard.
  kept(genesis: string): unknown[] | null {
    return this.#kept.get(genesis) ?? null;
  }

  /// Every entry kept of the lock: its chain, then those off it.
  all(genesis: string): Entry[] {
    return [...(this.#kept.get(genesis) ?? []), ...(this.#aside.get(genesis) ?? [])];
  }

  /// How many entries are kept off the lock's chain.
  asideOf(genesis: string): number {
    return this.#aside.get(genesis)?.length ?? 0;
  }

  /// Every chain kept of `sub`'s, by its genesis.
  of(sub: string): [string, unknown[]][] {
    return [...this.#kept].filter(([, chain]) => subOf(chain) === sub);
  }

  /// The chains heard in workspace `ws`, by their genesis.
  heardIn(ws: string): [string, unknown[]][] {
    return [...this.#kept].filter(([genesis]) => this.#heard.get(genesis)?.has(ws) === true);
  }

  /// Checked and let in on it: its entries kept (as heard in `ws`, when said); then whoever listens told when the chain
  /// gone by moved.
  keep(genesis: string, chain: unknown[], ws: string | null = null, fork = false): void {
    const sub = subOf(chain);
    if (sub === null) return;
    try {
      this.take(genesis, sub, chain, ws, fork);
    } catch {
      // (no chain of that genesis among them: nothing kept)
    }
  }

  #store(genesis: string, kept: Kept, ws: string | null, changed: boolean, moved: boolean) {
    const heard = this.#heard.get(genesis) ?? new Set<string>();
    const newly = ws !== null && !heard.has(ws);
    if (!changed && !newly) return;
    if (changed) {
      this.#kept.delete(genesis);
      this.#kept.set(genesis, kept.entries);
      if (kept.aside.length > 0) this.#aside.set(genesis, kept.aside);
      else this.#aside.delete(genesis);
      // A person's oldest chains go past the few kept (the latest is the one kept last).
      const sub = subOf(kept.entries);
      const theirs = [...this.#kept.keys()].filter((g) => subOf(this.#kept.get(g)!) === sub);
      for (const g of theirs.slice(0, Math.max(0, theirs.length - CHAINS_A_PERSON))) {
        this.#kept.delete(g);
        this.#aside.delete(g);
        this.#heard.delete(g);
      }
    }
    if (newly) this.#heard.set(genesis, heard.add(ws));
    if (this.#path !== null) {
      mkdirSync(dirname(this.#path), { recursive: true });
      const temp = `${this.#path}.tmp`;
      const heardOut = Object.fromEntries([...this.#heard].filter(([g]) => this.#kept.has(g)).map(([g, s]) => [g, [...s]]));
      const asideOut = this.#aside.size === 0 ? {} : { aside: Object.fromEntries([...this.#aside].filter(([g]) => this.#kept.has(g))) };
      writeFileSync(temp, JSON.stringify({ chains: Object.fromEntries(this.#kept), heard: heardOut, ...asideOut }), { mode: 0o600 }); // sync: one step with the answer that it was kept, as this file was always written
      renameSync(temp, this.#path);
    }
    if (moved) for (const f of [...this.#told]) f(genesis);
    for (const f of [...this.#changed]) f(genesis);
  }

  /// Told each time the chain gone by of a lock moves, on or to another branch (its genesis); returns what stops it.
  listen(f: (genesis: string) => void): () => void {
    this.#told.add(f);
    return () => void this.#told.delete(f);
  }

  /// Told each time anything kept of a lock changes, its chain or what is off it, or a workspace it was heard in; returns
  /// what stops it.
  watch(f: (genesis: string) => void): () => void {
    this.#changed.add(f);
    return () => void this.#changed.delete(f);
  }
}

/// Whether the last of `brought` is on `chain`.
function onChain(chain: Entry[], brought: Entry[]): boolean {
  const last = brought.at(-1);
  if (last === undefined) return true;
  const h = hashOf(last);
  return chain.some((e) => hashOf(e) === h);
}

/// Entries as they came over the wire, their shape checked (not their signature); null where one is malformed.
function entriesOf(raw: unknown[]): Entry[] | null {
  const out = raw.map(asEntry);
  return out.some((e) => e === null) ? null : (out as Entry[]);
}
