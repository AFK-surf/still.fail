// Whether the station sends its log to still.fail (ops/log-export.ts; config.json `telemetry.logs`, on unless false):
// scrubbed, for what goes wrong between stations or with still.fail to be found from our side. The overview says it to
// any member (`diagnostics`); PUT /diagnostics/settings `{logs}` changes it, for the workspace's owners and admins.
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";

export type DiagnosticsDeps = { config: ConfigFile; changed?: () => void };

/// The setting as the overview says it.
export const diagnosticsView = (raw: unknown): { logs: boolean } => ({ logs: (raw as { telemetry?: { logs?: unknown } } | null)?.telemetry?.logs !== false });

export const routes = ({ config, changed }: DiagnosticsDeps): Route[] => [
  {
    method: "PUT",
    pattern: /^\/diagnostics\/settings$/,
    handle: async (r: Request): Promise<Answer> => {
      if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.context.managersOnly"));
      let on: unknown;
      try {
        on = JSON.parse(r.body.toString("utf8") || "{}")?.logs;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof on !== "boolean") return error(400, "logs is true or false");
      config.update((raw) => {
        const telemetry = raw.telemetry !== null && typeof raw.telemetry === "object" ? { ...raw.telemetry } : {};
        if (on) delete telemetry.logs;
        else telemetry.logs = false;
        if (Object.keys(telemetry).length > 0) raw.telemetry = telemetry;
        else delete raw.telemetry;
      });
      // Said before it stops: the last line sent says who turned it off.
      log.info("diagnostics", "sending the station's log set", { on, by: r.viewer.email });
      changed?.();
      return json(200, JSON.stringify(diagnosticsView(config.raw())));
    },
  },
];
