import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { Effect, Fiber, Layer, Stream, SubscriptionRef } from "effect";
import { MeshLive } from "../src/mesh/mesh.ts";
import { Net } from "../src/jobs/load.ts";
import { AdminApi, ControlPlane, Events, Key, MeshNative, MeshSide, Own, Parts, Peers, Previous, ScreenRegistry, StationConfig, Store, Up } from "../src/services.ts";
import type { Endpoint, Mesh } from "../src/mesh/native.ts";
import { ALPN } from "../src/mesh/serve.ts";
import { hearLines, type Line } from "../src/ops/log.ts";
import { memoryMesh } from "./memory-mesh.ts";
import { StationParts } from "../src/parts.ts";
import { settle } from "./hub-fakes.ts";

function startup(t: TestContext, bindAddr: string | undefined, congestion?: "cubic" | "bbr", scenario: { front?: boolean; failures?: number } = {}) {
  const original = process.env.STILLFAIL_MESH_BIND_ADDR;
  const originalFront = process.env.STILLFAIL_MESH_FRONT;
  if (bindAddr === undefined) delete process.env.STILLFAIL_MESH_BIND_ADDR;
  else process.env.STILLFAIL_MESH_BIND_ADDR = bindAddr;
  if (scenario.front) process.env.STILLFAIL_MESH_FRONT = "/front.sock";
  else delete process.env.STILLFAIL_MESH_FRONT;
  t.after(() => {
    if (original === undefined) delete process.env.STILLFAIL_MESH_BIND_ADDR;
    else process.env.STILLFAIL_MESH_BIND_ADDR = original;
    if (originalFront === undefined) delete process.env.STILLFAIL_MESH_FRONT;
    else process.env.STILLFAIL_MESH_FRONT = originalFront;
  });
  const previous = Promise.withResolvers<void>();
  const exited = Promise.withResolvers<void>();
  const built = Promise.withResolvers<void>();
  const binding = Promise.withResolvers<void>();
  const accepting = Promise.withResolvers<void>();
  let calls = 0;
  let presence = false;
  let boundCongestion: string | undefined;
  // The cloud's state as the mesh reads it once bound: a workspace, no relays, no other stations.
  // (`data`: where it keeps what the mesh keeps of the locks, mesh/person-chains.ts)
  const cloud = { state: { workspace_name: "ws" }, data: mkdtempSync(join(tmpdir(), "mesh-handover-")), relays: () => [], memberships: () => [], peersCurrent: false, listen: () => () => {}, toolCalls: null, removed: () => false };
  // The mesh it is bound on: what a test binds there too reaches it.
  const mesh = memoryMesh();
  let station: Endpoint | null = null;
  const inputs = Layer.mergeAll(
    Layer.succeed(MeshSide)({ net: new Net(), peers: { route: null }, outside: null, forwarded: () => false, runtimes: () => [], device: null }),
    Layer.succeed(Previous)({ pid: scenario.front ? 123 : null, gone: previous.promise, exited: exited.promise }),
    Layer.succeed(Own)({ paths: () => [] } as never),
    Layer.succeed(Peers)({ attach: () => {} } as never),
    Layer.succeed(Parts)(new StationParts()),
    Layer.succeed(StationConfig)({ raw: () => ({ network: { congestion } }), listen: () => () => {} } as never),
    Layer.succeed(ControlPlane)({
      state: cloud,
      changes: Stream.never,
      presence: Effect.sync(() => (presence = true)).pipe(Effect.andThen(Effect.never)),
      spec: () => ({ name: "still.fail cloud", tools: false }),
      credential: () => undefined,
    } as never),
    Layer.succeed(Key)({ seed: Buffer.alloc(32) } as never),
    Layer.succeed(MeshNative)({ bind: async (options: Parameters<Mesh["bind"]>[0]) => {
      calls++;
      boundCongestion = options.congestion;
      binding.resolve();
      if (calls <= (scenario.failures ?? 0)) throw new Error("port is held by the previous station");
      const endpoint = await mesh.bind(options);
      station = endpoint;
      // Its relay link never up: no real sockets or timers in this scheduling regression.
      endpoint.online = () => new Promise<void>(() => {});
      const accept = endpoint.accept.bind(endpoint);
      endpoint.accept = () => {
        accepting.resolve();
        return accept();
      };
      return endpoint;
    } } as unknown as Mesh),
    Layer.succeed(Store)(null!), Layer.succeed(AdminApi)(null!), Layer.succeed(Events)({ tell: () => {} } as never),
    Layer.succeed(Up)(Effect.runSync(SubscriptionRef.make(true))), Layer.succeed(ScreenRegistry)(null!),
  );
  const running = Effect.runFork(Effect.scoped(Effect.gen(function* () {
    yield* Layer.build(MeshLive.pipe(Layer.provide(inputs)));
    built.resolve();
    yield* Effect.never;
  })));
  return { previous, exited, built, binding, accepting, running, mesh, station: () => station!, calls: () => calls, presence: () => presence, congestion: () => boundCongestion };
}

test("the mesh starts with its saved controller, cubic when no choice was made", async (t) => {
  for (const choice of [undefined, "bbr", "cubic"] as const) {
    const s = startup(t, undefined, choice);
    try {
      await s.accepting.promise;
      assert.equal(s.congestion(), choice ?? "cubic");
    } finally { await Effect.runPromise(Fiber.interrupt(s.running)); }
  }
});

test("a connection is served as it comes beside the others, said as its serving fails, and closed as that ends or the station stops", async (t) => {
  const lines: Line[] = [];
  hearLines((l) => void (l.at === "mesh" && l.message === "connection ended" && lines.push(l)));
  t.after(() => hearLines(null));
  const s = startup(t, undefined);
  let stopped = false;
  const stop = () => (stopped ? Promise.resolve() : ((stopped = true), Effect.runPromise(Fiber.interrupt(s.running))));
  try {
    await s.accepting.promise;
    const device = await s.mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [] });
    t.after(() => device.close());
    // Two at once: neither waits for the other's hello.
    const [quiet, wordless] = await Promise.all([device.connect({ id: s.station().id() }, ALPN), device.connect({ id: s.station().id() }, ALPN)]);
    await quiet.openBi();
    // One whose control stream ends with no hello: its serving fails, which is said, and it is closed.
    await (await wordless.openBi()).finish();
    assert.equal(await wordless.closed(), "station stopping");
    assert.deepEqual(lines.map((l) => [l.level, l.fields]), [["INFO", { error: "Error: no credential" }]]);
    assert.equal(quiet.isClosed(), false);
    // The station stops: the one still being served is closed by it, before its endpoint is.
    await stop();
    assert.equal(await quiet.closed(), "station stopping");
    assert.equal(lines.length, 1);
  } finally { await stop(); }
});

test("a station takes its members' connections before its relay link is up, and goes online at the cloud only after", { timeout: 10_000 }, async (t) => {
  const s = startup(t, "0.0.0.0:0");
  try {
    await s.built.promise;
    await s.accepting.promise;
    await settle();
    assert.equal(s.presence(), false);
  } finally {
    await Effect.runPromise(Fiber.interrupt(s.running));
    s.previous.resolve();
  }
});

test("startup can signal ready while the old station still owns its mesh port", async (t) => {
  const s = startup(t, "0.0.0.0:4770");
  try {
    await s.built.promise; // main can now signal ready, letting the launcher stop the old process.
    await settle();
    assert.equal(s.calls(), 0);
    s.previous.resolve();
    await s.binding.promise;
    assert.equal(s.calls(), 1);
  } finally {
    await Effect.runPromise(Fiber.interrupt(s.running));
  }
});

test("a station stopped during handover does not bind after its predecessor exits", async (t) => {
  const s = startup(t, "0.0.0.0:4770");
  await s.built.promise;
  await Effect.runPromise(Fiber.interrupt(s.running));
  s.previous.resolve();
  await settle();
  assert.equal(s.calls(), 0);
});

test("the front binds again after its predecessor releases the fixed port", async (t) => {
  const s = startup(t, "0.0.0.0:4770", undefined, { front: true, failures: 1 });
  try {
    await s.built.promise;
    await s.binding.promise;
    await settle();
    assert.equal(s.calls(), 1);
    s.previous.resolve();
    await settle();
    assert.equal(s.calls(), 1); // A timed-out handover does not mean the old process has exited.
    s.exited.resolve();
    await settle();
    assert.equal(s.calls(), 2);
    await s.accepting.promise;
  } finally {
    await Effect.runPromise(Fiber.interrupt(s.running));
  }
});

test("the front takes over an existing endpoint before its predecessor exits", async (t) => {
  const s = startup(t, "0.0.0.0:4770", undefined, { front: true });
  try {
    await s.built.promise;
    await s.accepting.promise;
    assert.equal(s.calls(), 1);
  } finally {
    await Effect.runPromise(Fiber.interrupt(s.running));
    s.previous.resolve();
  }
});

test("a stopped station does not retry the front's failed bind", async (t) => {
  const s = startup(t, "0.0.0.0:4770", undefined, { front: true, failures: 1 });
  await s.built.promise;
  await s.binding.promise;
  await Effect.runPromise(Fiber.interrupt(s.running));
  s.previous.resolve();
  s.exited.resolve();
  await settle();
  assert.equal(s.calls(), 1);
});

for (const bindAddr of [undefined, "0.0.0.0:0", "[::]:0"]) {
  test(`random-port mesh starts before its predecessor exits (${bindAddr ?? "default"})`, async (t) => {
    const s = startup(t, bindAddr);
    try {
      await s.built.promise;
      await settle();
      assert.equal(s.calls(), 1);
    } finally {
      await Effect.runPromise(Fiber.interrupt(s.running));
      s.previous.resolve();
    }
  });
}
