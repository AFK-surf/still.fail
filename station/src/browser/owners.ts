// Which session opened each tab of the station's browser (docs/remote-screens.md, "Whose a tab is"): learnt from the
// session's own connection to it (proxy.ts) and from a tab's opener, kept in <data>/browser/owners.json as Chrome keeps
// its tabs, so the next station process that takes the browser up still knows them. A tab gone is forgotten. These are
// the station's own context's tabs: one in a chat's own context (browsers.ts) is that chat's, by its context.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";

export class Owners {
  readonly #file: string;
  readonly #dir: string;
  readonly #of: Map<string, string>;

  constructor(dir: string) {
    this.#dir = dir;
    this.#file = join(dir, "owners.json");
    this.#of = new Map(Object.entries(read(this.#file)));
  }

  /// The session that opened tab `targetId`, if one is known.
  of(targetId: string): string | undefined {
    return this.#of.get(targetId);
  }

  /// Tab `targetId` is `session`'s; whether that is news.
  set(targetId: string, session: string): boolean {
    if (this.#of.get(targetId) === session) return false;
    this.#of.set(targetId, session);
    this.#write();
    return true;
  }

  /// Tab `targetId` is gone.
  drop(targetId: string) {
    if (this.#of.delete(targetId)) this.#write();
  }

  /// Only these tabs are there (the browser as a station process takes it up): the rest are forgotten.
  keep(targetIds: Set<string>) {
    let changed = false;
    for (const id of [...this.#of.keys()]) if (!targetIds.has(id)) changed = this.#of.delete(id) || changed;
    if (changed) this.#write();
  }

  #write() {
    try {
      mkdirSync(this.#dir, { recursive: true });
      writeFileSync(this.#file, JSON.stringify(Object.fromEntries(this.#of), null, 2) + "\n");
    } catch (e) {
      log.warn("browser", "the tabs' owners could not be written", { error: (e as Error).message });
    }
  }
}

function read(file: string): Record<string, string> {
  try {
    const v = JSON.parse(readFileSync(file, "utf8"));
    if (v === null || typeof v !== "object" || Array.isArray(v)) return {};
    return Object.fromEntries(Object.entries(v).filter((e): e is [string, string] => typeof e[1] === "string" && e[1] !== ""));
  } catch {
    return {};
  }
}
