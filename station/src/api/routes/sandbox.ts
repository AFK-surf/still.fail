// Execution in sandboxes (src/agents/sandbox.ts): GET says the setting to any member; PUT `{enabled, ssh, identity?,
// knownHosts?, persist?, labels?, warm?}` is for the workspace's owners and admins. Switching on is refused unless a
// sandbox can be had and the station's data directory made there at its path. Kept in config.json (`sandbox`).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { WARM, checkReach, checkSandbox, sandboxConfig, warmUp } from "../../agents/sandbox.ts";

export type SandboxDeps = { config: ConfigFile; changed?: () => void; reach?: typeof checkReach };

const view = (raw: any) => {
  const s = raw?.sandbox;
  if (s === null || typeof s !== "object") return { enabled: false, ssh: null, identity: null, knownHosts: null, persist: null, labels: [], warm: WARM };
  return { enabled: sandboxConfig(raw) !== null, ssh: s.ssh ?? null, identity: s.identity ?? null, knownHosts: s.knownHosts ?? null, persist: s.persist ?? null, labels: Array.isArray(s.labels) ? s.labels : [], warm: typeof s.warm === "number" ? s.warm : WARM };
};

export const routes = ({ config, changed, reach = checkReach }: SandboxDeps): Route[] => [
  { method: "GET", pattern: /^\/sandbox$/, handle: async () => json(200, JSON.stringify(view(config.raw()))) },
  {
    method: "PUT",
    pattern: /^\/sandbox$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins choose where the station runs things");
      let asked: any;
      try {
        asked = JSON.parse(r.body.toString("utf8") || "{}");
      } catch {
        return error(400, "invalid JSON");
      }
      if (asked === null || typeof asked !== "object") return error(400, "a JSON object");
      const next = { ...(config.raw()?.sandbox ?? {}), ...asked };
      try {
        checkSandbox({ sandbox: next });
      } catch (e) {
        return error(400, (e as Error).message);
      }
      const on = sandboxConfig({ sandbox: next });
      if (on !== null) {
        const reached = await reach(on, config.data);
        if (!reached.ok) return error(409, reached.why);
      }
      try {
        config.update((raw) => {
          raw.sandbox = next;
        });
      } catch (e) {
        return error(400, (e as Error).message);
      }
      changed?.();
      // As many warm sandboxes made, or deleted, as it says now.
      void warmUp(config.data);
      return json(200, JSON.stringify(view(config.raw())));
    },
  },
];
