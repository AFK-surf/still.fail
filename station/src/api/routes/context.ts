// How the station goes on with a session whose prompt cache is over (config.json `afreshWhenCold`), unless its chat
// chose otherwise (sessions `afresh`, session.settings): a message or notice to an agent, its large context's cache
// over, starts it afresh (its context cleared, told to read back what it needs) rather than send all of it again at
// full price. The overview says it to any member (`context`); PUT
// /context/settings `{afreshWhenCold}` changes it, for the workspace's owners and admins.
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";

export type ContextDeps = { config: ConfigFile; changed?: () => void };

/// The setting as the overview says it.
export const contextView = (raw: unknown): { afreshWhenCold: boolean } => ({ afreshWhenCold: (raw as { afreshWhenCold?: unknown } | null)?.afreshWhenCold === true });

export const routes = ({ config, changed }: ContextDeps): Route[] => [
  {
    method: "PUT",
    pattern: /^\/context\/settings$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.context.managersOnly"));
      let on: unknown;
      try {
        on = JSON.parse(r.body.toString("utf8") || "{}")?.afreshWhenCold;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof on !== "boolean") return error(400, "afreshWhenCold is true or false");
      config.update((raw) => {
        if (on) raw.afreshWhenCold = true;
        else delete raw.afreshWhenCold;
      });
      log.info("context", "going on afresh once a cache is over set", { on, by: r.viewer.email });
      changed?.();
      return json(200, JSON.stringify(contextView(config.raw())));
    },
  },
];
