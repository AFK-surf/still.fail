// A chat's way to the station's browser (docs/remote-screens.md, "A chat's own environment"): a WebSocket on the agents'
// door, ws://127.0.0.1:<door>/browser/<the session's key, base64url>, to the DevTools of the station's one Chrome
// through a gate (gate.ts) that lets the session reach only its chat's own browser context: its tabs, its cookies.
// Nothing asked on it brings the browser in front of what the person at the machine is doing: each tab asked for is
// opened in a window of its own, behind the others, and a tab asked to be brought forward is answered as done and left
// where it is. The address stays when Chrome is started again or another station process takes the door: a client that
// lost its connection connects to the same one again.
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Duplex } from "node:stream";
import WebSocket, { type RawData, WebSocketServer } from "ws";
import { wall } from "../ops/fibers.ts";
import type { DoorRoute } from "../parts.ts";
import { refuseUpgrade } from "../tools/http.ts";
import { Gate, type GateParts } from "./gate.ts";

export { BEHIND } from "./gate.ts";
export const PREFIX = "browser";
/// The largest message passed either way (a screenshot of a large page is big).
const MAX = 256 * 1024 * 1024;
/// How long the browser's DevTools are given to take the connection (Chrome's time: the machine's clock).
const OPEN_MS = 10_000;

/// Where `session` reaches the browser, after the door's origin (`http://127.0.0.1:<port>`).
export function sessionPath(session: string): string {
  return `/${PREFIX}/${Buffer.from(session, "utf8").toString("base64url")}`;
}

/// The session a door path names; null when it names none.
export function sessionOfPath(url: string): string | null {
  const m = /^\/browser\/([A-Za-z0-9_-]+)\/?(?:\?.*)?$/.exec(url);
  if (m === null) return null;
  const session = Buffer.from(m[1]!, "base64url").toString("utf8");
  return session !== "" && sessionPath(session) === `/${PREFIX}/${m[1]}` ? session : null;
}

/// What the door asks of the browsers (browsers.ts Browsers): for a session, the browser's DevTools (started if it is
/// not running) and its chat's context there.
export type DoorBrowsers = {
  open(session: string): Promise<{ ws: string; gate: GateParts }>;
};

/// The browser's route on the agents' door.
export function browserDoor(browser: DoorBrowsers): DoorRoute {
  const server = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: MAX });
  return {
    prefix: PREFIX,
    async request(_req: IncomingMessage, res: ServerResponse) {
      res.writeHead(400, { "content-type": "text/plain; charset=utf-8" }).end("The station's browser is a WebSocket here: give this address to chrome-devtools-mcp --wsEndpoint or Playwright's connectOverCDP.");
    },
    async upgrade(req: IncomingMessage, socket: Duplex, head: Buffer) {
      const session = sessionOfPath(req.url ?? "");
      if (session === null) return refuseUpgrade(socket, 404, "the station's browser is /browser/<session>, as the browser tool gives it");
      let opened: { ws: string; gate: GateParts };
      try {
        opened = await browser.open(session);
      } catch (e) {
        return refuseUpgrade(socket, 503, `the station's browser could not be started: ${(e as Error).message}`);
      }
      const upstream = new WebSocket(opened.ws, { perMessageDeflate: false, maxPayload: MAX });
      try {
        await wall.within(OPEN_MS, new Promise<void>((resolve, reject) => {
          upstream.once("open", () => resolve());
          upstream.once("error", reject);
        }), "the browser's DevTools did not answer");
      } catch (e) {
        upstream.terminate();
        return refuseUpgrade(socket, 502, (e as Error).message);
      }
      server.handleUpgrade(req, socket, head, (client) => pass(client, upstream, new Gate(opened.gate)));
    },
  };
}

/// Both ways through `gate`, until either side ends.
export function pass(client: WebSocket, upstream: WebSocket, gate: Gate) {
  const up = (texts: string[]) => {
    if (upstream.readyState === WebSocket.OPEN) for (const t of texts) upstream.send(t);
  };
  const down = (texts: string[]) => {
    if (client.readyState === WebSocket.OPEN) for (const t of texts) client.send(t);
  };
  client.on("message", (data, binary) => {
    // DevTools speaks text; anything else is not let through.
    if (binary) return;
    const passed = gate.fromClient(data.toString());
    up(passed.up);
    down(passed.down);
  });
  upstream.on("message", (data, binary) => {
    if (!binary) {
      const text = data.toString();
      if (gate.wants(text)) {
        const passed = gate.fromChrome(text);
        up(passed.up);
        down(passed.down);
        return;
      }
    }
    if (client.readyState === WebSocket.OPEN) client.send(data, { binary });
  });
  const end = () => {
    for (const ws of [client, upstream]) {
      if (ws.readyState === WebSocket.OPEN) ws.close();
      else if (ws.readyState === WebSocket.CONNECTING) ws.terminate();
    }
  };
  for (const ws of [client, upstream]) {
    ws.on("close", end);
    ws.on("error", end);
  }
}
