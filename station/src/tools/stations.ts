// The workspace's other stations, for agents: station_list, station_task, station_file, as tools/remote.ts defines
// them; what they do is the station transport's (src/jobs/remote.ts), reached through the hub's `Remote`. Their answer
// is its JSON, pretty-printed.
import type { Remote } from "../sessions/neighbours.ts";
import type { Tool } from "./mcp.ts";
import { STATION_TOOLS } from "./remote.ts";

/// The tools, on `remote` (a function: the transport is made after the tools, and may be none yet).
export function stationTools(remote: () => Remote | null): Tool[] {
  return STATION_TOOLS.map((definition) => ({
    ...definition,
    run: async (session: string, args: Record<string, any>) => {
      const r = remote();
      if (!r) throw new Error("other stations cannot be reached from this one yet");
      return JSON.stringify(await r.tool(definition.name as "station_list" | "station_task" | "station_file", session, args), null, 2);
    },
  }));
}
