// The devices attached to a station (devices/, 2026-11-10): kept by their station, each its adder's; a chat reaches one
// on a port of its own station, carried over the mesh to the station it is on (memory-mesh.ts here), only its own
// processes let through, the device's station saying whether the chat may (a whole station: every chat).
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { type AddressInfo, type Server, type Socket, connect, createServer } from "node:net";
import { test } from "node:test";
import { Cloud } from "../src/cloud/state.ts";
import { DeviceRegistry } from "../src/devices/registry.ts";
import { reachDevice } from "../src/devices/connect.ts";
import { reachedAt } from "../src/devices/tool.ts";
import { Forwards } from "../src/mesh/peer-forward.ts";
import { DeviceRefused, PEER_HTTP_ALPN, PeerHttp, peerNamed, serveHttp } from "../src/mesh/peer-http.ts";
import { PEER_ALPN } from "../src/mesh/peer.ts";
import { memoryMesh } from "./memory-mesh.ts";

const cloudOf = (station: string, name: string, peers: { id: string; name: string }[]): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name, station, peers, revocations: [], joined: [] },
    lock: null,
    peersCurrent: true,
    listeners: new Set(),
    relays: () => [],
  });

const PAT = { sub: "pat", email: "Pat@Example.com", name: "Pat" };

async function listen(server: Server): Promise<number> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return (server.address() as AddressInfo).port;
}

/// A device on the network: it answers each line it is sent with the line upper-cased.
async function camera(): Promise<{ port: number; close(): Promise<void> }> {
  const server = createServer((s) => s.on("data", (c: Buffer) => s.write(c.toString().toUpperCase())));
  const port = await listen(server);
  return { port, close: () => new Promise((r) => server.close(() => r())) };
}

/// What 127.0.0.1:`port` answers to `line`, or that it was cut off.
function talk(port: number, line: string): Promise<string> {
  return new Promise((resolve) => {
    const socket: Socket = connect({ host: "127.0.0.1", port });
    let heard = "";
    socket.on("data", (c: Buffer) => {
      heard += c.toString();
      if (heard.length >= line.length) socket.end();
    });
    socket.on("error", () => resolve(`cut: ${heard}`));
    socket.once("connect", () => socket.write(line));
    socket.once("close", () => resolve(heard));
  });
}

test("a device is kept by its station, its adder's, as what it is reached at", () => {
  const registry = new DeviceRegistry(new DatabaseSync(":memory:"));
  const made = registry.add("ws", PAT, { name: "cam", kind: "tcp", target: "192.168.1.20:554" }, 100);
  assert.ok(typeof made !== "string");
  assert.equal(made.owner, "pat");
  assert.equal(made.owner_email, "pat@example.com");
  assert.match(made.id, /^[0-9a-f]{16}$/);
  assert.match(registry.add("ws", PAT, { name: "CAM", kind: "tcp", target: "10.0.0.1:80" }, 101) as string, /named CAM is attached here already/);
  assert.match(registry.add("ws", PAT, { name: "x", kind: "tcp", target: "nohost" }, 101) as string, /host:port/);
  assert.match(registry.add("ws", PAT, { name: "x", kind: "usb", target: "a" }, 101) as string, /kind: adb, tcp or serial/);
  assert.match(registry.add("ws", PAT, { name: "x", kind: "serial", target: "ttyUSB0" }, 101) as string, /its path/);
  assert.match(registry.add("ws", PAT, { name: "x", kind: "serial", target: "/dev/ttyUSB0", baud: 7 }, 101) as string, /baud/);
  assert.ok(typeof registry.add("ws", PAT, { name: "board", kind: "serial", target: "/dev/ttyUSB0", baud: 9600 }, 101) !== "string");
  assert.ok(typeof registry.add("ws", PAT, { name: "pixel", kind: "adb", target: "R5CT1234" }, 102) !== "string");
  assert.deepEqual(registry.of("ws").map((d) => d.name), ["cam", "board", "pixel"]);
  assert.deepEqual(registry.of("other"), []);
  assert.equal(registry.get("other", made.id), null);
  assert.equal(registry.remove("ws", made.id), true);
  assert.deepEqual(registry.of("ws").map((d) => d.name), ["board", "pixel"]);
  // What the agent is told, by kind.
  assert.match(reachedAt({ name: "pixel", kind: "adb", target: "R5CT1234" }, 4000), /adb -P 4000 -s R5CT1234/);
  assert.match(reachedAt({ name: "cam", kind: "tcp", target: "10.0.0.1:554" }, 4000), /127\.0\.0\.1:4000/);
  assert.match(reachedAt({ name: "board", kind: "serial", target: "/dev/ttyUSB0", baud: 9600 }, 4000), /9600 baud/);
});

test("a device on another station: forwarded to a port here, its bytes carried there and back; only the chat's processes let through", async () => {
  const cam = await camera();
  const mesh = memoryMesh({ window: 64 * 1024 });
  const bind = (alpns: Buffer[]) => mesh.bind({ secretKey: randomBytes(32), alpns, relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [here, there] = await Promise.all([bind([PEER_HTTP_ALPN, PEER_ALPN]), bind([PEER_HTTP_ALPN, PEER_ALPN])]);
  const roster = [{ id: here.id(), name: "Here" }, { id: there.id(), name: "Studio" }];
  const hereCloud = cloudOf(here.id(), "Here", roster);
  const thereCloud = cloudOf(there.id(), "Studio", roster);
  const registry = new DeviceRegistry(new DatabaseSync(":memory:"));
  const d = registry.add("ws", PAT, { name: "cam", kind: "tcp", target: `127.0.0.1:${cam.port}` }, 1);
  assert.ok(typeof d !== "string");
  const asked: string[] = [];
  void (async () => {
    for (;;) {
      const conn = await there.accept();
      if (!conn) return;
      void serveHttp(conn, thereCloud, {
        device: async (peer, workspace, session, id, probe) => {
          asked.push(`${peer === here.id() ? "here" : peer}/${workspace}/${session}/${id}/${probe}`);
          const kept = registry.get(workspace, id);
          if (kept === null) throw new DeviceRefused(404, "no such device on this station");
          return probe ? null : reachDevice(kept);
        },
      }).catch(() => conn.close(0, "refused"));
    }
  })();
  const http = new PeerHttp(here, hereCloud, (id) => ({ id }));
  const route = { tunnel: (s: string, p: number, probe?: boolean) => http.tunnel(s, p, probe), tunnelDevice: (s: string, dev: string, session: string, probe?: boolean) => http.tunnelDevice(s, dev, session, probe) };
  const forwards = new Forwards({
    route: () => route,
    resolve: (station) => {
      const { id } = peerNamed(hereCloud, station);
      return { id, name: roster.find((p) => p.id === id)!.name };
    },
    holders: async () => [4242],
  });
  try {
    let admitting = true;
    const admitted: number[][] = [];
    const target = { id: d.id, name: "cam", here: null, admit: async (holders: number[]) => (admitted.push(holders), admitting ? null : "this device's port is another chat's") };
    const v = await forwards.openDevice("s1", there.id(), target, false);
    assert.equal(v.device, "cam");
    assert.equal(v.station, "Studio");
    const port = Number(v.local.split(":")[1]);
    assert.deepEqual(asked, [`here/ws/s1/${d.id}/true`]);
    assert.equal(await talk(port, "hello"), "HELLO");
    assert.deepEqual(admitted, [[4242]]);
    // Asked again: the same forward.
    assert.equal((await forwards.openDevice("s1", there.id(), target, false)).note, "already forwarded");
    // Another chat's process: cut off, nothing carried.
    admitting = false;
    assert.match(await talk(port, "hi"), /^(cut: )?$/);
    assert.equal(asked.length, 2);
    // A device that station does not have: refused as it is asked for.
    await assert.rejects(forwards.openDevice("s1", there.id(), { ...target, id: "fedcba9876543210" }, false), /no such device/);
    // Handed back: its port is closed.
    forwards.closeDevice("s1", d.id, "handed back");
    assert.deepEqual(await forwards.list("s1"), []);
  } finally {
    await forwards.close();
    http.close();
    await Promise.all([here.close(), there.close()]);
    await cam.close();
  }
});

test("a device on this station itself: reached with no mesh between", async () => {
  const cam = await camera();
  const forwards = new Forwards({ route: () => null, resolve: (s) => ({ id: s, name: s }) });
  try {
    const v = await forwards.openDevice("s1", "self", { id: "0123456789abcdef", name: "cam", here: () => reachDevice({ id: "0123456789abcdef", name: "cam", kind: "tcp", target: `127.0.0.1:${cam.port}` }), admit: null }, true);
    assert.equal(await talk(Number(v.local.split(":")[1]), "local"), "LOCAL");
    assert.equal((await forwards.list("s1"))[0]!.station_state, "online");
  } finally {
    await forwards.close();
    await cam.close();
  }
});
