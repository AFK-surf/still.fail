// peer_forward: a port of another station of the workspace forwarded to this machine, as `ssh -L` does
// (mesh/peer-forward.ts). One tool: with station and port it opens one, with close it closes one, with nothing it lists
// the session's.
import type { Forwards } from "../mesh/peer-forward.ts";
import type { Tool } from "./mcp.ts";

export const PEER_FORWARD_DESCRIPTION =
  "Forward a TCP port of another station of this workspace to this machine, like `ssh -L`: a listener on 127.0.0.1:<local_port> here whose connections reach localhost:<port> on that station (it tries 127.0.0.1 and [::1] there, as a local client would), bytes passed as they are. Use it for anything a browser or a non-HTTP client uses: web pages and dev servers (absolute paths, client routing, redirects, cookies, HMR and other WebSockets work as on that machine), databases (postgres, redis), a Chrome's DevTools port. For a program that only calls an HTTP API with a base URL, $STILLFAIL_PEER_HTTP/<station>/<port> needs no forward. local_port defaults to the same number when it is free here, else another (the answer says which). A forward is this session's: it closes when this chat is archived or deleted, when the job given as job ends, after 30 minutes with no connection, or when this station restarts (none survives a restart: open it again). With close: <local_port>, closes that one. With no arguments, lists this session's forwards, saying whether each one's station is online. A station from before forwarding is reported as needing an update.";

/// The tool, on the station's forwards.
export function forwardTools(forwards: Forwards): Tool[] {
  return [
    {
      name: "peer_forward",
      description: PEER_FORWARD_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          station: { type: "string", description: "The station: its name from station_list (any case), or its id." },
          port: { type: "integer", minimum: 1, maximum: 65535, description: "The port on that station's localhost." },
          local_port: { type: "integer", minimum: 1, maximum: 65535, description: "Where here (127.0.0.1); default the same as port when free, else any free one." },
          job: { type: "string", description: "One of your jobs (job_start's id): the forward closes when it ends." },
          close: { type: "integer", minimum: 1, maximum: 65535, description: "A forward's local port: closes it." },
        },
        additionalProperties: false,
      },
      run: async (session, args) => {
        const int = (key: string): number | undefined => {
          const v = args[key];
          if (v === undefined || v === null) return undefined;
          if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 65535) throw new Error(`${key}: a port, 1 to 65535`);
          return v;
        };
        const close = int("close");
        const station = typeof args.station === "string" ? args.station.trim() : "";
        const port = int("port");
        if (close !== undefined) {
          if (station !== "" || port !== undefined) throw new Error("close takes no station or port");
          const was = forwards.remove(session, close);
          return `Closed ${was.local} (to ${was.station}:${was.port}).`;
        }
        if (station === "" && port === undefined) {
          const list = await forwards.list(session);
          return list.length === 0 ? "No forwarded ports." : JSON.stringify(list, null, 2);
        }
        if (station === "" || port === undefined) throw new Error("give both station and port to forward one (none: list them; close: close one)");
        const job = typeof args.job === "string" && args.job.trim() !== "" ? args.job.trim() : undefined;
        return JSON.stringify(await forwards.open(session, station, port, int("local_port"), job), null, 2);
      },
    },
  ];
}
