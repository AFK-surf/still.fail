// An operator's network choice (the congestion controller). Saved, and taken by the running mesh as saved (mesh.ts
// applyNetwork); a station started again (below) has it from its start. The relays' UDP way, a choice until
// 2026-10-30, is no more: a client from before that still sets it is answered as if it did, nothing saved.
import { error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { managesStation } from "../../mesh/credential.ts";
import { networkView } from "../../mesh/settings.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";

export const routes = ({ config, changed, restart }: { config: ConfigFile; changed?: () => void; restart?: () => (() => Promise<void>) | null }): Route[] => [{
  method: "PUT",
  pattern: /^\/network\/settings$/,
  handle: async (r) => {
    if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.network.managersOnly"));
    let body: any;
    try { body = JSON.parse(r.body.toString("utf8")); }
    catch { return error(400, "invalid JSON"); }
    const set: { congestion?: "cubic" | "bbr" } = {};
    if (body !== null && typeof body === "object" && "congestion" in body) {
      if (body.congestion !== "cubic" && body.congestion !== "bbr") return error(400, "congestion: expected cubic or bbr");
      set.congestion = body.congestion;
    }
    if (Object.keys(set).length === 0) {
      if (body !== null && typeof body === "object" && typeof body.relayUdp === "boolean") return json(200, JSON.stringify(networkView(config.raw())));
      return error(400, "expected congestion");
    }
    config.update((raw) => { raw.network = { ...raw.network, ...set }; });
    changed?.();
    return json(200, JSON.stringify(networkView(config.raw())));
  },
}, {
  // The station started again (ops/restart.ts): its launcher hands over to a new process.
  method: "POST",
  pattern: /^\/station\/restart$/,
  handle: async (r) => {
    if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.restart.managersOnly"));
    const go = restart?.() ?? null;
    if (go === null) return error(409, tr(r.lang, "station.restart.cannot"));
    log.info("restart", "asked from the station's page", { by: r.viewer.email });
    // The old process serves on (this answer too) until the new one has taken over.
    await go();
    return json(202, JSON.stringify({ restarting: true }));
  },
}];
