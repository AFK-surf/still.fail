// The grants of data outflow (docs/data-outflow.md), for the members of the station's home workspace: which programs
// of this machine may read what, and what they read lately (GET /outflow/grants); revoking one (DELETE
// /outflow/grants/:id), which its program's next read is refused for.
import { type Request, error, json, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import type { OutflowGrants } from "../../outflow/grants.ts";

const home = (r: Request) => r.viewer.home !== false;

export const routes = (grants: OutflowGrants): Route[] => [
  {
    method: "GET",
    pattern: /^\/outflow\/grants\/?$/,
    handle: async (r: Request) => (home(r) ? json(200, JSON.stringify({ grants: grants.list() })) : error(403, "only the station's own workspace sees its grants")),
  },
  {
    method: "DELETE",
    pattern: /^\/outflow\/grants\/([^/]+)\/?$/,
    handle: async (r: Request, [id]: string[]) => {
      if (!home(r)) return error(403, "only the station's own workspace revokes its grants");
      return grants.revoke(percentDecode(id!)) ? json(200, JSON.stringify({ revoked: true })) : error(404, "no such grant");
    },
  },
];
