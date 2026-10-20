// The variables everything the station starts for its agents runs with (ops/agent-env.ts, config.json `agentEnv`): the
// overview says them to any member (values that say too much masked); PUT /agent-env changes them, for the workspace's
// owners and admins: `{text}`, all of them as a .env file's lines (a secret left as shown, masked, is kept), or `{env}`, a
// patch (a string sets one, null removes it, one left out stays). The sessions' processes take them now if idle, else
// before their next turn.
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";
import { ENV_NAME, type EnvLineError, MOST_VALUE, MOST_VARS, agentEnv, maskValue, parseEnvText, secretValue } from "../../ops/agent-env.ts";

export type AgentEnvDeps = { config: ConfigFile; changed?: () => void; restart?: () => void };

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/// The variables as the pages show them, by name: a secret's value masked.
export function agentEnvView(raw: unknown): { key: string; value: string; secret: boolean }[] {
  return Object.entries(agentEnv(raw))
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, value]) => (secretValue(key, value) ? { key, value: maskValue(value), secret: true } : { key, value, secret: false }));
}

/// A line refused, in the asker's words.
function refusal(lang: Lang, e: EnvLineError): string {
  if (e.why === "tooMany") return tr(lang, "station.agentEnv.tooMany", { most: MOST_VARS });
  if (e.why === "badName") return tr(lang, "station.agentEnv.badName", { line: e.line, name: e.name ?? "" });
  if (e.why === "tooLong") return tr(lang, "station.agentEnv.tooLong", { line: e.line, most: MOST_VALUE });
  return tr(lang, "station.agentEnv.notPair", { line: e.line });
}

export const routes = ({ config, changed, restart }: AgentEnvDeps): Route[] => [
  {
    method: "PUT",
    pattern: /^\/agent-env$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.agentEnv.managersOnly"));
      let body: Record<string, unknown>;
      try {
        const parsed = JSON.parse(r.body.toString("utf8") || "{}");
        body = isObject(parsed) ? parsed : {};
      } catch {
        return error(400, "invalid JSON");
      }
      const before = agentEnv(config.raw());
      // As written (`text`, a .env file's lines): all of them, a secret left masked kept as it was; else a patch (`env`).
      let next: Record<string, string>;
      if (typeof body.text === "string") {
        const read = parseEnvText(body.text, before);
        if ("why" in read) return error(400, refusal(r.lang, read as EnvLineError));
        next = read;
      } else if (isObject(body.env)) {
        next = { ...before };
        for (const [key, value] of Object.entries(body.env)) {
          if (!ENV_NAME.test(key)) return error(400, `invalid environment variable name ${key}`);
          if (value === null) delete next[key];
          else if (typeof value === "string") next[key] = value;
          else return error(400, `env.${key}: a string, or null to remove it`);
        }
      } else return error(400, "text: the variables as NAME=value lines; or env: a map of variables to a value, or null to remove one");
      try {
        config.update((raw) => {
          if (Object.keys(next).length > 0) raw.agentEnv = next;
          else delete raw.agentEnv;
        });
      } catch (e) {
        return error(400, (e as Error).message);
      }
      const after = agentEnv(config.raw());
      if (JSON.stringify(after) !== JSON.stringify(before)) {
        log.info("agent-env", "the agents' variables changed", { names: Object.keys(after), by: r.viewer.email });
        restart?.();
      }
      changed?.();
      return json(200, JSON.stringify({ env: agentEnvView(config.raw()) }));
    },
  },
];
