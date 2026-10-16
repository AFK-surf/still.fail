import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Fiber, Layer } from "effect";
import { MeshLive } from "../src/mesh/mesh.ts";
import { Agents, type AgentsParts } from "../src/sessions/agents.ts";
import { AdbShares, AdminApi, ControlPlane, Key, MeshNative, Store, Up } from "../src/services.ts";
import type { Mesh } from "../src/mesh/native.ts";
import { memoryMesh } from "./memory-mesh.ts";
import { settle } from "./hub-fakes.ts";

function startup() {
  const previous = Promise.withResolvers<void>();
  const built = Promise.withResolvers<void>();
  const binding = Promise.withResolvers<void>();
  let calls = 0;
  const inputs = Layer.mergeAll(
    Layer.succeed(Agents)({ previousGone: previous.promise } as AgentsParts),
    Layer.succeed(ControlPlane)({ state: { state: {}, relays: () => [] } } as never),
    Layer.succeed(Key)({ seed: Buffer.alloc(32) } as never),
    Layer.succeed(MeshNative)({ bind: async (options: Parameters<Mesh["bind"]>[0]) => {
      calls++;
      binding.resolve();
      const endpoint = await memoryMesh().bind(options);
      // Stay before control-plane presence: no real sockets or timers in this scheduling regression.
      endpoint.online = () => new Promise<void>(() => {});
      return endpoint;
    } } as unknown as Mesh),
    Layer.succeed(Store)(null!), Layer.succeed(AdminApi)(null!),
    Layer.succeed(Up)(null!), Layer.succeed(AdbShares)(null!),
  );
  const running = Effect.runFork(Effect.scoped(Effect.gen(function* () {
    yield* Layer.build(MeshLive.pipe(Layer.provide(inputs)));
    built.resolve();
    yield* Effect.never;
  })));
  return { previous, built, binding, running, calls: () => calls };
}

test("startup can signal ready while the old station still owns its mesh port", async () => {
  const s = startup();
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

test("a station stopped during handover does not bind after its predecessor exits", async () => {
  const s = startup();
  await s.built.promise;
  await Effect.runPromise(Fiber.interrupt(s.running));
  s.previous.resolve();
  await settle();
  assert.equal(s.calls(), 0);
});
