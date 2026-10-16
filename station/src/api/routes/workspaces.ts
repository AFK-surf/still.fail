// The workspaces the station is in (docs/multi-workspace.md): GET lists them, to its home workspace's owners and admins
// all of them, to anyone else only their own; POST /workspaces/join `{token}` (one-time, from the workspace to join) has
// it join one more, staying in those it is in: for its home workspace's owners and admins.
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
  // Whether it may join more: not while a workspace lock holds it to one.
  canJoin: managesStation(r.viewer) && cloud.locked() === null,
});

export const routes = ({ cloud, data, changed }: WorkspacesDeps): Route[] => [
  { method: "GET", pattern: /^\/workspaces$/, handle: async (r: Request) => json(200, JSON.stringify(view(cloud, r))) },
  {
    method: "POST",
    pattern: /^\/workspaces\/join$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, "only the owners and admins of this station's home workspace add it to another workspace");
      let token: unknown;
      try {
        token = JSON.parse(r.body.toString("utf8") || "{}")?.token;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof token !== "string" || token === "") return error(400, "token is required");
      try {
        const joined = await joinWorkspace(data, token);
        cloud.reload();
        changed?.();
        return json(200, JSON.stringify({ joined: { workspace: joined.workspace, workspaceName: joined.workspace_name, name: joined.name }, ...view(cloud, r) }));
      } catch (e) {
        return error(409, (e as Error).message);
      }
    },
  },
];
