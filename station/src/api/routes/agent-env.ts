// The variables everything the station starts for its agents runs with (ops/agent-env.ts, config.json `agentEnv`): the
// overview says them to any member (values that say too much masked); PUT /agent-env `{env}` changes them, for the
// workspace's owners and admins. As with a profile's variables, a string sets one, null removes it, one left out stays
// (so a masked value survives an edit). The sessions' processes take them now if idle, else before their next turn.
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";
import { ENV_NAME, agentEnv, secretValue } from "../../ops/agent-env.ts";
import { mask } from "../../accounts/index.ts";

export type AgentEnvDeps = { config: ConfigFile; changed?: () => void; restart?: () => void };

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/// The variables as the pages show them, by name: a secret's value masked.
export function agentEnvView(raw: unknown): { key: string; value: string; secret: boolean }[] {
  return Object.entries(agentEnv(raw))
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, value]) => (secretValue(key, value) ? { key, value: mask(value), secret: true } : { key, value, secret: false }));
}

export const routes = ({ config, changed, restart }: AgentEnvDeps): Route[] => [
  {
    method: "PUT",
    pattern: /^\/agent-env$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.share.managersOnly"));
      let asked: unknown;
      try {
        asked = JSON.parse(r.body.toString("utf8") || "{}")?.env;
      } catch {
        return error(400, "invalid JSON");
      }
      if (!isObject(asked)) return error(400, "env: a map of variables to a value, or null to remove one");
      for (const [key, value] of Object.entries(asked)) {
        if (!ENV_NAME.test(key)) return error(400, `invalid environment variable name ${key}`);
        if (value !== null && typeof value !== "string") return error(400, `env.${key}: a string, or null to remove it`);
      }
      const before = JSON.stringify(agentEnv(config.raw()));
      try {
        config.update((raw) => {
          const env: Record<string, unknown> = isObject(raw.agentEnv) ? { ...raw.agentEnv } : {};
          for (const [key, value] of Object.entries(asked)) {
            if (value === null) delete env[key];
            else env[key] = value;
          }
          if (Object.keys(env).length > 0) raw.agentEnv = env;
          else delete raw.agentEnv;
        });
      } catch (e) {
        return error(400, (e as Error).message);
      }
      const after = agentEnv(config.raw());
      if (JSON.stringify(after) !== before) {
        log.info("agent-env", "the agents' variables changed", { names: Object.keys(after), by: r.viewer.email });
        restart?.();
      }
      changed?.();
      return json(200, JSON.stringify({ env: agentEnvView(config.raw()) }));
    },
  },
];
