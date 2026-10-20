// The modules beside the station (docs/station-modules.md) as its members see them, and turned on or off by its owners
// and admins without anyone writing config.json: GET /modules, each still.fail makes (modules/catalog.ts) and each
// config.json names, `{id, offered, enabled, installed, running, version}`; PUT /modules/<id> `{enabled}`, the station
// writing config.json itself (a package of the catalog named by its id, or one named turned off or on again), its
// modules then started or stopped as config.json changes (modules/live.ts).
import type { Route } from "../admin.ts";
import { type Request, error, json } from "../request.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { CATALOG } from "../../modules/catalog.ts";
import { type ModuleSet, MODULE_ID } from "../../modules/modules.ts";
import { readInstalled } from "../../modules/packages.ts";
import { join } from "node:path";

export type ModulesDeps = { config: ConfigFile; modules: ModuleSet; changed: () => void };

/// Each module still.fail makes or config.json names, and how it is now.
export function listed(d: ModulesDeps): unknown[] {
  const named: any[] = Array.isArray(d.config.raw()?.modules) ? d.config.raw().modules : [];
  const ids = [...new Set([...CATALOG.map((o) => o.id), ...named.flatMap((m) => (typeof m?.id === "string" ? [m.id] : []))])];
  return ids.map((id) => {
    const entry = named.find((m) => m?.id === id);
    const installed = readInstalled(join(d.modules.dirOf(id), "app"));
    return {
      id,
      offered: CATALOG.some((o) => o.id === id),
      enabled: entry !== undefined && entry.enabled !== false,
      installed: installed.current !== null,
      running: d.modules.get(id)?.running === true,
      version: installed.current === null ? null : `0.1.${installed.current}`,
    };
  });
}

export const routes = (d: ModulesDeps): Route[] => [
  { method: "GET", pattern: /^\/modules$/, handle: async () => json(200, JSON.stringify({ modules: listed(d) })) },
  {
    method: "PUT",
    pattern: /^\/modules\/([^/]+)$/,
    handle: async (r: Request, [id]) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins turn the station's modules on or off");
      if (!MODULE_ID.test(id!)) return error(400, "no such module");
      let enabled: unknown;
      try {
        enabled = JSON.parse(r.body.toString("utf8") || "{}")?.enabled;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof enabled !== "boolean") return error(400, "enabled is true or false");
      const offered = CATALOG.find((o) => o.id === id);
      const named = (Array.isArray(d.config.raw()?.modules) ? d.config.raw().modules : []).some((m: any) => m?.id === id);
      if (!offered && !named) return error(404, "no such module");
      d.config.update((raw) => {
        const list: any[] = Array.isArray(raw.modules) ? raw.modules : (raw.modules = []);
        const entry = list.find((m) => m?.id === id);
        if (entry === undefined) list.push({ id, package: offered!.package });
        else if (enabled) delete entry.enabled;
        else entry.enabled = false;
      });
      d.changed();
      return json(200, JSON.stringify({ modules: listed(d) }));
    },
  },
];
