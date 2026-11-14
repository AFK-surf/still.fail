// The models a person starred in a workspace (模型收藏), the same on all their devices and every station of it (the user,
// 2026-11-14): their devices carry them, as they do their presets (sessions/presets.ts), and the stations do not bring
// them level with each other. GET /stars gives the asker's own; PUT /stars `{stars}` merges what their device brings
// model by model, the newer of each kept (client/core-ts/src/preset-records.ts `mergeStars`), and answers what is kept
// now. A change is told to that person's devices alone (`stars`, `{workspace}`), which read GET /stars again. A
// station from before answers 404 `no route …`.
//
// Kept in stillfail.db (`model_stars`), one row a person a workspace, read by its key as it is first asked and held
// after. Nothing is kept of someone who asked nothing; what a member who left starred stays, read by nobody.
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { RecordRefusal, type Stars, canonical, mergeStars, starsOf } from "../../../../client/core-ts/src/preset-records.ts";

/// Where they are kept (the store's `model_stars`).
export type StarsKept = { modelStars(ws: string, sub: string): string | null; putModelStars(ws: string, sub: string, stars: string): void };

export type StarsDeps = { kept: StarsKept; told?: (ws: string, sub: string) => void };

/// A PUT /stars body is so large at most (STARS_MOST models of keys STAR_KEY_MOST long fit in it many times over).
const BODY_MOST = 256 * 1024;

export function routes({ kept, told }: StarsDeps): Route[] {
  // (each person's as last read or written: read by its key once)
  const held = new Map<string, Stars>();
  const keyOf = (ws: string, sub: string) => `${ws}\0${sub}`;
  const read = (ws: string, sub: string): Stars => {
    const at = keyOf(ws, sub);
    let stars = held.get(at);
    if (stars === undefined) {
      const text = kept.modelStars(ws, sub);
      try {
        stars = text === null ? {} : starsOf(JSON.parse(text));
      } catch (e) {
        log.warn("stars", "a person's stars kept here do not read; taken as none", { error: (e as Error).message });
        stars = {};
      }
      held.set(at, stars);
    }
    return stars;
  };
  return [
    {
      method: "GET",
      pattern: /^\/stars$/,
      handle: async (r: Request): Promise<Answer> => {
        if (!r.viewer.sub) return error(403, "stars are a person's own");
        return json(200, JSON.stringify({ stars: read(r.viewer.workspace, r.viewer.sub) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/stars$/,
      handle: async (r: Request): Promise<Answer> => {
        if (!r.viewer.sub) return error(403, "stars are a person's own");
        if (r.body.length > BODY_MOST) return error(413, "request too large");
        let given: Stars;
        try {
          given = starsOf((JSON.parse(r.body.toString("utf8") || "{}") as { stars?: unknown } | null)?.stars);
        } catch (e) {
          return error(400, e instanceof RecordRefusal ? e.message : "invalid JSON");
        }
        const ws = r.viewer.workspace;
        const sub = r.viewer.sub;
        const was = read(ws, sub);
        const now = mergeStars(was, given);
        if (canonical(now) !== canonical(was)) {
          kept.putModelStars(ws, sub, JSON.stringify(now));
          held.set(keyOf(ws, sub), now);
          told?.(ws, sub);
        }
        return json(200, JSON.stringify({ stars: now }));
      },
    },
  ];
}
