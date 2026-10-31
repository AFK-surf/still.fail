// How the station goes on with a session whose prompt cache is over (config.json `afreshWhenCold` and `afreshAbove`),
// unless its chat chose otherwise (sessions `afresh`, session.settings): at the estimated USD threshold a message or
// notice starts it afresh, told to read back what it needs. An unknown price does not trigger a positive threshold;
// zero instead means every expired cache, even when its price is unknown.
// The overview says both settings to members; owners and admins may PUT either to /context/settings.
import { type Answer, type Request, error, json } from "../request.ts";
import { afreshThreshold, DEFAULT_AFRESH_ABOVE } from "../../../../client/core-ts/src/cache-policy.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";

export type ContextDeps = { config: ConfigFile; changed?: () => void };

/// The setting as the overview says it.
export const contextView = (raw: unknown): { afreshWhenCold: boolean; afreshAbove: number } => {
  const settings = raw as { afreshWhenCold?: unknown; afreshAbove?: unknown } | null;
  return { afreshWhenCold: settings?.afreshWhenCold === true, afreshAbove: afreshThreshold(settings?.afreshAbove) };
};

export const routes = ({ config, changed }: ContextDeps): Route[] => [
  {
    method: "PUT",
    pattern: /^\/context\/settings$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.context.managersOnly"));
      let settings: { afreshWhenCold?: unknown; afreshAbove?: unknown };
      try {
        const parsed: unknown = JSON.parse(r.body.toString("utf8") || "{}");
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return error(400, "expected an object");
        settings = parsed as typeof settings;
      } catch {
        return error(400, "invalid JSON");
      }
      const { afreshWhenCold: on, afreshAbove: above } = settings;
      if (on === undefined && above === undefined) return error(400, "no context setting given");
      if (on !== undefined && typeof on !== "boolean") return error(400, "afreshWhenCold is true or false");
      if (above !== undefined && (typeof above !== "number" || !Number.isFinite(above) || above < 0)) return error(400, "afreshAbove is a nonnegative amount in USD");
      config.update((raw) => {
        if (on !== undefined) {
          if (on) raw.afreshWhenCold = true;
          else delete raw.afreshWhenCold;
        }
        if (above !== undefined) {
          if (above === DEFAULT_AFRESH_ABOVE) delete raw.afreshAbove;
          else raw.afreshAbove = above;
        }
      });
      log.info("context", "going on afresh once a cache is over set", { on, above, by: r.viewer.email });
      changed?.();
      return json(200, JSON.stringify(contextView(config.raw())));
    },
  },
];
