// The longest chain of each person's own lock this station has heard (docs/personal-lock.md): a device taken off a lock
// could bring the chain from before, so an older one brought is judged as the longer one kept. A chain that is neither
// goes on from nor is part of the one kept is another's word against it: refused. Kept in memory: a restarted station has
// only what is brought next.
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

  /// Which of what is kept and what is `brought` to judge by: the longer, when one goes on from the other.
  newest(genesis: string, _sub: string, brought: unknown[]): unknown[] {
    const kept = this.#kept.get(genesis);
    if (kept === undefined) return brought;
    const shorter = kept.length <= brought.length ? kept : brought;
    const longer = kept.length <= brought.length ? brought : kept;
    if (!shorter.every((e, i) => same(e, longer[i]))) throw new LockRefusal("this device brought a lock at odds with the one its person has here");
    return longer;
  }

  /// Checked and let in on it: kept.
  keep(genesis: string, chain: unknown[]): void {
    this.#kept.set(genesis, chain);
  }
}
