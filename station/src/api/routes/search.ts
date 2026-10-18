// What a search finds on this station (docs/search.md): GET /search?q=&kinds=&limit=&offset=, as the asker may see it
// (their workspace's, and what only a member who may write reaches). `{groups: [{kind, hits, more}], building}`
// (`building` always false). People are not given the execution history: agents search it (tools/search.ts).
import { type Request, error, json, param } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { readOnly } from "../../mesh/credential.ts";
import type { Asker } from "../../search/match.ts";

/// What a viewer is asking as.
export const askerOf = (viewer: Request["viewer"]): Asker => ({ workspace: viewer.workspace, home: viewer.home !== false, scopes: readOnly(viewer) ? [] : ["write"] });

const count = (v: string | undefined, fallback: number) => (v !== undefined && /^[0-9]{1,4}$/.test(v) ? Number(v) : fallback);

export const routes = ({ agents }: Tools): Route[] => [
  {
    method: "GET",
    pattern: /^\/search$/,
    handle: async (r: Request) => {
      const q = param(r, "q") ?? "";
      if (q.length > 200) return error(400, "a search is at most 200 characters");
      const kinds = (param(r, "kinds") ?? "").split(",").filter((k) => /^[a-z]{1,24}$/.test(k) && k !== "history");
      if (param(r, "kinds") === "history") return json(200, JSON.stringify({ groups: [], building: false }));
      if (!agents) return error(503, "station starting");
      try {
        const found = await agents.search.query(q, askerOf(r.viewer), { kinds, limit: count(param(r, "limit"), 8), offset: count(param(r, "offset"), 0) });
        return json(200, JSON.stringify(found));
      } catch (e) {
        return error(503, (e as Error).message);
      }
    },
  },
];
