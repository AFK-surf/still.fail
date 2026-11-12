// The bodies of one workspace's statements this station keeps, by their hash (rules/src/lock/body.mbt): a statement is
// an entry `ws {t, h}` in its signer's own log, its body `{ws, kind, …, prev, salt}` kept by the workspace alone, so
// that no log, the cloud's copy or a station of another workspace reads who is in it (station/test/lock-roster4-model.ts
// D1). Kept beside the workspace's lock (`mesh/locks/<ws>.bodies.json`), written as it is. A body is taken only where
// the rules find an entry this station keeps that commits to it under this workspace's tag (`bodyRefusal`), so what
// is kept is bounded by the entries kept; none is let go while the station keeps the workspace (off is a state: no
// entry drops a body). Pure but for its file: who is told is the caller's.
import { existsSync, readFileSync } from "node:fs";
import { writePrivate } from "../ops/files.ts";
import { type Entry, bodyHash, bodyRefusal, canonical } from "./lock.ts";

/// The longest body taken, in its canonical form: a statement says a person, a key, the settings.
export const BODY_MOST = 16 * 1024;

/// A body not taken, by its hash where it has one, and why.
export type BodyRefused = { hash: string | null; why: string };

export class LockBodies {
  readonly #path: string | null;
  #bodies: Map<string, unknown> | null = null;
  /// Counts each body taken: what is made of them is made again.
  version = 0;

  constructor(path: string | null) {
    this.#path = path;
  }

  #read(): Map<string, unknown> {
    if (this.#bodies !== null) return this.#bodies;
    const out = new Map<string, unknown>();
    try {
      if (this.#path !== null && existsSync(this.#path)) { // sync: read once, as the lock beside it is
        const raw = JSON.parse(readFileSync(this.#path, "utf8")); // sync: read once, as the lock beside it is
        for (const b of Array.isArray(raw?.bodies) ? raw.bodies : []) {
          const h = bodyHash(b);
          if (h !== null) out.set(h, b);
        }
      }
    } catch {
      // (a file that holds none: none kept; each is given again by the stations and devices that keep it)
    }
    this.#bodies = out;
    return out;
  }

  /// Every body kept, by its hash.
  all(): Map<string, unknown> {
    return this.#read();
  }

  has(h: string): boolean {
    return this.#read().has(h);
  }

  /// `bodies` taken where the rules find an entry kept that commits to each (`commits`, by the body's hash) under the
  /// tag of workspace `ws`; each one not, and why. Written once for all taken.
  take(ws: string, bodies: unknown[], commits: (h: string) => { genesis: string; chain: Entry[] }[]): { taken: number; refused: BodyRefused[] } {
    const kept = this.#read();
    const refused: BodyRefused[] = [];
    let taken = 0;
    for (const b of bodies) {
      let text: string;
      try {
        text = canonical(b);
      } catch {
        refused.push({ hash: null, why: "a body is {ws, kind, …, salt}" });
        continue;
      }
      if (text.length > BODY_MOST) {
        refused.push({ hash: null, why: "a body this long is no statement" });
        continue;
      }
      const h = bodyHash(b);
      if (h === null) {
        refused.push({ hash: null, why: "a body is {ws, kind, …, salt}" });
        continue;
      }
      if (kept.has(h)) continue;
      const why = bodyRefusal(ws, b, commits(h));
      if (why !== null) {
        refused.push({ hash: h, why });
        continue;
      }
      kept.set(h, JSON.parse(text));
      taken++;
    }
    if (taken > 0) {
      this.version++;
      if (this.#path !== null) writePrivate(this.#path, JSON.stringify({ bodies: [...kept.values()] }));
    }
    return { taken, refused };
  }
}
