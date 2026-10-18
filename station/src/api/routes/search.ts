// What a search finds on this station (docs/search.md): GET /search?q=&kinds=&limit=&offset=, as the asker may see it
// (their workspace's, and what only a member who may write reaches). `{groups: [{kind, hits, more}], building}`
// (`building` always false). People find chats, messages, services and tasks, files: the execution history, skills and
// memory, the profiles are the agents' to search (tools/search.ts).
import { type Request, error, json, param } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { managesStation, readOnly } from "../../mesh/credential.ts";
import type { Asker } from "../../search/match.ts";

/// What a viewer is asking as.
export const askerOf = (viewer: Request["viewer"]): Asker => ({ workspace: viewer.workspace, home: viewer.home !== false, scopes: readOnly(viewer) ? [] : ["write"] });

/// What people find here.
export const PEOPLE = ["chat", "message", "job", "file"];

const count = (v: string | undefined, fallback: number) => (v !== undefined && /^[0-9]{1,4}$/.test(v) ? Number(v) : fallback);

export const routes = ({ agents, events }: Tools): Route[] => [
  // Whether the machine's person's own mail, messages, calendars, contacts, notes and photos are found too (config.json
  // `search.personal`, off unless set): the station's owners and admins say.
  {
    method: "PUT",
    pattern: /^\/search\/settings$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins set what the station's search finds");
      if (!agents) return error(503, "station starting");
      let personal: unknown;
      try {
        personal = JSON.parse(r.body.toString("utf8") || "{}")?.personal;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof personal !== "boolean") return error(400, "personal is true or false");
      agents.config.update((raw) => {
        raw.search = { ...(raw.search !== null && typeof raw.search === "object" ? raw.search : {}), personal };
      });
      events?.overviewChanged();
      return json(200, JSON.stringify({ personal }));
    },
  },
  {
    method: "GET",
    pattern: /^\/search$/,
    handle: async (r: Request) => {
      const q = param(r, "q") ?? "";
      if (q.length > 200) return error(400, "a search is at most 200 characters");
      const asked = (param(r, "kinds") ?? "").split(",").filter((k) => k !== "");
      const kinds = asked.length > 0 ? asked.filter((k) => PEOPLE.includes(k)) : PEOPLE;
      if (kinds.length === 0) return json(200, JSON.stringify({ groups: [], building: false }));
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
