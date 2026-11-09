import { GIB, type WorkspaceWatch } from "../jobs/workspace-size.ts";
import type { Remote } from "../jobs/remote.ts";
import type { Tool } from "./mcp.ts";

/// The MCP token supplies the chat: a caller can change only its own workspace's limit on a station it has used.
export function workspaceSizeTools(watch: WorkspaceWatch, remote: Remote): Tool[] {
  return [{
    name: "workspace_limit",
    description: "Read or change this chat's soft workspace-size limit on one station. Omit station for this station; name a station this chat has used for its remote workspace there. The default is 10 GiB. When a working chat exceeds its limit, the station tells its agent and repeats hourly until it cleans up or raises the limit; it never deletes files or stops work for this. Give limit_gib to set a positive whole number of GiB, or omit it to read the current limit.",
    inputSchema: {
      type: "object",
      properties: {
        station: { type: "string", description: "The station's name or id; omit for this station." },
        limit_gib: { type: "integer", minimum: 1, description: "New soft limit in whole GiB; omit to read it." },
      },
      additionalProperties: false,
    },
    run: async (session, args) => {
      const named = typeof args.station === "string" ? args.station.trim() : "";
      const station = await remote.workspaceStation(session, named);
      if (args.limit_gib !== undefined) {
        if (typeof args.limit_gib !== "number") throw new Error("limit_gib must be a positive whole number of GiB");
        watch.setLimit(session, station, args.limit_gib);
      }
      return JSON.stringify({ station: station || "this station", limit_gib: watch.limit(session, station) / GIB });
    },
  }];
}
