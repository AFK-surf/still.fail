// Web services of another station through this one's agents' door (mesh/peer-http.ts) over real iroh on this machine:
// which protocol two endpoints agree on (a station offering both its own and the station transport's is answered in its
// own by a new station, in the transport's by one from before), bodies both ways, an event stream, a WebSocket. Real
// sockets and real time, so it runs beside the checks (`pnpm test:side`); test/peer-http.test.ts covers the rest in memory.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import WebSocket, { WebSocketServer } from "ws";
import { Cloud } from "../src/cloud/state.ts";
import { loadMesh } from "../src/mesh/native.ts";
import { PEER_HTTP_ALPN, PeerHttp, serveHttp } from "../src/mesh/peer-http.ts";
import { PEER_ALPN } from "../src/mesh/peer.ts";
import { ALPN, FORMER_ALPN } from "../src/mesh/serve.ts";
import { openAgentsDoor } from "../src/tools/http.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";

const cloudOf = (station: string, peers: { id: string; name: string }[]): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name: "", station, peers, revocations: [], joined: [] },
    lock: null,
    peersCurrent: true,
    listeners: new Set(),
    relays: () => [],
  });

test("over real iroh: a new station is asked in its own protocol, an old one is told; requests and sockets go both ways", async () => {
  const mesh = loadMesh();
  const bind = (alpns: Buffer[]) => mesh.bind({ secretKey: randomBytes(32), alpns, relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  // As mesh.ts binds a station: the members' protocols first.
  const [here, there, old] = await Promise.all([bind([PEER_HTTP_ALPN, PEER_ALPN]), bind([ALPN, FORMER_ALPN, PEER_HTTP_ALPN, PEER_ALPN]), bind([ALPN, FORMER_ALPN, PEER_ALPN])]);
  const roster = [{ id: here.id(), name: "here" }, { id: there.id(), name: "there" }, { id: old.id(), name: "old" }];
  const thereCloud = cloudOf(there.id(), roster);
  for (const endpoint of [there, old]) {
    void (async () => {
      for (;;) {
        const conn = await endpoint.accept();
        if (!conn) return;
        if (conn.alpn().equals(PEER_HTTP_ALPN)) void serveHttp(conn, thereCloud).catch(() => conn.close(0, "refused"));
      }
    })();
  }
  const sockets = new Map([there, old].map((e) => [e.id(), e.sockets().filter((s) => s.startsWith("127.0.0.1:"))]));
  const http = new PeerHttp(here, cloudOf(here.id(), roster), (id) => ({ id, ips: sockets.get(id) }));
  const door = await openAgentsDoor({ port: 0 }, new McpEndpoint(() => undefined, []), () => ({ status: 400, body: {} }), () => http);
  const web = createServer((req, res) => {
    if (req.url === "/echo") {
      const hash = createHash("sha256");
      req.on("data", (c) => hash.update(c));
      req.on("end", () => res.end(hash.digest("hex")));
    } else if (req.url === "/events") {
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.write("data: first\n\n");
    } else res.end("hello");
  });
  await new Promise<void>((r) => web.listen(0, "127.0.0.1", r));
  const port = (web.address() as AddressInfo).port;
  const wss = new WebSocketServer({ port: 0, host: "127.0.0.1" });
  await new Promise((r) => wss.once("listening", r));
  wss.on("connection", (ws) => ws.on("message", (data, binary) => ws.send(data, { binary })));
  const base = `http://127.0.0.1:${door.port}/peer`;
  try {
    assert.equal(await (await fetch(`${base}/there/${port}/`)).text(), "hello");
    const old502 = await fetch(`${base}/old/${port}/`);
    assert.equal(old502.status, 502);
    assert.match(await old502.text(), /needs an update/);
    const body = randomBytes(16 * 1024 * 1024);
    assert.equal(await (await fetch(`${base}/there/${port}/echo`, { method: "POST", body })).text(), createHash("sha256").update(body).digest("hex"));
    // The event stream's first event, while the service still holds it open.
    const events = await fetch(`${base}/there/${port}/events`);
    const reader = events.body!.getReader();
    assert.equal(Buffer.from((await reader.read()).value!).toString(), "data: first\n\n");
    await reader.cancel();
    const ws = new WebSocket(`ws://127.0.0.1:${door.port}/peer/there/${(wss.address() as AddressInfo).port}/`);
    await new Promise((r, j) => (ws.once("open", r), ws.once("error", j)));
    const echoed = new Promise<string>((r) => ws.once("message", (d) => r(String(d))));
    ws.send("ping");
    assert.equal(await echoed, "ping");
    ws.close();
  } finally {
    web.closeAllConnections();
    web.close();
    wss.close();
    await door.close(0);
    http.close();
    await Promise.all([here.close(), there.close(), old.close()]);
  }
});
