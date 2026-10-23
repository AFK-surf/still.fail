// The station's browser as each session reaches it (docs/remote-screens.md, "Whose a tab is"): a WebSocket on the
// agents' door, ws://127.0.0.1:<door>/browser/<the session's key, base64url>, passed through to the browser's DevTools
// as it is. What goes by tells which tabs the session opens: a Target.createTarget asked on it, and the targetId its
// answer gives (a tab one of those opens is the session's too: tabs.ts). The address stays when Chrome is started again
// or another station process takes the door: a client that lost its connection connects to the same one again.
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Duplex } from "node:stream";
import WebSocket, { type RawData, WebSocketServer } from "ws";
import { wall } from "../ops/fibers.ts";
import type { DoorRoute } from "../parts.ts";
import { refuseUpgrade } from "../tools/http.ts";
import type { StationBrowser } from "./browser.ts";

export const PREFIX = "browser";
/// The largest message passed either way (a screenshot of a large page is big).
const MAX = 256 * 1024 * 1024;
/// How long the browser's DevTools are given to take the connection (Chrome's time: the machine's clock).
const OPEN_MS = 10_000;
/// An answer longer than this is no Target.createTarget's: it is passed on unread.
const ANSWER_MAX = 4096;

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

/// The browser's route on the agents' door.
export function browserDoor(browser: StationBrowser): DoorRoute {
  const server = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: MAX });
  return {
    prefix: PREFIX,
    async request(_req: IncomingMessage, res: ServerResponse) {
      res.writeHead(400, { "content-type": "text/plain; charset=utf-8" }).end("The station's browser is a WebSocket here: give this address to chrome-devtools-mcp --wsEndpoint or Playwright's connectOverCDP.");
    },
    async upgrade(req: IncomingMessage, socket: Duplex, head: Buffer) {
      const session = sessionOfPath(req.url ?? "");
      if (session === null) return refuseUpgrade(socket, 404, "the station's browser is /browser/<session>, as the browser tool gives it");
      let ws: string;
      try {
        const status = await browser.endpoint();
        if (status.ws === undefined) throw new Error("it has no DevTools address");
        ws = status.ws;
      } catch (e) {
        return refuseUpgrade(socket, 503, `the station's browser could not be started: ${(e as Error).message}`);
      }
      const upstream = new WebSocket(ws, { perMessageDeflate: false, maxPayload: MAX });
      try {
        await wall.within(OPEN_MS, new Promise<void>((resolve, reject) => {
          upstream.once("open", () => resolve());
          upstream.once("error", reject);
        }), "the browser's DevTools did not answer");
      } catch (e) {
        upstream.terminate();
        return refuseUpgrade(socket, 502, (e as Error).message);
      }
      server.handleUpgrade(req, socket, head, (client) => pass(client, upstream, (targetId) => browser.own(targetId, session)));
    },
  };
}

/// Both ways, as they come, until either side ends; `opened`: a tab this connection asked for.
export function pass(client: WebSocket, upstream: WebSocket, opened: (targetId: string) => void) {
  // The Target.createTarget asked and not answered yet, by the target session they were asked on and their id.
  const asked = new Set<string>();
  const key = (session: unknown, id: unknown) => `${typeof session === "string" ? session : ""}\0${String(id)}`;
  const parsed = (data: RawData): any => {
    try {
      return JSON.parse(data.toString());
    } catch {
      return null;
    }
  };
  client.on("message", (data, binary) => {
    if (!binary && data.toString().includes('"Target.createTarget"')) {
      const m = parsed(data);
      if (m?.method === "Target.createTarget" && m.id !== undefined) asked.add(key(m.sessionId, m.id));
    }
    if (upstream.readyState === WebSocket.OPEN) upstream.send(data, { binary });
  });
  upstream.on("message", (data, binary) => {
    if (!binary && asked.size > 0 && byteLength(data) <= ANSWER_MAX) {
      const m = parsed(data);
      if (m?.id !== undefined && asked.delete(key(m.sessionId, m.id)) && typeof m.result?.targetId === "string") opened(m.result.targetId);
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

function byteLength(data: RawData): number {
  return Array.isArray(data) ? data.reduce((n, b) => n + b.length, 0) : data instanceof ArrayBuffer ? data.byteLength : data.length;
}
