// The longest chain of each person's own lock this station has heard: a device taken off a lock
// could bring the chain from before, so an older one brought is judged as the longer one kept. A chain that neither goes
// on from nor is part of the one kept is another's word against it: refused. Kept on disk, so a restart does not forget a
// device was taken off.
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

export class PersonChains {
  readonly #kept = new Map<string, unknown[]>();
  readonly #path: string | null;

  constructor(path: string | null = null) {
    this.#path = path;
    if (path === null) return;
    try {
      for (const [genesis, chain] of Object.entries(JSON.parse(readFileSync(path, "utf8")))) if (Array.isArray(chain)) this.#kept.set(genesis, chain);
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

  /// Checked and let in on it: kept, when it is more than was.
  keep(genesis: string, chain: unknown[]): void {
    if (this.#kept.get(genesis)?.length === chain.length) return;
    this.#kept.set(genesis, chain);
    if (this.#path === null) return;
    mkdirSync(dirname(this.#path), { recursive: true });
    const temp = `${this.#path}.tmp`;
    writeFileSync(temp, JSON.stringify(Object.fromEntries(this.#kept)), { mode: 0o600 });
    renameSync(temp, this.#path);
  }
}
