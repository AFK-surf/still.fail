// An operator's network choices (the congestion controller, the relays' UDP way). Saved now, read by the mesh on the
// next station start. A request sets what it names.
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
    let body: any;
    try { body = JSON.parse(r.body.toString("utf8")); }
    catch { return error(400, "invalid JSON"); }
    const set: { congestion?: "cubic" | "bbr"; relayUdp?: boolean } = {};
    if (body !== null && typeof body === "object" && "congestion" in body) {
      if (body.congestion !== "cubic" && body.congestion !== "bbr") return error(400, "congestion: expected cubic or bbr");
      set.congestion = body.congestion;
    }
    if (body !== null && typeof body === "object" && "relayUdp" in body) {
      if (typeof body.relayUdp !== "boolean") return error(400, "relayUdp: expected a boolean");
      set.relayUdp = body.relayUdp;
    }
    if (Object.keys(set).length === 0) return error(400, "expected congestion or relayUdp");
    config.update((raw) => { raw.network = { ...raw.network, ...set }; });
    changed?.();
    return json(200, JSON.stringify(networkView(config.raw())));
  },
}];
