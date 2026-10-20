// Ports of another station forwarded to this machine (mesh/peer-forward.ts, the peer_forward tool): two stations'
// endpoints connected in memory (memory-mesh.ts, its streams flow-controlled as QUIC's are), real TCP services and
// clients on this machine standing for the other's and this one's. A forward carries bytes as they are, both ways at
// the slower side's pace, half-closes and WebSockets included; it is refused as /peer is, and closes with its session,
// its job, or after a while with no connection (on a test clock).
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { createServer as createHttpServer } from "node:http";
import { type AddressInfo, type Server, type Socket, connect, createServer } from "node:net";
import { test } from "node:test";
import { Effect, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";
import WebSocket, { WebSocketServer } from "ws";
import { Cloud } from "../src/cloud/state.ts";
import { Forwards, IDLE_MS, type JobState, pipeTcp, reachLocal } from "../src/mesh/peer-forward.ts";
import { PEER_HTTP_ALPN, PeerHttp, peerNamed, serveHttp } from "../src/mesh/peer-http.ts";
import { PEER_ALPN } from "../src/mesh/peer.ts";
import type { Endpoint, Stream } from "../src/mesh/native.ts";
import { ownPorts } from "../src/ops/own.ts";
import { forwardTools } from "../src/tools/forward.ts";
import { memoryMesh } from "./memory-mesh.ts";

const cloudOf = (station: string, name: string, peers: { id: string; name: string }[]): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name, station, peers, revocations: [], joined: [] },
    lock: null,
    peersCurrent: true,
    listeners: new Set(),
    relays: () => [],
  });

/// A TestClock; `begun(n)` resolves once `n` waits have begun on it (each then sleeping on it: an adjust reaches it).
function testClock(): { clock: Clock.Clock; adjust(ms: number): Promise<void>; begun(n: number): Promise<void>; asked(): number } {
  const test = Effect.runSync(Scope.provide(TestClock.make(), Effect.runSync(Scope.make())));
  let asked = 0;
  let heard: (() => void)[] = [];
  const clock: Clock.Clock = {
    ...test,
    sleep: (d) =>
      Effect.suspend(() => {
        asked++;
        for (const wake of heard.splice(0)) wake();
        return test.sleep(d);
      }),
  };
  const begun = async (n: number) => {
    while (asked < n) await new Promise<void>((r) => heard.push(r));
    for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
  };
  return { clock, adjust: (ms) => Effect.runPromise(test.adjust(`${ms} millis`)), begun, asked: () => asked };
}

/// Until `check` holds, looked at on each turn of the event loop (no deadline).
async function until(check: () => boolean) {
  while (!check()) await new Promise((r) => setImmediate(r));
}

/// A server on this machine standing for a service on the other station.
async function listen(server: Server | ReturnType<typeof createHttpServer>, host = "127.0.0.1"): Promise<number> {
  await new Promise<void>((resolve) => server.listen(0, host, resolve));
  return (server.address() as AddressInfo).port;
}

/// A port nothing listens on now.
async function freePort(): Promise<number> {
  const s = createServer();
  const port = await listen(s);
  await new Promise((r) => s.close(r));
  return port;
}

/// A TCP connection to 127.0.0.1:`port`, half-open, once it is connected.
function dial(port: number): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = connect({ host: "127.0.0.1", port, allowHalfOpen: true });
    socket.once("connect", () => resolve(socket));
    socket.once("error", reject);
  });
}

/// All a socket says until its end (rejected on an error), read slowly: each chunk only on the event loop's next turn.
function readAll(socket: Socket, slow = false): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const parts: Buffer[] = [];
    socket.on("data", (c: Buffer) => {
      parts.push(c);
      if (slow) {
        socket.pause();
        setImmediate(() => socket.resume());
      }
    });
    socket.once("end", () => resolve(Buffer.concat(parts)));
    socket.once("error", reject);
  });
}

/// Writes `data` at the pace the socket takes it, then ends it (a half-close).
async function send(socket: Socket, data: Buffer) {
  for (let at = 0; at < data.length; at += 256 * 1024) {
    if (!socket.write(data.subarray(at, at + 256 * 1024))) await new Promise((r) => socket.once("drain", r));
  }
  socket.end();
}

/// A connection to 127.0.0.1:`port`: what it heard before it closed, and whether it was cut off (reset) rather than
/// ended. One cut off at once may be reset before it is seen connected: the same.
function attempt(port: number): Promise<{ heard: string; reset: boolean }> {
  return new Promise((resolve) => {
    const socket = connect({ host: "127.0.0.1", port, allowHalfOpen: true });
    let heard = "";
    let reset = false;
    socket.on("data", (c: Buffer) => (heard += c.toString()));
    socket.on("error", () => (reset = true));
    socket.once("end", () => socket.end());
    socket.once("close", () => resolve({ heard, reset }));
  });
}

const sha = (b: Buffer) => createHash("sha256").update(b).digest("hex");

/// Jobs as the forwards see them: their records, and their changes told.
function fakeJobs() {
  const records = new Map<string, JobState>();
  const listeners = new Set<(id: string) => void>();
  return {
    records,
    set(id: string, job: JobState | null) {
      if (job === null) records.delete(id);
      else records.set(id, job);
      for (const l of listeners) l(id);
    },
    job: (id: string) => records.get(id) ?? null,
    changes: (changed: (id: string) => void) => (listeners.add(changed), () => listeners.delete(changed)),
  };
}

/// This station and another (and one from before forwards, and one gone), the way to them, and this one's forwards on a
/// test clock. `ports`: the other station's ports as its services here listen on them (a forward to a port free here
/// would otherwise reach itself, both stations being on this machine); `forwardedThere`: the other's own forwards.
async function stations(ports: Map<number, number> = new Map(), forwardedThere: Set<number> = new Set()) {
  const mesh = memoryMesh({ window: 64 * 1024 });
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
  const local = { reach: (port: number) => reachLocal(ports.get(port) ?? port), forwarded: (port: number) => forwardedThere.has(port) };
  const accept = (endpoint: Endpoint, cloud: any) =>
    void (async () => {
      for (;;) {
        const conn = await endpoint.accept();
        if (!conn) return;
        if (conn.alpn().equals(PEER_HTTP_ALPN)) void serveHttp(conn, cloud, local).catch(() => conn.close(0, "refused"));
      }
    })();
  accept(there, thereCloud);
  accept(old, cloudOf(old.id(), "old", roster));
  const http = new PeerHttp(here, hereCloud, (id) => ({ id }));
  let tunnels = 0;
  const route = { tunnel: (station: string, port: number, probe?: boolean) => (tunnels++, http.tunnel(station, port, probe)) };
  const time = testClock();
  const jobs = fakeJobs();
  const forwards = new Forwards({
    route: () => route,
    resolve: (station) => {
      const { id } = peerNamed(hereCloud, station);
      return { id, name: roster.find((p) => p.id === id)!.name };
    },
    jobs,
    clock: time.clock,
  });
  const tool = forwardTools(forwards)[0]!;
  return {
    here, there, old, hereCloud, thereCloud, http, forwards, time, jobs, tool,
    tunnels: () => tunnels,
    close: async () => (await forwards.close(), http.close(), await Promise.all([here.close(), there.close(), old.close()])),
  };
}

test("pipeTcp: one write on the stream at a time, reads only while the socket takes more; ends passed on each way", async () => {
  const mesh = memoryMesh({ window: 16 * 1024 });
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_HTTP_ALPN], relayUrls: [], discovery: false });
  const [a, b] = await Promise.all([bind(), bind()]);
  const server = createServer({ allowHalfOpen: true, pauseOnConnect: true });
  const port = await listen(server);
  try {
    const conn = await a.connect({ id: b.id() }, PEER_HTTP_ALPN);
    const mine = await conn.openBi();
    const there = (await b.accept())!;
    const theirs = (await there.acceptBi())!;
    const accepted = new Promise<Socket>((r) => server.once("connection", r));
    const client = await dial(port);
    const socket = await accepted;
    let pending = 0;
    let mostPending = 0;
    let mostBuffered = 0;
    const watched: Stream = {
      write: async (bytes) => {
        mostPending = Math.max(mostPending, ++pending);
        try {
          await mine.write(bytes);
        } finally {
          pending--;
        }
      },
      read: () => {
        mostBuffered = Math.max(mostBuffered, socket.writableLength);
        return mine.read();
      },
      finish: () => mine.finish(),
      stopped: () => mine.stopped(),
      reset: (code) => mine.reset(code),
    };
    const piped = pipeTcp(socket, watched, Buffer.from("carried:"));
    const up = randomBytes(8 * 1024 * 1024 + 3);
    const down = randomBytes(8 * 1024 * 1024 + 5);
    // The client's side: all it sends, then its end, while it reads what comes slowly.
    const heard = readAll(client, true);
    void send(client, up);
    // The stream's other side: read slowly; its own bytes written as the window lets them, then its end.
    const got = (async () => {
      const parts: Buffer[] = [];
      for (let more = await theirs.read(); more !== null; more = await theirs.read()) {
        parts.push(more);
        await new Promise((r) => setImmediate(r));
      }
      return Buffer.concat(parts);
    })();
    for (let at = 0; at < down.length; at += 32 * 1024) await theirs.write(down.subarray(at, at + 32 * 1024));
    await theirs.finish();
    assert.equal(sha(await got), sha(up));
    assert.equal(sha(await heard), sha(Buffer.concat([Buffer.from("carried:"), down])));
    await piped;
    assert.equal(mostPending, 1);
    assert.ok(mostBuffered < socket.writableHighWaterMark, `${mostBuffered} buffered for the socket at a read`);

    // The other side's reset ends the connection here.
    const pair = async () => {
      const accepted = new Promise<Socket>((r) => server.once("connection", r));
      const client = await dial(port);
      client.on("error", () => {});
      const mine = await conn.openBi();
      return { client, socket: await accepted, mine, theirs: (await there.acceptBi())! };
    };
    const reset = await pair();
    const closed = new Promise((r) => reset.client.once("close", r));
    const piped2 = pipeTcp(reset.socket, reset.mine);
    await reset.theirs.reset(0);
    await piped2;
    await closed;
    assert.ok(reset.socket.destroyed);
    // A client gone (its connection reset, not ended: an end is a half-close): the stream is reset.
    const gone = await pair();
    const piped3 = pipeTcp(gone.socket, gone.mine);
    gone.client.resetAndDestroy();
    await piped3;
    await assert.rejects(gone.theirs.read(), /reset/);
  } finally {
    server.close();
    await Promise.all([a.close(), b.close()]);
  }
});

test("a forward carries bytes as they are: 16 MB each way at the slower side's pace, half-closes passed on", async () => {
  const service = createServer({ allowHalfOpen: true }, (socket) => {
    const hash = createHash("sha256");
    let size = 0;
    socket.on("data", (c: Buffer) => {
      hash.update(c);
      size += c.length;
      // A slow reader: the forward waits for it.
      socket.pause();
      setImmediate(() => socket.resume());
    });
    // Its asker's end heard (the rest of its answer still to go): what came, then 16 MB of its own, then its end.
    socket.on("end", () => void send(socket, Buffer.concat([Buffer.from(`${size} ${hash.digest("hex")}\n`), DOWN])));
    // The forward looks whether something here listens on the port (both stations are on this machine): a knock.
    socket.on("error", () => {});
  });
  const DOWN = randomBytes(16 * 1024 * 1024 + 11);
  const port = await listen(service);
  const s = await stations();
  try {
    const opened = await s.forwards.open("chat-1", "studio", port);
    // That port is the service's own here (both stations are on this machine): another is taken.
    assert.notEqual(opened.local, `127.0.0.1:${port}`);
    assert.match(opened.note!, new RegExp(`port ${port} is taken here`));
    const local = Number(opened.local.split(":")[1]);
    const up = randomBytes(16 * 1024 * 1024 + 7);
    const client = await dial(local);
    const answer = readAll(client, true);
    await send(client, up);
    const got = await answer;
    const nl = got.indexOf(10);
    assert.equal(got.subarray(0, nl).toString(), `${up.length} ${sha(up)}`);
    assert.equal(sha(got.subarray(nl + 1)), sha(DOWN));
    await until(() => client.destroyed || client.readyState === "closed");
    // Listed with what it carried.
    const [listed] = await s.forwards.list("chat-1");
    assert.equal(listed!.station, "Studio");
    assert.equal(listed!.station_state, "online");
    assert.equal(listed!.served, 1);
  } finally {
    service.close();
    await s.close();
  }
});

test("web pages pass unchanged: absolute asset paths, redirects, cookies, the Host as given, a WebSocket upgrade", async () => {
  const web = createHttpServer((req, res) => {
    if (req.url === "/") return res.writeHead(200, { "content-type": "text/html", "set-cookie": "sid=1; Path=/" }).end(`<script src="/assets/app.js"></script>`);
    if (req.url === "/assets/app.js") return res.writeHead(200, { "content-type": "text/javascript", "x-host": req.headers.host ?? "", "x-cookie": req.headers.cookie ?? "" }).end("console.log(1)");
    if (req.url === "/app") return res.writeHead(302, { location: "/login" }).end();
    if (req.url === "/login") return res.end("login");
    res.writeHead(404).end();
  });
  const wss = new WebSocketServer({ server: web });
  wss.on("connection", (ws, req) => {
    ws.send(`hi ${req.url}`);
    ws.on("message", (data, binary) => ws.send(data, { binary }));
  });
  const servicePort = await listen(web);
  // A port free here, the other station's service there.
  const port = await freePort();
  const s = await stations(new Map([[port, servicePort]]));
  try {
    const opened = await s.forwards.open("chat-1", "Studio", port);
    // Free here: the same number.
    assert.equal(opened.local, `127.0.0.1:${port}`);
    assert.equal(opened.url, `http://127.0.0.1:${port}/`);
    assert.equal(opened.note, undefined);
    const page = await fetch(opened.url);
    assert.equal(await page.text(), `<script src="/assets/app.js"></script>`);
    assert.equal(page.headers.get("set-cookie"), "sid=1; Path=/");
    const asset = await fetch(`${opened.url}assets/app.js`, { headers: { cookie: "sid=1" } });
    assert.equal(await asset.text(), "console.log(1)");
    assert.equal(asset.headers.get("x-host"), `127.0.0.1:${port}`);
    assert.equal(asset.headers.get("x-cookie"), "sid=1");
    const moved = await fetch(`${opened.url}app`, { redirect: "manual" });
    assert.equal(moved.headers.get("location"), "/login");
    assert.equal(await (await fetch(`${opened.url}app`)).text(), "login");
    // A browser's page may say its Origin: nothing is refused for it here.
    const ws = new WebSocket(`ws://127.0.0.1:${port}/hmr`, { origin: `http://127.0.0.1:${port}` });
    const first = new Promise<string>((r) => ws.once("message", (d) => r(String(d))));
    await new Promise((r, j) => (ws.once("open", r), ws.once("error", j)));
    assert.equal(await first, "hi /hmr");
    const echoed = new Promise<Buffer>((r) => ws.once("message", (d) => r(d as Buffer)));
    ws.send(Buffer.from([1, 2, 3]));
    assert.deepEqual([...(await echoed)], [1, 2, 3]);
    const closed = new Promise((r) => ws.once("close", r));
    ws.close();
    await closed;
    // Asked again for the same port, the same forward.
    assert.equal((await s.forwards.open("chat-1", "studio", port)).note, "already forwarded");
    assert.equal(s.forwards.count(), 1);
  } finally {
    wss.close();
    web.closeAllConnections();
    web.close();
    await s.close();
  }
});

/// Whether this machine has an IPv6 loopback to listen on.
async function hasV6(): Promise<boolean> {
  const s = createServer();
  try {
    await new Promise<void>((resolve, reject) => (s.once("error", reject), s.listen(0, "::1", resolve)));
    await new Promise((r) => s.close(r));
    return true;
  } catch {
    return false;
  }
}

test("the station there reaches a service listening on 127.0.0.1 alone, or on [::1] alone", async (t) => {
  const v6 = await hasV6();
  const s = await stations();
  const servers: Server[] = [];
  try {
    for (const host of v6 ? ["127.0.0.1", "::1"] : ["127.0.0.1"]) {
      const server = createServer((socket) => (socket.on("error", () => {}), socket.end(`hello from ${host}`)));
      servers.push(server);
      const port = await listen(server, host);
      const opened = await s.forwards.open("chat-1", "Studio", port);
      // Something listens on that port here (at either address): the forward is elsewhere.
      assert.notEqual(opened.local, `127.0.0.1:${port}`);
      const client = await dial(Number(opened.local.split(":")[1]));
      client.end();
      assert.equal((await readAll(client)).toString(), `hello from ${host}`);
    }
    if (!v6) t.diagnostic("no IPv6 loopback here: [::1] alone not tried");
  } finally {
    for (const server of servers) server.close();
    await s.close();
  }
});

test("refused as /peer is: the station's own ports and forwards, an old or unknown station; nothing there closes the connection", async () => {
  const ports = new Map<number, number>();
  const s = await stations(ports, new Set([7777]));
  const own = await freePort();
  ownPorts.add(own);
  try {
    await assert.rejects(s.forwards.open("chat-1", "Studio", own), new RegExp(`port ${own} is the station's own there`));
    // A port that station forwards from another: refused (a forward to it would carry on, or loop).
    await assert.rejects(s.forwards.open("chat-1", "Studio", 7777), /port 7777 there is a port that station forwards from another/);
    await assert.rejects(s.forwards.open("chat-1", "old", 5432), /station old is from before .* needs an update/);
    await assert.rejects(s.forwards.open("chat-1", "nowhere", 5432), /no station nowhere/);
    await assert.rejects(s.forwards.open("chat-1", "Here", 5432), /is this station/);
    // That station does not have this one in its roster.
    s.thereCloud.state.peers = s.thereCloud.state.peers.filter((p: any) => p.id !== s.here.id());
    await assert.rejects(s.forwards.open("chat-1", "Studio", 5432), /that station refused/);
    s.thereCloud.state.peers = [...s.thereCloud.state.peers, { id: s.here.id(), name: "Here" }];
    assert.equal(s.forwards.count(), 0);
    // Nothing listens on the port there: the forward opens (a dev server may come up later), each connection closes.
    const nothing = await freePort();
    ports.set(nothing, await freePort());
    const opened = await s.forwards.open("chat-1", "Studio", nothing);
    assert.deepEqual(await attempt(Number(opened.local.split(":")[1])), { heard: "", reset: true });
    const [listed] = await s.forwards.list("chat-1");
    assert.equal(listed!.station_state, "online");
    assert.match(listed!.last_error!, new RegExp(`nothing takes connections on port ${nothing} there`));
  } finally {
    ownPorts.delete(own);
    await s.close();
  }
});

test("its station offline: the listener stays, connections close at once, a listing says offline", async () => {
  const service = createServer((socket) => (socket.on("error", () => {}), socket.end("hello")));
  const port = await listen(service);
  const s = await stations();
  try {
    const opened = await s.forwards.open("chat-1", "Studio", port);
    const local = Number(opened.local.split(":")[1]);
    await s.there.close();
    assert.deepEqual(await attempt(local), { heard: "", reset: true });
    // Marked down: the next connection is closed without asking the mesh again.
    const asked = s.tunnels();
    assert.deepEqual(await attempt(local), { heard: "", reset: true });
    assert.equal(s.tunnels(), asked);
    const [listed] = await s.forwards.list("chat-1");
    assert.match(listed!.station_state!, /^offline: station Studio cannot be reached/);
    assert.match(listed!.last_error!, /cannot be reached/);
    assert.equal(s.forwards.count("chat-1"), 1);
  } finally {
    service.close();
    await s.close();
  }
});

test("a forward closes after 30 minutes with no connection, with its session, with its job, or when closed", async () => {
  const service = createServer((socket) => (socket.on("error", () => {}), socket.end("hello")));
  const port = await listen(service);
  const s = await stations();
  const refused = (local: string) =>
    new Promise<boolean>((resolve) => {
      const socket = connect({ host: "127.0.0.1", port: Number(local.split(":")[1]) });
      socket.once("connect", () => (socket.destroy(), resolve(false)));
      socket.once("error", () => resolve(true));
    });
  try {
    // Idle: no connection for the while, closed; one open keeps it.
    const asked = s.time.asked();
    const idle = await s.forwards.open("chat-1", "Studio", port);
    await s.time.begun(asked + 1);
    const tunnels = s.tunnels();
    const held = await dial(Number(idle.local.split(":")[1]));
    held.on("data", () => {});
    // Taken (its connection on its way there): no while counts now.
    await until(() => s.tunnels() > tunnels);
    await s.time.adjust(IDLE_MS * 2);
    assert.equal(s.forwards.count(), 1);
    const before = s.time.asked();
    held.destroy();
    await s.time.begun(before + 1);
    await s.time.adjust(IDLE_MS - 1);
    assert.equal(s.forwards.count(), 1);
    await s.time.adjust(1);
    await until(() => s.forwards.count() === 0);
    assert.ok(await refused(idle.local));

    // Its session archived or deleted: its forwards close, another session's stay.
    const mine = await s.forwards.open("chat-1", "Studio", port);
    const theirs = await s.forwards.open("chat-2", "Studio", port);
    s.forwards.closeSession("chat-1");
    assert.ok(await refused(mine.local));
    assert.equal(s.forwards.count("chat-2"), 1);

    // Its job ended (a service that exited is started again: not that).
    s.jobs.set("j1", { session: "chat-2", state: "running", port: 8080 });
    s.jobs.set("j2", { session: "chat-2", state: "running", port: null });
    await assert.rejects(s.forwards.open("chat-1", "Studio", port, undefined, "j1"), /no job j1 of this session/);
    const withService = await s.forwards.open("chat-2", "Studio", port, undefined, "j1");
    const withJob = await s.forwards.open("chat-2", "Studio", port, undefined, "j2");
    assert.equal(withService.job, "j1");
    s.jobs.set("j1", { session: "chat-2", state: "exited", port: 8080 });
    s.jobs.set("j2", { session: "chat-2", state: "exited", port: null });
    assert.ok(await refused(withJob.local));
    assert.ok(!(await refused(withService.local)));
    s.jobs.set("j1", { session: "chat-2", state: "stopped", port: 8080 });
    assert.ok(await refused(withService.local));

    // Closed by the tool.
    assert.equal(await s.tool.run("chat-2", { close: Number(theirs.local.split(":")[1]) }), `Closed ${theirs.local} (to Studio:${port}).`);
    assert.ok(await refused(theirs.local));
    assert.equal(s.forwards.count(), 0);
  } finally {
    service.close();
    await s.close();
  }
});

test("peer_forward: opens, lists and closes; an explicit local port taken is refused; asked wrong, it says how", async () => {
  const service = createServer((socket) => (socket.on("error", () => {}), socket.end("hello")));
  const servicePort = await listen(service);
  const port = await freePort();
  const s = await stations(new Map([[port, servicePort]]));
  try {
    assert.equal(await s.tool.run("chat-1", {}), "No forwarded ports.");
    const opened = JSON.parse(await s.tool.run("chat-1", { station: "studio", port }));
    assert.deepEqual(opened, { local: `127.0.0.1:${port}`, url: `http://127.0.0.1:${port}/`, station: "Studio", port, connections: 0, served: 0 });
    // Another session asks for the same port: taken here now, so elsewhere; at that port explicitly, refused.
    const other = JSON.parse(await s.tool.run("chat-2", { station: "Studio", port }));
    assert.notEqual(other.local, `127.0.0.1:${port}`);
    assert.match(other.note, /is taken here, so it is at/);
    await assert.rejects(s.tool.run("chat-3", { station: "Studio", port, local_port: port }), new RegExp(`127.0.0.1:${port} is taken here`));
    const client = await dial(port);
    client.end();
    assert.equal((await readAll(client)).toString(), "hello");
    const listed = JSON.parse(await s.tool.run("chat-1", {}));
    assert.equal(listed.length, 1);
    assert.equal(listed[0].station_state, "online");
    assert.equal(listed[0].served, 1);
    await assert.rejects(s.tool.run("chat-1", { station: "Studio" }), /give both station and port/);
    await assert.rejects(s.tool.run("chat-1", { close: 1, port: 2 }), /close takes no station or port/);
    await assert.rejects(s.tool.run("chat-1", { close: Number(other.local.split(":")[1]) }), /no forward of this session/);
    await assert.rejects(s.tool.run("chat-1", { station: "old", port: 5432 }), /needs an update/);
    assert.equal(await s.tool.run("chat-1", { close: port }), `Closed 127.0.0.1:${port} (to Studio:${port}).`);
  } finally {
    service.close();
    await s.close();
  }
});
