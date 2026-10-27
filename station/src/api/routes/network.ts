// An operator's congestion controller choice. Saved now, read by the mesh on the next station start.
import { error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { managesStation } from "../../mesh/credential.ts";
import { networkView } from "../../mesh/settings.ts";
import { tr } from "../../ops/i18n.ts";

export const routes = ({ config, changed }: { config: ConfigFile; changed?: () => void }): Route[] => [{
  method: "PUT",
  pattern: /^\/network\/settings$/,
  handle: async (r) => {
    if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.network.managersOnly"));
    let congestion: unknown;
    try { congestion = JSON.parse(r.body.toString("utf8"))?.congestion; }
    catch { return error(400, "invalid JSON"); }
    if (congestion !== "cubic" && congestion !== "bbr") return error(400, "congestion: expected cubic or bbr");
    config.update((raw) => { raw.network = { ...raw.network, congestion }; });
    changed?.();
    return json(200, JSON.stringify(networkView(config.raw())));
  },
}];
