// An endpoint's connections taken (src/mesh/accept.ts), as the station takes its own (src/mesh/mesh.ts, src/rig/main.ts):
// what is done of each, in what order, how each ends, and what stopping does to them. The endpoint and its connections
// are the test's: nothing here is the mesh's, and nothing waits on time.
import assert from "node:assert/strict";
import { test, type TestContext } from "node:test";
import { Cause, Effect, Exit, Fiber, FiberSet, Scope } from "effect";
import { accept, type Taken } from "../src/mesh/accept.ts";
import type { Connection } from "../src/mesh/endpoint.ts";
import { hearLines } from "../src/ops/log.ts";

const take = accept;

/// An endpoint that gives the connections the test says, and all that is done of them and said in the log, in order.
function world(t: TestContext) {
  const trace: string[] = [];
  let waiting: { entry: string; go: () => void }[] = [];
  const say = (entry: string) => {
    trace.push(entry);
    for (const w of waiting.filter((w) => w.entry === entry)) w.go();
    waiting = waiting.filter((w) => w.entry !== entry);
  };
  /// Once the trace says `entry` (it may already).
  const until = (entry: string) => (trace.includes(entry) ? Promise.resolve() : new Promise<void>((go) => waiting.push({ entry, go })));
  hearLines((l) => say(`log ${l.level} ${l.at}: ${l.message} ${JSON.stringify(l.fields)}`));
  t.after(() => hearLines(null));
  let give: ((conn: Connection | null) => void) | null = null;
  let fail: ((error: Error) => void) | null = null;
  let asked = 0;
  const endpoint = {
    accept: () => {
      say(`accept ${++asked}`);
      return new Promise<Connection | null>((resolve, reject) => ((give = resolve), (fail = reject)));
    },
  };
  /// How each connection's serving ends, by its name.
  const serving = new Map<string, { done: () => void; failed: (e: unknown) => void }>();
  const names = new Map<Connection, string>();
  /// The endpoint gives a connection of this name, once it is asked for one: until what serves it was called and the
  /// next is asked for.
  const arrive = async (name: string) => {
    const conn = { close: (code: number, reason: string) => say(`close ${name} ${code} ${reason}`) } as Connection;
    names.set(conn, name);
    await until(`accept ${asked || 1}`);
    const next = `accept ${asked + 1}`;
    give!(conn);
    await Promise.all([until(`serve ${name}`), until(next)]);
  };
  const how: Taken = {
    arrived: (conn) => say(`arrived ${names.get(conn)}`),
    serve: (conn) => {
      const name = names.get(conn)!;
      say(`serve ${name}`);
      if (name.startsWith("thrown")) throw new Error(`${name} threw`);
      return new Promise<void>((done, failed) => serving.set(name, { done, failed }));
    },
    closing: "stopping",
  };
  return { trace, until, endpoint, how, arrive, serving, names, none: () => give!(null), broken: (e: Error) => fail!(e) };
}

test("each connection is watched, then served beside the others, and closed once it is served no more", async (t) => {
  const w = world(t);
  const running = Effect.runFork(Effect.scoped(take(w.endpoint, w.how)));
  await w.arrive("a");
  await w.arrive("b");
  // Served to its end.
  w.serving.get("a")!.done();
  await w.until("close a 0 stopping");
  // Its serving failed: said, and closed.
  w.serving.get("b")!.failed(new Error("no credential"));
  await w.until("close b 0 stopping");
  // What serves it threw before it began.
  await w.arrive("thrown c");
  await w.until("close thrown c 0 stopping");
  // The endpoint closed: no more are taken.
  w.none();
  assert.ok(Exit.isSuccess(await Effect.runPromise(Fiber.await(running))));
  assert.deepEqual(w.trace, [
    "accept 1",
    "arrived a", "serve a", "accept 2",
    "arrived b", "serve b", "accept 3",
    "close a 0 stopping",
    'log INFO mesh: connection ended {"error":"Error: no credential"}', "close b 0 stopping",
    "arrived thrown c", "serve thrown c", 'log INFO mesh: connection ended {"error":"Error: thrown c threw"}', "close thrown c 0 stopping", "accept 4",
  ]);
});

test("stopping closes every connection being served, with the reason given", async (t) => {
  const w = world(t);
  const running = Effect.runFork(Effect.scoped(take(w.endpoint, w.how)));
  await w.arrive("a");
  await w.arrive("b");
  await Effect.runPromise(Fiber.interrupt(running));
  assert.deepEqual(w.trace, ["accept 1", "arrived a", "serve a", "accept 2", "arrived b", "serve b", "accept 3", "close a 0 stopping", "close b 0 stopping"]);
});

test("an endpoint that gives no more ends the taking, and its connections with the scope their fibers are of", async (t) => {
  // The taking's own scope: they end as it returns.
  const own = world(t);
  const running = Effect.runFork(Effect.scoped(take(own.endpoint, own.how)));
  await own.arrive("a");
  own.none();
  assert.ok(Exit.isSuccess(await Effect.runPromise(Fiber.await(running))));
  assert.deepEqual(own.trace, ["accept 1", "arrived a", "serve a", "accept 2", "close a 0 stopping"]);
  // A set of the caller's: they are served until its scope closes (the station's, made before what is to stop first).
  const given = world(t);
  const scope = Effect.runSync(Scope.make());
  const connections = Effect.runSync(Scope.provide(FiberSet.make(), scope));
  const taking = Effect.runFork(Effect.scoped(take(given.endpoint, { ...given.how, connections })));
  await given.arrive("a");
  given.none();
  assert.ok(Exit.isSuccess(await Effect.runPromise(Fiber.await(taking))));
  assert.deepEqual(given.trace, ["accept 1", "arrived a", "serve a", "accept 2"]);
  await Effect.runPromise(Scope.close(scope, Exit.void));
  assert.deepEqual(given.trace, ["accept 1", "arrived a", "serve a", "accept 2", "close a 0 stopping"]);
});

test("what is said of a connection whose serving failed is the caller's where it gives it", async (t) => {
  const w = world(t);
  const running = Effect.runFork(Effect.scoped(take(w.endpoint, { ...w.how, failed: (error, conn) => void w.trace.push(`failed ${w.names.get(conn)}: ${String(error)}`) })));
  await w.arrive("a");
  w.serving.get("a")!.failed(new Error("no credential"));
  await w.until("close a 0 stopping");
  await Effect.runPromise(Fiber.interrupt(running));
  assert.deepEqual(w.trace, ["accept 1", "arrived a", "serve a", "accept 2", "failed a: Error: no credential", "close a 0 stopping"]);
});

test("an endpoint whose accept fails is asked no more: the taking dies of it, its connections closed", async (t) => {
  const w = world(t);
  const running = Effect.runFork(Effect.scoped(take(w.endpoint, w.how)));
  await w.arrive("a");
  w.broken(new Error("endpoint gone"));
  const exit = await Effect.runPromise(Fiber.await(running));
  assert.ok(Exit.isFailure(exit) && !Cause.hasInterruptsOnly(exit.cause));
  assert.match(Cause.pretty(exit.cause), /endpoint gone/);
  assert.deepEqual(w.trace, ["accept 1", "arrived a", "serve a", "accept 2", "close a 0 stopping"]);
});
