// A whole file asked again while it is coming (a preview closed and opened again, an image put up anew) waits for the read
// going, told how far it has come, rather than being brought again beside it: a desktop app had six images coming fifteen
// times at once from ccvm, each at a fifteenth of the line (2026-10-28).
import assert from "node:assert/strict";
import { test } from "node:test";
import type { HttpResponse } from "../src/host.ts";
import { call } from "./helpers.ts";
import { base, started, stationLater } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

test("a_whole_file_asked_again_while_it_comes_is_read_once", async () => {
  const { host, core } = await started(base());
  const asked: string[] = [];
  let answer: ((r: HttpResponse) => void) | null = null;
  stationLater(host, (req) => {
    if (!req.url.includes("/admin/api/sessions/k1/files?")) return undefined;
    asked.push(req.url);
    return new Promise<HttpResponse>((resolve) => (answer = resolve));
  });
  const ui = core.connect();
  call(core, ui, 1, "station.file", { station: "ws/st", key: "k1", name: "a.png", progress: true });
  await host.settle();
  call(core, ui, 2, "station.file", { station: "ws/st", key: "k1", name: "a.png", progress: true });
  await host.settle();
  assert.equal(asked.length, 1, "asked of the station once");
  answer!({ status: 200, headers: [["content-type", "image/png"]], body: new Uint8Array([1, 2, 3]) });
  await host.settle();
  await host.settle();
  const done = host.takeEmitted().map(([, m]) => m as J).filter((m) => (m.id === 1 || m.id === 2) && ("ok" in m || "error" in m));
  assert.deepEqual(done.map((m) => [m.id, m.ok?.type, m.error?.message]).sort(), [[1, "image/png", undefined], [2, "image/png", undefined]]);
  // Come and gone: asked again, it is read again.
  call(core, ui, 3, "station.file", { station: "ws/st", key: "k1", name: "a.png" });
  await host.settle();
  assert.equal(asked.length, 2);
  core.close();
});
