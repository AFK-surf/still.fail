// An app's modules in the core (src/module.ts, docs/core-modules.md): their calls answered by them, their topics computed
// by them from what they keep of a station, their requests under the station's `/m/<module>`; the core's own calls stay
// the core's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { parseCall } from "../src/core/calls.ts";
import { CoreError } from "../src/error.ts";
import type { CoreModule, ModuleEnv } from "../src/module.ts";
import type { Topic } from "../src/protocol.ts";
import { FakeHost } from "../src/testing.ts";
import { apply, answers, call, subscribe, v } from "./helpers.ts";
import { started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";

/// A shelf of books: `demo.books` read from the station as it is shown and kept, `demo.add` one written there.
function demo(log: string[]): CoreModule {
  return {
    name: "demo",
    install(env: ModuleEnv) {
      const topic = (station: string): Topic => ({ topic: "demo.books", station });
      const read = (station: string) =>
        env.request(station, "GET", "/books", null, { quiet: true }).pipe(
          Effect.tap((got) => Effect.sync(() => env.keep(station, "books", got, topic(station)))),
          Effect.ignore,
        );
      return {
        calls: {
          add: {
            parse(params) {
              const p = params as { station?: unknown; title?: unknown };
              if (typeof p?.station !== "string" || typeof p.title !== "string") throw CoreError.invalid("station and title");
              return { station: p.station, title: p.title };
            },
            run: (p: { station: string; title: string }) =>
              Effect.andThen(env.request(p.station, "POST", "/books", { title: p.title }), (made) => Effect.as(read(p.station), made)),
            station: (p: { station: string }) => p.station,
            counts: true,
          },
        },
        topics: {
          owns: (t) => t.topic === "demo.books",
          start: (t) => {
            log.push(`start ${String(t.station)}`);
            env.fork(read(String(t.station)));
          },
          compute: (t) => {
            const kept = env.kept(String(t.station), "books");
            return kept === undefined ? undefined : { ok: kept };
          },
        },
        keyed: { "demo.books": { fields: { books: { key: ["id"] } } } },
      };
    },
  };
}

test("a module's topic is read from its part of the station, kept, and its call goes there too", async () => {
  const log: string[] = [];
  let books = [{ id: "b1", title: "三体" }];
  const { host, core } = await started(undefined, 0, undefined, undefined, [demo(log)]);
  stationReplies(host, (req) => {
    if (req.url.endsWith("/admin/api/m/demo/books") && req.method === "GET") return { books };
    if (req.url.endsWith("/admin/api/m/demo/books") && req.method === "POST") {
      books = [...books, { id: "b2", title: "活着" }];
      return { id: "b2" };
    }
    return undefined;
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "demo.books", station: ST });
  await host.settle();
  assert.deepEqual(log, [`start ${ST}`]);
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).books.map((b: { title: string }) => b.title), ["三体"]);
  call(core, ui, 2, "demo.add", { station: ST, title: "活着" });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.deepEqual(answers(emitted, 2)?.ok, { id: "b2" });
  assert.ok(host.requests.some((r) => r.method === "POST" && r.url.endsWith("/admin/api/m/demo/books")));
  for (const [client, m] of emitted) host.emitted.push([client, m]);
  apply(host, values);
  assert.deepEqual(v(values, 1).books.map((b: { title: string }) => b.title), ["三体", "活着"]);
  core.close();
});

test("a UI's messages reach a module as they come, by JSON (as the hosts hand them over)", async () => {
  const books = [{ id: "b1", title: "三体" }];
  const { host, core } = await started(undefined, 0, undefined, undefined, [demo([])]);
  stationReplies(host, (req) => (req.url.endsWith("/admin/api/m/demo/books") ? { books } : undefined));
  const ui = core.connect();
  core.receiveJson(ui, JSON.stringify({ id: 1, subscribe: { topic: "demo.books", station: ST } }));
  // Not a module's, nor the core's: no such topic.
  core.receiveJson(ui, JSON.stringify({ id: 2, subscribe: { topic: "other.books", station: ST } }));
  // A module's topic's params are plain values.
  core.receiveJson(ui, JSON.stringify({ id: 3, subscribe: { topic: "demo.books", station: { nested: true } } }));
  core.receiveJson(ui, JSON.stringify({ id: 4, call: "demo.add", params: { station: ST } }));
  await host.settle();
  const emitted = host.takeEmitted();
  for (const [, m] of emitted) host.emitted.push([ui, m]);
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).books.map((b: { title: string }) => b.title), ["三体"]);
  assert.equal((answers(emitted, 2)?.error as CoreError).code, "bad_message");
  assert.equal((answers(emitted, 3)?.error as CoreError).code, "bad_message");
  assert.equal((answers(emitted, 4)?.error as CoreError).code, "invalid_params");
  core.close();
});

test("a module's call that is wrong, or that its station refuses, says why", async () => {
  const { host, core } = await started(undefined, 0, undefined, undefined, [demo([])]);
  stationReplies(host, (req) => (req.url.includes("/admin/api/m/demo/") ? status(503, { error: "模块没有运行" }) : undefined));
  const ui = core.connect();
  call(core, ui, 1, "demo.add", { station: ST });
  call(core, ui, 2, "demo.add", { station: ST, title: "x" });
  call(core, ui, 3, "demo.remove", { station: ST });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.equal((answers(emitted, 1)?.error as CoreError).code, "invalid_params");
  assert.equal((answers(emitted, 2)?.error as CoreError).message, "模块没有运行（10月6日 09:00:00）");
  assert.equal((answers(emitted, 3)?.error as CoreError).code, "unknown_call");
  core.close();
});

test("the core's own calls stay its own, and a module's name is its own", async () => {
  const shadow: CoreModule = { name: "auth", install: () => ({ calls: { begin: { parse: () => ({}), run: () => Effect.succeed("module") } } }) };
  const calls = new Map([["auth.begin", shadow.install(null as never).calls!.begin!]]);
  assert.equal(parseCall("auth.begin", { redirect_uri: "r", return_to: "/" }, undefined, calls).kind, "authBegin");
  assert.throws(() => parseCall("demo.nothing", {}, undefined, calls), (e: CoreError) => e.code === "unknown_call");
  const host = new FakeHost();
  const twice = Core.create(host, { clock: host.time.clock, modules: [demo([]), demo([])] });
  await assert.rejects(twice, /its own/);
  const badName = Core.create(new FakeHost(), { modules: [{ name: "Demo!", install: () => ({}) }] });
  await assert.rejects(badName, /its own/);
});
