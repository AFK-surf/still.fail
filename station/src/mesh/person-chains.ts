// The longest chain of each person's own lock this station has heard (docs/personal-lock.md): a device taken off a lock
// could bring the chain from before, so an older one brought is judged as the longer one kept. A chain that is neither
// goes on from nor is part of the one kept is another's word against it: refused. On disk, so a restart cannot forget a
// revocation already heard; SQLite serializes a handover's overlapping station processes.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
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
  readonly #db: DatabaseSync | null;
  #revision = 0;

  constructor(data?: string) {
    if (data === undefined) this.#db = null;
    else {
      const dir = join(data, "mesh");
      mkdirSync(dir, { recursive: true });
      this.#db = new DatabaseSync(join(dir, "person-locks.sqlite"));
      // Never wait synchronously on another station process: a busy database refuses this connection to retry.
      this.#db.exec("PRAGMA busy_timeout = 0; PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS chains (genesis TEXT PRIMARY KEY, entries TEXT NOT NULL)");
    }
  }

  close(): void { this.#db?.close(); }

  /// Changes by this process and by another station process sharing the database.
  version(): string {
    const data = this.#db?.prepare("PRAGMA data_version").get() as { data_version: number } | undefined;
    return `${data?.data_version ?? 0}:${this.#revision}`;
  }

  #read(genesis: string): unknown[] | undefined {
    if (this.#db === null) return this.#kept.get(genesis);
    const row = this.#db.prepare("SELECT entries FROM chains WHERE genesis = ?").get(genesis) as { entries: string } | undefined;
    if (!row) return undefined;
    try {
      const entries: unknown = JSON.parse(row.entries);
      if (Array.isArray(entries) && entries.length > 0) return entries;
    } catch {}
    throw new LockRefusal("the personal lock kept by this station is broken");
  }

  #longer(kept: unknown[] | undefined, brought: unknown[]): unknown[] {
    if (kept === undefined) return brought;
    const shorter = kept.length <= brought.length ? kept : brought;
    const longer = kept.length <= brought.length ? brought : kept;
    if (!shorter.every((e, i) => same(e, longer[i]))) throw new LockRefusal("this device brought a lock at odds with the one its person has here");
    return longer;
  }

  /// Which of what is kept and what is `brought` to judge by: the longer, when one goes on from the other.
  newest(genesis: string, _sub: string, brought: unknown[]): unknown[] {
    return this.#longer(this.#read(genesis), brought);
  }

  /// Checked: keep it atomically against any other station process and return whichever valid prefix is longer.
  keep(genesis: string, chain: unknown[]): unknown[] {
    if (this.#db === null) {
      const had = this.#kept.get(genesis), next = this.#longer(had, chain);
      this.#kept.set(genesis, next);
      if (had === undefined || next.length > had.length) this.#revision++;
      return next;
    }
    try { this.#db.exec("BEGIN IMMEDIATE"); }
    catch { throw new LockRefusal("the station is updating personal locks; try again"); }
    try {
      const had = this.#read(genesis), next = this.#longer(had, chain);
      const changed = had === undefined || next.length > had.length;
      if (changed) this.#db.prepare("INSERT OR REPLACE INTO chains (genesis, entries) VALUES (?, ?)").run(genesis, JSON.stringify(next));
      this.#db.exec("COMMIT");
      if (changed) this.#revision++;
      return next;
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
  }
}
