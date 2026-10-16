// Web services of another station through this one's agents' door (mesh/peer-http.ts): two stations' endpoints
// connected in memory (memory-mesh.ts), real HTTP and WebSocket services on this machine standing for the other's.
// /peer/<station>/<port>/<path> is <path> of the service there, both ways as it comes; who may ask is the roster's
// stations, from this machine's programs only.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { type IncomingMessage, type Server, type ServerResponse, createServer, request as httpRequest } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import WebSocket, { WebSocketServer } from "ws";
import { Cloud } from "../src/cloud/state.ts";
import { PEER_HTTP_ALPN, PeerHttp, serveHttp } from "../src/mesh/peer-http.ts";
import { PEER_ALPN } from "../src/mesh/peer.ts";
import type { Endpoint } from "../src/mesh/native.ts";
import { type AgentsDoor, openAgentsDoor, peerTarget } from "../src/tools/http.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";
import { memoryMesh } from "./memory-mesh.ts";

/// A station's cloud.json in memory, read as the station reads it: in workspace "ws" with `peers` ({id, name}).
const cloudOf = (station: string, name: string, peers: { id: string; name: string }[]): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name, station, peers, revocations: [], joined: [] },
    lock: null,
    peersCurrent: true,
    listeners: new Set(),
    relays: () => [],
  });

/// A promise and what settles it.
function later<T = void>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}

/// The other station's machine's web service: what each path does.
async function service(handle: (req: IncomingMessage, res: ServerResponse) => void): Promise<{ port: number; server: Server }> {
  const server = createServer(handle);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return { port: (server.address() as AddressInfo).port, server };
}

/// Two stations (and one from before web requests), this one's door, and its way to the others.
async function stations() {
  const mesh = memoryMesh();
  const bind = (alpns: Buffer[]) => mesh.bind({ secretKey: randomBytes(32), alpns, relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [here, there, old, gone] = await Promise.all([bind([PEER_HTTP_ALPN, PEER_ALPN]), bind([PEER_HTTP_ALPN, PEER_ALPN]), bind([PEER_ALPN]), bind([PEER_HTTP_ALPN])]);
  await gone.close();
  const roster = [
    { id: here.id(), name: "Here" },
    { id: there.id(), name: "Studio" },
    { id: old.id(), name: "old" },
    { id: gone.id(), name: "gone" },
  ];
  const hereCloud = cloudOf(here.id(), "Here", roster);
  const thereCloud = cloudOf(there.id(), "Studio", [...roster]);
  const served: Promise<void>[] = [];
  const accept = (endpoint: Endpoint, cloud: any) =>
    void (async () => {
      for (;;) {
        const conn = await endpoint.accept();
        if (!conn) return;
        // As the mesh does (mesh.ts): a connection that is not served is closed.
        if (conn.alpn().equals(PEER_HTTP_ALPN)) served.push(serveHttp(conn, cloud).catch(() => conn.close(0, "refused")));
      }
    })();
  accept(there, thereCloud);
  accept(old, cloudOf(old.id(), "old", roster));
  const http = new PeerHttp(here, hereCloud, (id) => ({ id }));
  const mcp = new McpEndpoint(() => undefined, []);
  const door = await openAgentsDoor({ port: 0 }, mcp, () => ({ status: 400, body: {} }), () => http);
  const base = `http://127.0.0.1:${door.port}/peer`;
  return { here, there, old, hereCloud, thereCloud, http, door, base, served, close: async () => (await door.close(0), http.close(), await Promise.all([here.close(), there.close(), old.close()])) };
}

/// A request to the door with headers fetch would not send as given (Host, Origin): its status and text.
function raw(door: AgentsDoor, path: string, headers: Record<string, string>): Promise<[number, string]> {
  return new Promise((resolve, reject) => {
    const req = httpRequest({ host: "127.0.0.1", port: door.port, path, headers, agent: false }, (res) => {
      const parts: Buffer[] = [];
      res.on("data", (c) => parts.push(c));
      res.on("end", () => resolve([res.statusCode ?? 0, Buffer.concat(parts).toString()]));
    });
    req.on("error", reject);
    req.end();
  });
}

test("a /peer URL names a station, a port and the path with its query", () => {
  assert.deepEqual(peerTarget("/peer/Studio/11434/api/tags?x=1"), { station: "Studio", given: "Studio", port: 11434, path: "/api/tags?x=1" });
  assert.deepEqual(peerTarget("/peer/my%20mac/80"), { station: "my mac", given: "my%20mac", port: 80, path: "/" });
  assert.deepEqual(peerTarget("/peer/a/8080?q"), { station: "a", given: "a", port: 8080, path: "/?q" });
  for (const bad of ["/peer/a", "/peer//80/", "/peer/a/0/", "/peer/a/65536/", "/peer/a/80x/", "/peer/%zz/80/", "/mcp"]) assert.equal(peerTarget(bad), null, bad);
});

test("requests reach the other station's service: bodies both ways, its headers, redirects, streams as they come", async () => {
  const s = await stations();
  const next = [later(), later(), later()];
  const web = await service((req, res) => {
    const url = req.url ?? "/";
    if (url === "/hello?x=1") return res.writeHead(200, { "content-type": "text/plain", "x-seen": `${req.headers.host} ${req.headers.authorization}` }).end("hello");
    if (url === "/echo") {
      const hash = createHash("sha256");
      let size = 0;
      req.on("data", (c: Buffer) => (hash.update(c), (size += c.length)));
      req.on("end", () => res.writeHead(201, { "content-type": "application/json" }).end(JSON.stringify({ size, sha: hash.digest("hex"), length: req.headers["content-length"] ?? null })));
      return;
    }
    if (url === "/big") {
      res.writeHead(200, { "content-length": String(8 * 1024 * 1024) });
      const chunk = Buffer.alloc(64 * 1024, 7);
      let left = 128;
      const pump = () => {
        while (left > 0) {
          left--;
          if (!res.write(chunk)) return void res.once("drain", pump);
        }
        res.end();
      };
      return pump();
    }
    // Each event only once the asker has the one before: nothing waits for the whole answer.
    if (url === "/events") {
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.write("data: 0\n\n");
      void (async () => {
        for (const [i, n] of next.entries()) {
          await n.promise;
          res.write(`data: ${i + 1}\n\n`);
        }
        res.end();
      })();
      return;
    }
    if (url === "/old") return res.writeHead(302, { location: `http://localhost:${web.port}/hello?x=1` }).end();
    res.writeHead(404).end();
  });
  try {
    const hello = await fetch(`${s.base}/Studio/${web.port}/hello?x=1`, { headers: { authorization: "Bearer svc" } });
    assert.equal(hello.status, 200);
    assert.equal(await hello.text(), "hello");
    // Host as the service's own, its program's authorization passed on.
    assert.equal(hello.headers.get("x-seen"), `localhost:${web.port} Bearer svc`);
    // By id too, any case of the name.
    assert.equal(await (await fetch(`${s.base}/${s.there.id()}/${web.port}/hello?x=1`)).text(), "hello");
    assert.equal(await (await fetch(`${s.base}/studio/${web.port}/hello?x=1`)).text(), "hello");

    const upload = randomBytes(3 * 1024 * 1024 + 17);
    const sent = await fetch(`${s.base}/Studio/${web.port}/echo`, { method: "POST", body: upload });
    assert.equal(sent.status, 201);
    assert.deepEqual(await sent.json(), { size: upload.length, sha: createHash("sha256").update(upload).digest("hex"), length: String(upload.length) });
    // A body of no length said (chunked) goes as it comes.
    const chunked = await fetch(`${s.base}/Studio/${web.port}/echo`, {
      method: "POST",
      body: new ReadableStream({ start: (c) => (c.enqueue(new Uint8Array([1, 2, 3])), c.close()) }),
      duplex: "half",
    } as RequestInit);
    assert.deepEqual(await chunked.json(), { size: 3, sha: createHash("sha256").update(Buffer.from([1, 2, 3])).digest("hex"), length: null });

    const big = Buffer.from(await (await fetch(`${s.base}/Studio/${web.port}/big`)).arrayBuffer());
    assert.equal(big.length, 8 * 1024 * 1024);
    assert.ok(big.every((b) => b === 7));

    const events = await fetch(`${s.base}/Studio/${web.port}/events`);
    assert.equal(events.headers.get("content-type"), "text/event-stream");
    const reader = events.body!.getReader();
    let got = "";
    for (let i = 0; i <= next.length; i++) {
      while (!got.includes(`data: ${i}\n\n`)) got += Buffer.from((await reader.read()).value!).toString();
      next[i]?.resolve();
    }
    assert.equal((await reader.read()).done, true);

    // A redirect to the service itself stays under its /peer path.
    const moved = await fetch(`${s.base}/Studio/${web.port}/old`, { redirect: "manual" });
    assert.equal(moved.status, 302);
    assert.equal(moved.headers.get("location"), `/peer/Studio/${web.port}/hello?x=1`);
    assert.equal(await (await fetch(`${s.base}/Studio/${web.port}/old`)).text(), "hello");
  } finally {
    web.server.close();
    await s.close();
  }
});

test("a WebSocket reaches the other station's service with its sub-protocol, messages both ways, closes passed on", async () => {
  const s = await stations();
  const wss = new WebSocketServer({ port: 0, host: "127.0.0.1", handleProtocols: (p) => (p.has("chat") ? "chat" : false) });
  await new Promise((r) => wss.once("listening", r));
  const port = (wss.address() as AddressInfo).port;
  const closed = later<[number, string]>();
  wss.on("connection", (ws, req) => {
    ws.send(`hi ${req.headers.authorization}`);
    ws.on("message", (data, binary) => ws.send(binary ? data : `echo ${data}`, { binary }));
    ws.on("close", (code, reason) => closed.resolve([code, reason.toString()]));
  });
  try {
    const ws = new WebSocket(`ws://127.0.0.1:${s.door.port}/peer/Studio/${port}/socket`, ["chat"], { headers: { authorization: "Bearer svc" } });
    const heard: string[] = [];
    const more = () => new Promise<WebSocket.RawData>((r) => ws.once("message", r));
    const first = more();
    await new Promise((r, j) => (ws.once("open", r), ws.once("error", j)));
    assert.equal(ws.protocol, "chat");
    heard.push(String(await first));
    ws.send("one");
    heard.push(String(await more()));
    ws.send(Buffer.from([0, 1, 2]));
    assert.deepEqual([...(await more() as Buffer)], [0, 1, 2]);
    assert.deepEqual(heard, ["hi Bearer svc", "echo one"]);
    const done = new Promise<[number, string]>((r) => ws.once("close", (code, reason) => r([code, reason.toString()])));
    ws.close(4000, "bye");
    assert.deepEqual(await closed.promise, [4000, "bye"]);
    assert.deepEqual(await done, [4000, "bye"]);

    // The service closing closes the program's.
    wss.removeAllListeners("connection");
    wss.on("connection", (w) => w.close(4001, "enough"));
    const second = new WebSocket(`ws://127.0.0.1:${s.door.port}/peer/Studio/${port}/`);
    assert.deepEqual(await new Promise((r) => second.once("close", (code, reason) => r([code, reason.toString()]))), [4001, "enough"]);

    // No service there: the upgrade is refused, saying why.
    wss.close();
    const none = new WebSocket(`ws://127.0.0.1:${s.door.port}/peer/Studio/${port}/`);
    const status = await new Promise<number>((r) => none.once("unexpected-response", (_q, res) => r(res.statusCode ?? 0)));
    assert.equal(status, 502);
  } finally {
    wss.close();
    await s.close();
  }
});

test("only programs on this machine: another Host or a web page's Origin is refused", async () => {
  const s = await stations();
  const web = await service((_req, res) => res.end("ok"));
  try {
    const path = `/peer/Studio/${web.port}/`;
    assert.deepEqual(await raw(s.door, path, {}), [200, "ok"]);
    assert.deepEqual(await raw(s.door, path, { host: `localhost:${s.door.port}` }), [200, "ok"]);
    // DNS rebinding: a site's page named 127.0.0.1 says its own Host.
    assert.equal((await raw(s.door, path, { host: `evil.example:${s.door.port}` }))[0], 403);
    assert.equal((await raw(s.door, path, { host: "127.0.0.1:1" }))[0], 403);
    assert.equal((await raw(s.door, path, { origin: "https://evil.example" }))[0], 403);
    assert.equal((await raw(s.door, path, { origin: `http://127.0.0.1:${s.door.port}` }))[0], 403);
    // `Origin: null` from outside a browser passes; from a browser's sandboxed frame (which says where it fetches) not.
    assert.deepEqual(await raw(s.door, path, { origin: "null" }), [200, "ok"]);
    assert.equal((await raw(s.door, path, { origin: "null", "sec-fetch-site": "cross-site" }))[0], 403);
    const ws = new WebSocket(`ws://127.0.0.1:${s.door.port}${path}`, { origin: "https://evil.example" });
    assert.equal(await new Promise<number>((r) => ws.once("unexpected-response", (_q, res) => r(res.statusCode ?? 0))), 403);
  } finally {
    web.server.close();
    await s.close();
  }
});

test("only the roster's stations, by a name that tells one; the station's own ports and old or gone stations refused", async () => {
  const s = await stations();
  const web = await service((_req, res) => res.end("ok"));
  const say = async (url: string) => {
    const r = await fetch(url);
    return [r.status, await r.text()] as const;
  };
  try {
    assert.match((await say(`${s.base}/nowhere/${web.port}/`)).join(" "), /^404 no station nowhere .*Studio/);
    assert.match((await say(`${s.base}/here/${web.port}/`)).join(" "), /^400 here is this station/);
    // A name two stations have: the id tells which.
    s.hereCloud.state.peers = [...s.hereCloud.state.peers, { id: "ab".repeat(32), name: "studio" }];
    assert.match((await say(`${s.base}/Studio/${web.port}/`)).join(" "), /^409 Studio names 2 stations/);
    assert.equal((await say(`${s.base}/${s.there.id()}/${web.port}/`))[1], "ok");
    s.hereCloud.state.peers = s.hereCloud.state.peers.slice(0, -1);
    // The station's own ports there (its agents' door would carry the request on).
    assert.match((await say(`${s.base}/Studio/${s.door.port}/health`)).join(" "), new RegExp(`^403 port ${s.door.port} is the station's own`));
    // A station from before: told by the protocol it answers in.
    assert.match((await say(`${s.base}/old/${web.port}/`)).join(" "), /^502 station old is from before .* needs an update/);
    assert.match((await say(`${s.base}/gone/${web.port}/`)).join(" "), /^502 station gone cannot be reached/);
    // That station does not have this one in its roster.
    s.thereCloud.state.peers = s.thereCloud.state.peers.filter((p: any) => p.id !== s.here.id());
    assert.match((await say(`${s.base}/Studio/${web.port}/`)).join(" "), /^403 /);
    // This one's roster not current: nothing goes.
    s.hereCloud.peersCurrent = false;
    assert.match((await say(`${s.base}/Studio/${web.port}/`)).join(" "), /^503 /);
  } finally {
    web.server.close();
    await s.close();
  }
});

test("taken out of the other station's workspace, a connection it had ends", async () => {
  const s = await stations();
  const hold = later();
  const web = await service((_req, res) => {
    res.writeHead(200);
    res.write("start");
    void hold.promise.then(() => res.end());
  });
  try {
    const answer = await fetch(`${s.base}/Studio/${web.port}/`);
    const reader = answer.body!.getReader();
    assert.equal(Buffer.from((await reader.read()).value!).toString(), "start");
    s.thereCloud.state.peers = s.thereCloud.state.peers.filter((p: any) => p.id !== s.here.id());
    (s.thereCloud as any).tell();
    await assert.rejects(reader.read());
    // A roster not current alone ends nothing.
    s.thereCloud.state.peers = [...s.thereCloud.state.peers, { id: s.here.id(), name: "Here" }];
    const again = await fetch(`${s.base}/Studio/${web.port}/`);
    const more = again.body!.getReader();
    assert.equal(Buffer.from((await more.read()).value!).toString(), "start");
    s.thereCloud.peersCurrent = false;
    (s.thereCloud as any).tell();
    hold.resolve();
    assert.equal((await more.read()).done, true);
  } finally {
    hold.resolve();
    web.server.close();
    await s.close();
  }
});

test("a station that takes no connection in time is said to be offline", async () => {
  const cloud = cloudOf("me", "me", [{ id: "me", name: "me" }, { id: "cd".repeat(32), name: "far" }]);
  const endpoint = { connect: () => new Promise(() => {}) } as unknown as Endpoint;
  const http = new PeerHttp(endpoint, cloud, (id) => ({ id }), 1);
  const door = await openAgentsDoor({ port: 0 }, new McpEndpoint(() => undefined, []), () => ({ status: 400, body: {} }), () => http);
  try {
    const answer = await fetch(`http://127.0.0.1:${door.port}/peer/far/8080/`);
    assert.equal(answer.status, 504);
    assert.match(await answer.text(), /station far did not answer .* offline/);
  } finally {
    await door.close(0);
  }
});
