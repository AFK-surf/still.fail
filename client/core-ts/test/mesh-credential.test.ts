// The production Cloud, WakingHost and Mesh, on the existing
// simulated transport and clock. No real network, credentials, or wall-clock waits.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Accounts, STORAGE_KEY } from "../src/accounts.ts";
import { Cloud } from "../src/cloud.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Mesh, type CredentialSource } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { Status } from "../src/status.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { Wake, Wakes, WakingHost } from "../src/wake.ts";
import { Station } from "./mesh-station.ts";
import { SimNet, SimTime } from "./sim-iroh.ts";

holdLanguage();

for (const seed of [1, 2, 3, 4]) {
  for (const announcesRecovery of [false, true]) {
    test(`default mesh recovers from a silent credential request; network event=${announcesRecovery}; seed=${seed}`, async () => {
      const time = new SimTime();
      const net = new SimNet(time.clock, seed);
      const host = new FakeHost(time);
      const wakes = new Wakes();
      const waking = new WakingHost(host, wakes);
      const runner = new Runner(time.clock);
      const run = <A, E>(effect: Effect.Effect<A, E>) => time.settle(runner.run(effect));
      const relay = net.relay("https://credential.relay.test/", { device: { ms: 20 }, station: { ms: 20 } });
      const station = await time.settle(Station.on(relay, [], net.world()));
      const tracer = new Tracer(host, runner, 1);
      const meshes: Mesh[] = [];
      host.store(STORAGE_KEY, [{ sub: "review", email: "review@example.test", name: "Review", picture: "", access: "fake-access", refresh: "fake-refresh", access_expires: time.now() / 1000 + 86_400 }]);
      const accounts = await run(Accounts.load(waking));
      const cloud = new Cloud(waking, accounts, tracer, new Status(host, runner));
      let asks = 0;
      host.onFetch((request) => {
        assert.ok(request.url.endsWith("/credential"), request.url);
        asks++;
        // This request's old connection never answers; every subsequent request
        // can succeed. The device remains on the same interface and in foreground.
        if (asks === 1) return new Promise(() => {});
        return jsonResponse(200, { credential: "ok-review", issued_at: time.now() / 1000, expires_at: time.now() / 1000 + 86_400, relay_url: relay });
      });
      const credentials: CredentialSource = (device) => cloud.credential("review", "review-workspace", device);
      const make = async () => {
        const mesh = await run(Mesh.make({ host: waking, runner, tracer, iroh: net.iroh(), wakes }, [relay]));
        meshes.push(mesh);
        return mesh;
      };
      const states = { first: "pending", retry: "pending" };
      try {
        const mesh = await make();
        void runner.run(Effect.result(mesh.link(station.id(), credentials))).then((r) => { states.first = r._tag; });
        await time.pass(60_000);
        assert.equal(asks, 1);
        assert.equal(station.firsts.length, 0, "no authenticated-client log despite the transport handshake");
        const handshakes = station.conns.length;
        void runner.run(Effect.result(mesh.link(station.id(), credentials))).then((r) => { states.retry = r._tag; });
        if (announcesRecovery) wakes.wake(new Wake(host.nowMs(), 0, true, false));
        await time.pass(30 * 60_000);
        const beforeRestart = { ...states, credentialRequests: asks, transportHandshakes: handshakes, authenticatedConnections: station.firsts.length };
        // Control: same host, credentials, relay and station, only the mesh state
        // recreated as a process restart would. This must work on the same network.
        await run(mesh.close());
        const again = await make();
        const link = await run(again.link(station.id(), credentials));
        const reply = await run(link.request({ method: "GET", path: "/admin/api/overview", headers: [] }, new Uint8Array()));
        assert.equal(reply.status, 200);
        assert.equal(beforeRestart.retry, "Success", "a recovered network must not leave the next send joining an old Opening forever");
      } finally {
        for (const mesh of meshes) await run(mesh.close());
        await time.settle(station.close());
        runner.shutdown();
      }
    });
  }
}
