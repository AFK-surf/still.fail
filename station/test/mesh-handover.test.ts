import assert from "node:assert/strict";
import { test, type TestContext } from "node:test";
import { Effect, Fiber, Layer, Stream, SubscriptionRef } from "effect";
import { MeshLive } from "../src/mesh/mesh.ts";
import { Net } from "../src/jobs/load.ts";
import { AdminApi, ControlPlane, Key, MeshNative, MeshSide, Own, Parts, Peers, Previous, ScreenRegistry, StationConfig, Store, Up } from "../src/services.ts";
import type { Mesh } from "../src/mesh/native.ts";
import { memoryMesh } from "./memory-mesh.ts";
import { StationParts } from "../src/parts.ts";
import { settle } from "./hub-fakes.ts";

function startup(t: TestContext, bindAddr: string | undefined, congestion?: "cubic" | "bbr") {
  const original = process.env.STILLFAIL_MESH_BIND_ADDR;
  if (bindAddr === undefined) delete process.env.STILLFAIL_MESH_BIND_ADDR;
  else process.env.STILLFAIL_MESH_BIND_ADDR = bindAddr;
  t.after(() => {
    if (original === undefined) delete process.env.STILLFAIL_MESH_BIND_ADDR;
    else process.env.STILLFAIL_MESH_BIND_ADDR = original;
  });
  const previous = Promise.withResolvers<void>();
  const built = Promise.withResolvers<void>();
  const binding = Promise.withResolvers<void>();
  const accepting = Promise.withResolvers<void>();
  let calls = 0;
  let presence = false;
  let boundCongestion: string | undefined;
  // The cloud's state as the mesh reads it once bound: a workspace, no relays, no other stations.
  const cloud = { state: { workspace_name: "ws" }, relays: () => [], memberships: () => [], peersCurrent: false, listen: () => () => {}, toolCalls: null };
  const inputs = Layer.mergeAll(
    Layer.succeed(MeshSide)({ net: new Net(), peers: { route: null }, outside: null, forwarded: () => false, runtimes: () => [] }),
    Layer.succeed(Previous)({ pid: null, gone: previous.promise }),
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
      const endpoint = await memoryMesh().bind(options);
      // Its relay link never up: no real sockets or timers in this scheduling regression.
      endpoint.online = () => new Promise<void>(() => {});
      const accept = endpoint.accept.bind(endpoint);
      endpoint.accept = () => {
        accepting.resolve();
        return accept();
      };
      return endpoint;
    } } as unknown as Mesh),
    Layer.succeed(Store)(null!), Layer.succeed(AdminApi)(null!),
    Layer.succeed(Up)(Effect.runSync(SubscriptionRef.make(true))), Layer.succeed(ScreenRegistry)(null!),
  );
  const running = Effect.runFork(Effect.scoped(Effect.gen(function* () {
    yield* Layer.build(MeshLive.pipe(Layer.provide(inputs)));
    built.resolve();
    yield* Effect.never;
  })));
  return { previous, built, binding, accepting, running, calls: () => calls, presence: () => presence, congestion: () => boundCongestion };
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
