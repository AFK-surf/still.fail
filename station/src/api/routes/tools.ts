// How far the control plane's gateway may go on this machine (the device tools, src/device/tools.ts): GET says it to
// any member; PUT `{access}` (off | read | full) is for the workspace's owners and admins. Kept in config.json
// (`tools.access`).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { ACCESS, type Access, READ_OPS, accessOf } from "../../device/tools.ts";

export type ToolsDeps = { config: ConfigFile; changed?: () => void };

const manages = (r: Request) => r.viewer.role === "owner" || r.viewer.role === "admin";

/// What each level means, for the pages that set it.
export const ABOUT: Record<Access, string> = {
  off: "The control plane's agents cannot use this machine.",
  read: "Agents can read every file this machine's user can read, except the station's own data, and see processes, runtimes and chat states.",
  full: "Agents can also run commands, write files, manage processes and start chats as this machine's user.",
};

const view = (access: Access) => ({ access, levels: ACCESS, read_ops: READ_OPS, about: ABOUT });

export const routes = ({ config, changed }: ToolsDeps): Route[] => [
  { method: "GET", pattern: /^\/tools\/access$/, handle: async () => json(200, JSON.stringify(view(accessOf(config.raw())))) },
  {
    method: "PUT",
    pattern: /^\/tools\/access$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!manages(r)) return error(403, "only the workspace's owners and admins set the device tools' access");
      let asked: unknown;
      try {
        asked = JSON.parse(r.body.toString("utf8") || "{}")?.access;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof asked !== "string" || !ACCESS.includes(asked as Access)) return error(400, `access is one of ${ACCESS.join(", ")}`);
      try {
        config.update((raw) => {
          raw.tools = { ...(raw.tools !== null && typeof raw.tools === "object" ? raw.tools : {}), access: asked };
        });
      } catch (e) {
        return error(400, (e as Error).message);
      }
      changed?.();
      return json(200, JSON.stringify(view(asked as Access)));
    },
  },
];
