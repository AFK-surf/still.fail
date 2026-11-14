// A chat's Farview tab in its own protocol (src/farview.ts): what the calls take, the stream's bytes handed to the app
// as they come, what the app says carried in order, a stream that drops opened again as a new conversation, and a
// refusal ending the view. The station's side is station/test/farview.test.ts.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { parseFarview } from "../src/farview.ts";
import { HostWire, type RequestHead, type StationWire } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { apply, call, subscribe } from "./helpers.ts";
import { base, started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const station = "ws/st";

test("a view names its station, its tab and itself; what is said goes as bytes beside the call", () => {
  assert.deepEqual(parseFarview("farview.view", { station, screen: "browser:fv_1", view: "v1" }), { kind: "view", station, screen: "browser:fv_1", view: "v1" });
  assert.throws(() => parseFarview("farview.view", { station, view: "v1" }));
  assert.deepEqual(parseFarview("farview.send", { view: "v1" }, Uint8Array.of(1, 2)), { kind: "send", view: "v1", data: Uint8Array.of(1, 2) });
  assert.throws(() => parseFarview("farview.send", { view: "v1" }));
  assert.equal(parseFarview("screen.view", {}), null);
});

type Open = { head: RequestHead; screen: string; got: number[]; send(bytes: number[]): void; end(): void };

function farviewWire(answer: () => number) {
  const opens: Open[] = [];
  const make = (host: FakeHost): StationWire => {
    const plain = new HostWire(host);
    return {
      request: (s, head, body) => plain.request(s, head, body),
      farview: (_station, head, screen) =>
        Effect.gen(function* () {
          const queue = yield* Queue.unbounded<Uint8Array | null>();
          const o: Open = { head, screen, got: [], send: (b) => void Queue.offerUnsafe(queue, Uint8Array.from(b)), end: () => void Queue.offerUnsafe(queue, null) };
          opens.push(o);
          const status = answer();
          if (status !== 200) {
            o.send([...new TextEncoder().encode(JSON.stringify({ error: "no such tab" }))]);
            o.end();
          }
          return {
            reply: { status, headers: [["content-type", "application/x-farview"]] as [string, string][], body: { take: Queue.take(queue) }, via: null },
            send: { write: (bytes: Uint8Array) => Effect.sync(() => void o.got.push(...bytes)), finish: () => {} },
          };
        }),
    };
  };
  return { opens, make };
}

const said = (host: FakeHost, id: number) =>
  host
    .takeEmitted()
    .map(([, m]) => m as J)
    .filter((m) => m.id === id && "value" in m)
    .map((m) => (m.value.state ? m.value.state.phase + (m.value.state.opens ? `#${m.value.state.opens}` : "") : [...m.bytes]));

test("the host's bytes come to the app as they come, the app's go to it in order, a drop opens a new conversation", async () => {
  const wire = farviewWire(() => 200);
  const { host, core } = await started(base(), 0, wire.make);
  const ui = core.connect();
  call(core, ui, 1, "farview.view", { station, screen: "browser:fv_1", view: "v1" });
  await host.settle();
  assert.equal(wire.opens.length, 1);
  assert.equal(wire.opens[0]!.screen, "browser:fv_1");
  assert.deepEqual(said(host, 1), ["connecting", "live#1"]);
  wire.opens[0]!.send([0, 0, 0, 1]);
  wire.opens[0]!.send([7]);
  call(core, ui, 2, "farview.send", { view: "v1" }, Uint8Array.of(9, 8));
  call(core, ui, 3, "farview.send", { view: "v1" }, Uint8Array.of(7));
  await host.settle();
  assert.deepEqual(said(host, 1), [[0, 0, 0, 1], [7]]);
  assert.deepEqual(wire.opens[0]!.got, [9, 8, 7]);
  // The stream drops: opened again, the app told it is a new conversation (its Hello said anew).
  wire.opens[0]!.end();
  await host.time.pass(2_000);
  assert.equal(wire.opens.length, 2);
  assert.deepEqual(said(host, 1), ["reconnecting", "live#2"]);
  call(core, ui, 4, "farview.send", { view: "v1" }, Uint8Array.of(5));
  await host.settle();
  assert.deepEqual(wire.opens[1]!.got, [5]);
  // Let go of: what it says after goes nowhere.
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  call(core, ui, 5, "farview.send", { view: "v1" }, Uint8Array.of(1));
  await host.settle();
  const answer = host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === 5);
  assert.equal(answer?.error?.code, "not_found");
  core.close();
});

test("a tab the station does not have ends the view, saying so", async () => {
  const wire = farviewWire(() => 404);
  const { host, core } = await started(base(), 0, wire.make);
  const ui = core.connect();
  call(core, ui, 1, "farview.view", { station, screen: "browser:fv_gone", view: "v1" });
  await host.settle();
  assert.deepEqual(said(host, 1), ["connecting", "gone"]);
  assert.equal(wire.opens.length, 1);
  core.close();
});

test("the screens' list says which tab is a Farview tab", async () => {
  const wire = farviewWire(() => 200);
  const screens = { screens: [{ id: "browser:fv_1", kind: "browser", title: "Proton", width: 1280, height: 800, viewers: [], farview: true }, { id: "browser:T1", kind: "browser", title: "x", width: 1280, height: 800, viewers: [] }] };
  const { host, core } = await started({ ...base(), "GET /screens": screens }, 0, wire.make);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station });
  await host.settle();
  apply(host, values);
  assert.deepEqual((values.get(1) as J).screens.map((s: J) => [s.id, s.farview === true]), [["browser:fv_1", true], ["browser:T1", false]]);
  core.close();
});
