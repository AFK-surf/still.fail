// The workspaces the station is in (docs/multi-workspace.md): GET lists them, to its home workspace's owners and admins
// all of them, to anyone else only their own; POST /workspaces/join `{token}` (one-time, from the workspace to join) has
// it join one more, staying in those it is in: for its home workspace's owners and admins. `lock`: that workspace's
// lock's head as the asking device has it, which the station pins there (a locked station joins locked ones only).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { Cloud } from "../../cloud/state.ts";
import { joinWorkspace } from "../../cli.ts";

export type WorkspacesDeps = { cloud: Cloud; data: string; changed?: () => void };

const view = (cloud: Cloud, r: Request) => ({
  workspaces: cloud
    .memberships()
    .filter((m) => managesStation(r.viewer) || m.workspace === r.viewer.workspace)
    .map((m) => ({ workspace: m.workspace, workspaceName: m.workspace_name, name: m.name, home: m.home })),
  // Whether it may join more (a locked one: locked workspaces only).
  canJoin: managesStation(r.viewer),
});

export const routes = ({ cloud, data, changed }: WorkspacesDeps): Route[] => [
  { method: "GET", pattern: /^\/workspaces$/, handle: async (r: Request) => json(200, JSON.stringify(view(cloud, r))) },
  {
    method: "POST",
    pattern: /^\/workspaces\/join$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, "only the owners and admins of this station's home workspace add it to another workspace");
      let token: unknown;
      let lock: unknown;
      try {
        ({ token, lock } = JSON.parse(r.body.toString("utf8") || "{}") ?? {});
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof token !== "string" || token === "") return error(400, "token is required");
      if (lock !== undefined && lock !== null && (typeof lock !== "string" || !/^[0-9a-f]{64}$/.test(lock))) return error(400, "lock: a lock's hash");
      try {
        const joined = await joinWorkspace(data, token, typeof lock === "string" ? lock : undefined);
        cloud.reload();
        changed?.();
        return json(200, JSON.stringify({ joined: { workspace: joined.workspace, workspaceName: joined.workspace_name, name: joined.name }, ...view(cloud, r) }));
      } catch (e) {
        return error(409, (e as Error).message);
      }
    },
  },
];
