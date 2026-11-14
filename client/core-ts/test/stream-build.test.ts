// Screen views and preview sockets identify this core just as ordinary requests do: a station with a build floor
// otherwise mistakes a current app for a core from before builds were said.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { StationAddr } from "../src/station/addr.ts";
import { ownBuild, setOwnBuild } from "../src/station/oldest.ts";
import { HostWire, type RequestHead, type WireSocket } from "../src/station/wire.ts";
import { base, started } from "./station-fixture.ts";

for (const build of ["0.1.8190", ""]) {
  test(`screen and preview streams say the core build (${build || "unnumbered host"})`, async () => {
    const heads: RequestHead[] = [];
    const { core } = await started(base(), 0, (host) => {
      const plain = new HostWire(host);
      const open = (head: RequestHead, status: number): Effect.Effect<WireSocket> => {
        heads.push(head);
        return Effect.succeed({
          reply: { status, headers: [], body: { take: Effect.succeed(null) }, via: null },
          send: { write: () => Effect.void, finish: () => {} },
        });
      };
      return {
        request: (station, head, body) => plain.request(station, head, body),
        screen: (_station, head) => open(head, 200),
        socket: (_station, head) => open(head, 101),
      };
    });
    const previous = ownBuild();
    setOwnBuild(build);
    try {
      const station = StationAddr.parse("ws/st");
      const requests = core.inner.stations.requests;
      await core.inner.runner.run(Effect.scoped(requests.screenView(station, "browser:T1", { maxWidth: 1280, maxHeight: 800, codecs: ["jpeg"], control: true }, null)));
      await core.inner.runner.run(Effect.scoped(requests.previewSocket(station, 5180, "/live", [["sec-websocket-protocol", "test"]], null)));
      assert.deepEqual(heads.map((h) => h.path), ["/admin/api/screens/browser%3AT1/view", "/admin/api/preview/5180/live"]);
      for (const head of heads) {
        assert.deepEqual(head.headers.filter(([k]) => k === "stillfail-build"), [["stillfail-build", build || "0.1.0"]], head.path);
        assert.ok(head.headers.some(([k, v]) => k === "stillfail-lang" && v.length > 0), head.path);
        assert.ok(head.headers.some(([k]) => k === "traceparent"), head.path);
      }
      assert.ok(heads[1].headers.some(([k, v]) => k === "sec-websocket-protocol" && v === "test"));
    } finally {
      setOwnBuild(previous);
      core.close();
    }
  });
}
