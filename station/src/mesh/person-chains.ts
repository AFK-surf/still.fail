// The longest chain of each person's own lock this station has heard: a device taken off a lock
// could bring the chain from before, so an older one brought is judged as the longer one kept. A chain that neither goes
// on from nor is part of the one kept is another's word against it: refused. Kept on disk, so a restart does not forget a
// device was taken off.
//
// The station is also where a person's devices find their lock (the root AGENTS.md, The cloud is the account system): a
// device brings the chain as it grows (POST /lock/person) and reads it (GET /lock/person), the person's streams are told
// it grew (`person`), and the stations of the workspaces it was heard in keep each other level (person-sync.ts). So it
// keeps, by each chain, the workspaces it was heard in, and a few chains a person (each begun anew) at most.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { LockRefusal, entryHash, type Entry } from "../cloud/lock.ts";

const same = (a: unknown, b: unknown) => {
  try {
    return entryHash(a as Entry) === entryHash(b as Entry);
  } catch {
    return false;
  }
};

/// At most this many chains of one person (a lock begun anew when all their devices were lost): the oldest go.
export const CHAINS_A_PERSON = 4;
/// At most this many entries in a chain: a person's devices, added and removed (as the cloud kept, cloud/src/personal-lock.ts).
export const CHAIN_MOST = 1024;

/// Whose a chain is: its entries name the person's lock (`person:<sub>`).
export function subOf(chain: readonly unknown[]): string | null {
  const ws = (chain[0] as { ws?: unknown } | undefined)?.ws;
  return typeof ws === "string" && ws.startsWith("person:") ? ws.slice("person:".length) : null;
}

export class PersonChains {
  readonly #kept = new Map<string, unknown[]>();
  /// The workspaces each chain was heard in (`""`: none said).
  readonly #heard = new Map<string, Set<string>>();
  readonly #path: string | null;
  readonly #told = new Set<(genesis: string) => void>();

  constructor(path: string | null = null) {
    this.#path = path;
    if (path === null) return;
    try {
      const read = JSON.parse(readFileSync(path, "utf8"));
      // Written before the workspaces were kept: the chains alone.
      const chains = read?.chains !== undefined && typeof read.chains === "object" ? read.chains : read;
      for (const [genesis, chain] of Object.entries(chains ?? {})) if (Array.isArray(chain)) this.#kept.set(genesis, chain);
      for (const [genesis, ws] of Object.entries(read?.heard ?? {})) if (Array.isArray(ws)) this.#heard.set(genesis, new Set(ws.filter((w): w is string => typeof w === "string")));
    } catch {}
  }

  /// Which of what is kept and what is `brought` to judge by: the longer, when one goes on from the other.
  newest(genesis: string, _sub: string, brought: unknown[]): unknown[] {
    const kept = this.#kept.get(genesis);
    if (kept === undefined) return brought;
    const shorter = kept.length <= brought.length ? kept : brought;
    const longer = kept.length <= brought.length ? brought : kept;
    if (!shorter.every((e, i) => same(e, longer[i]))) throw new LockRefusal("this device brought a lock at odds with the one its person has here");
    return longer;
  }

  /// The longest heard of the lock: none, none heard.
  kept(genesis: string): unknown[] | null {
    return this.#kept.get(genesis) ?? null;
  }

  /// Every chain kept of `sub`'s, by its genesis.
  of(sub: string): [string, unknown[]][] {
    return [...this.#kept].filter(([, chain]) => subOf(chain) === sub);
  }

  /// The chains heard in workspace `ws`, by their genesis.
  heardIn(ws: string): [string, unknown[]][] {
    return [...this.#kept].filter(([genesis]) => this.#heard.get(genesis)?.has(ws) === true);
  }

  /// Checked and let in on it: kept, when it is more than was (and as heard in `ws`, when said); then whoever listens
  /// told (a device taken off it may be connected still).
  keep(genesis: string, chain: unknown[], ws: string | null = null): void {
    const grew = this.#kept.get(genesis)?.length !== chain.length;
    const heard = this.#heard.get(genesis) ?? new Set<string>();
    const newly = ws !== null && !heard.has(ws);
    if (!grew && !newly) return;
    if (grew) {
      this.#kept.delete(genesis);
      this.#kept.set(genesis, chain);
      // A person's oldest chains go past the few kept (the latest is the one kept last).
      const sub = subOf(chain);
      const theirs = [...this.#kept.keys()].filter((g) => subOf(this.#kept.get(g)!) === sub);
      for (const g of theirs.slice(0, Math.max(0, theirs.length - CHAINS_A_PERSON))) {
        this.#kept.delete(g);
        this.#heard.delete(g);
      }
    }
    if (newly) this.#heard.set(genesis, heard.add(ws));
    if (this.#path !== null) {
      mkdirSync(dirname(this.#path), { recursive: true });
      const temp = `${this.#path}.tmp`;
      const heardOut = Object.fromEntries([...this.#heard].filter(([g]) => this.#kept.has(g)).map(([g, s]) => [g, [...s]]));
      writeFileSync(temp, JSON.stringify({ chains: Object.fromEntries(this.#kept), heard: heardOut }), { mode: 0o600 });
      renameSync(temp, this.#path);
    }
    if (grew) for (const f of [...this.#told]) f(genesis);
  }

  /// Told each time a chain kept grows (its genesis); returns what stops it.
  listen(f: (genesis: string) => void): () => void {
    this.#told.add(f);
    return () => void this.#told.delete(f);
  }
}
