// The grants of data outflow (docs/data-outflow.md), for the members of the station's home workspace: which programs
// of this machine may read what, what they read lately, and which ask (GET /outflow/grants); an admin's answer to a
// request (POST /outflow/requests/:id, `{allow, scopes, workspace}`); revoking a grant (DELETE /outflow/grants/:id),
// which its program's next read is refused for.
import { type Request, error, json, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import { type OutflowGrants, SCOPES, type Scope } from "../../outflow/grants.ts";

const home = (r: Request) => r.viewer.home !== false;

export const routes = (grants: OutflowGrants): Route[] => [
  {
    method: "GET",
    pattern: /^\/outflow\/grants\/?$/,
    handle: async (r: Request) => (home(r) ? json(200, JSON.stringify({ grants: grants.list(), requests: grants.asking() })) : error(403, "only the station's own workspace sees its grants")),
  },
  {
    method: "DELETE",
    pattern: /^\/outflow\/grants\/([^/]+)\/?$/,
    handle: async (r: Request, [id]: string[]) => {
      if (!home(r)) return error(403, "only the station's own workspace revokes its grants");
      return grants.revoke(percentDecode(id!)) ? json(200, JSON.stringify({ revoked: true })) : error(404, "no such grant");
    },
  },
  {
    method: "POST",
    pattern: /^\/outflow\/requests\/([^/]+)\/?$/,
    handle: async (r: Request, [id]: string[]) => {
      if (!home(r) || !managesStation(r.viewer)) return error(403, "only an admin of the station's own workspace answers its requests");
      let given: any;
      try {
        given = JSON.parse(r.body.toString("utf8"));
      } catch {
        return error(400, "the answer is not JSON");
      }
      const scopes: Scope[] = Array.isArray(given?.scopes) ? given.scopes.filter((s: unknown): s is Scope => SCOPES.includes(s as Scope)) : [];
      const answer = given?.allow === true ? { allow: true as const, scopes, reach: given?.workspace === true ? ("workspace" as const) : ("station" as const) } : { allow: false as const };
      return grants.answer(percentDecode(id!), r.viewer.email, answer) ? json(200, JSON.stringify({ answered: true })) : error(404, "no such request waiting");
    },
  },
];
