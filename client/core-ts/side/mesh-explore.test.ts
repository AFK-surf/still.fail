// The side run's (not CI's): the mesh on simulated networks made up at random (sim-iroh.ts), each with things befalling
// it (relays slowing, going down, the station's connections dropped, the network changing under the device) while the
// core asks what it does, and what must hold whatever happened:
// - every request is answered or fails; none waits forever;
// - a write the station does not say it keeps to once is carried out at most once;
// - once all is well again, a read is answered;
// - left to choose a while once all is well, the requests go through a relay not clearly slower than the quickest;
// - closed, nothing of it is left open.
// SIM_EXPLORE=<runs> (200) networks; a failure names the seed its network was made from, and SIM_SEED=<seed> makes the
// same one again, for an agent to reproduce it as a test in test/mesh.test.ts.
import assert from "node:assert/strict";
import { randomInt } from "node:crypto";
import { test } from "node:test";
import { Effect } from "effect";
import type { Credential } from "../src/cloud.ts";
import { holdLanguage } from "../src/i18n.ts";
import { ALPN, cost, EXPLORE_MS, FORMER_ALPN, Mesh, MeshWire, MOVE_GAIN, type CredentialSource } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { readAll, type RequestHead } from "../src/station/wire.ts";
import { Status } from "../src/status.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { Wake, Wakes } from "../src/wake.ts";
import { Station } from "../test/mesh-station.ts";
import { type Leg, Rng, SimNet, SimTime } from "../test/sim-iroh.ts";

holdLanguage();

const RUNS = Number(process.env.SIM_EXPLORE ?? 200);
const SEEDS = process.env.SIM_SEED ? [Number(process.env.SIM_SEED)] : Array.from({ length: RUNS }, () => randomInt(1, 2 ** 31));
/// How long, once all is well again, a read may take.
const RECOVER_MS = 2 * 60_000;
/// How much slower than the quickest relay the requests may stay: what a move asks of the way moved to (MOVE_GAIN
/// quicker), and the jitter of pinging (up to 3 ms each way of a round trip, a few of them).
const slowest = (best: number) => best / (1 - MOVE_GAIN) + 12;

const grants: CredentialSource = () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential);

function leg(rng: Rng, fast: boolean): Leg {
  const ms = rng.int(0, 150);
  return !fast && rng.next() < 0.3 ? { ms, bps: rng.int(64, 4096) * 1024 } : { ms };
}

async function explore(seed: number): Promise<void> {
  const rng = new Rng(seed);
  const time = new SimTime();
  const net = new SimNet(time.clock, seed);
  const host = new FakeHost(time);
  const runner = new Runner(time.clock);
  const wakes = new Wakes();
  const world = net.world();
  const failures: string[] = [];
  try {
    // The relays, the station at home on one and held on the others, the device on some.
    const relays = Array.from({ length: rng.int(1, 3) }, (_, i) => net.relay(`https://r${i}.relay.test/`, { device: leg(rng, false), station: leg(rng, true) }));
    const home = relays[rng.int(0, relays.length - 1)]!;
    const station = await time.settle(Station.bound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [home], discovery: false, relayOnly: true }, world));
    await time.settle(station.endpoint.online());
    station.endpoint.keep(relays.filter((r) => r !== home));
    station.idempotent = rng.next() < 0.5;
    const mine = rng.next() < 0.5 ? relays : relays.filter(() => rng.next() < 0.6);
    const deviceRelays = mine.length > 0 ? mine : [relays[0]!];
    const env = { host, runner, tracer: new Tracer(host, runner, 1), iroh: net.iroh(), wakes };
    const mesh = await time.settle(runner.run(Mesh.make(env, deviceRelays)));
    const id = station.id();
    mesh.addAddr({ id, relays: [home] });
    net.note(`station at home on ${home}${station.idempotent ? ", keeps writes to once" : ""}; device on ${deviceRelays.join(", ")}`);
    const status = new Status(host, runner);
    const wire = new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials: () => grants, relays: () => [], status: () => status });
    const addr = StationAddr.parse(`w/${id}`);
    const ask = (h: RequestHead) => runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));

    // What befalls it, one thing after another; what it asks meanwhile.
    const asked: { what: string; settled: boolean; outcome: string }[] = [];
    let wellAt = time.now();
    const events = rng.int(5, 20);
    for (let k = 0; k < events; k++) {
      await time.pass(rng.int(0, 60_000));
      const r = relays[rng.int(0, relays.length - 1)]!;
      const kind = rng.int(0, 8);
      const request = (h: RequestHead, what: string) => {
        net.note(`asks ${what}`);
        const entry = { what: `${what} (${net.log.at(-1)!.split(":")[0]})`, settled: false, outcome: "" };
        asked.push(entry);
        void ask(h).then(
          (s) => Object.assign(entry, { settled: true, outcome: `${s}` }),
          (e) => Object.assign(entry, { settled: true, outcome: `failed: ${e?.message ?? e}` }),
        );
      };
      if (kind <= 2) request({ method: "GET", path: "/admin/api/overview", headers: [] }, "a read");
      else if (kind === 3) request({ method: "GET", path: "/admin/api/big", headers: [] }, "a large read");
      else if (kind === 4) request({ method: "POST", path: "/admin/api/x", headers: [["idempotency-key", `k${k}`]] }, `a write (k${k})`);
      else if (kind === 5) {
        net.note("the network changes under the device");
        wakes.wake(new Wake(host.nowMs(), 0, true, false));
      } else if (kind === 6) {
        // Its round trips change; how fast its lines are stays (what the mesh keeps of it for hours, SPEED_KEPT_MS).
        const [d, st] = [net.leg(r, "device"), net.leg(r, "station")];
        net.relay(r, { device: { ...d, ms: rng.int(0, 150) }, station: { ...st, ms: rng.int(0, 150) } });
      } else if (kind === 7) {
        const ms = rng.int(1000, 90_000);
        net.down(r, ms);
        wellAt = Math.max(wellAt, time.now() + ms);
      } else {
        const open = station.conns.filter((c) => !c.isClosed());
        if (open.length > 0) {
          net.note("the station drops a connection");
          open[rng.int(0, open.length - 1)].close(0, "restart");
        }
      }
    }

    // All is well again: what was asked is answered or failed, a read is answered.
    await time.pass(Math.max(0, wellAt - time.now()));
    net.note("all is well again");
    await time.until(() => asked.every((a) => a.settled), 10 * 60_000).catch(() => {});
    for (const a of asked) if (!a.settled) failures.push(`${a.what}: never answered nor failed`);
    let read = "";
    await time
      .settle(
        ask({ method: "GET", path: "/admin/api/overview", headers: [] }).then(
          (s) => (read = `${s}`),
          (e) => (read = `failed: ${e?.message ?? e}`),
        ),
        RECOVER_MS,
      )
      .catch(() => (read = `not answered within ${RECOVER_MS} ms`));
    if (read !== "200") failures.push(`a read once all is well: ${read}`);

    // Writes the station does not keep to once: carried out once at most.
    if (!station.idempotent) {
      const keys = station.served.filter((h) => h.method === "POST").map((h) => h.headers?.["idempotency-key"]);
      const twice = keys.filter((k, i) => keys.indexOf(k) !== i);
      if (twice.length > 0) failures.push(`writes carried out twice: ${[...new Set(twice)].join(", ")}`);
    }

    // Left to choose a while (past a dialling of the ways let go), all well: through a relay not clearly slower than the
    // quickest it can use.
    if (read === "200") {
      await time.pass(EXPLORE_MS + 2 * 60_000);
      const via = mesh.current(id)?.via() ?? null;
      const usable = mesh.relaysFor(id).filter((u) => relays.includes(u));
      // A way's round trip as it is, its speed as the mesh has seen it (none seen: not counted, as the mesh does).
      const truly = (u: string) => cost(2 * (net.leg(u, "device").ms + net.leg(u, "station").ms), mesh.speed(id, u));
      const best = Math.min(...usable.map(truly));
      const now = via === null ? null : relays.find((u) => new URL(u).host === new URL(via).host);
      if (now !== undefined && now !== null && truly(now) > slowest(best))
        failures.push(`left to choose, the requests go through ${now} (${truly(now).toFixed(0)} ms) though the quickest is ${best.toFixed(0)} ms: ${JSON.stringify(mesh.measured(id))}`);
    }

    // Closed: nothing left open.
    await time.settle(runner.run(mesh.close()));
    await time.settle(station.close());
    await time.pass(60_000);
    if (net.open().length > 0) failures.push(`${net.open().length} connection ends left open after closing`);
  } catch (e) {
    failures.push(`threw: ${e instanceof Error ? (e.stack ?? e.message) : String(e)}`);
  } finally {
    runner.shutdown();
  }
  if (failures.length > 0) assert.fail(`seed ${seed} (SIM_SEED=${seed} makes the same network again): ${net.describe()}\n${failures.map((f) => `  ✗ ${f}`).join("\n")}\nwhat befell it:\n${net.log.map((l) => `  ${l}`).join("\n")}`);
}

test("the mesh on networks made up at random", { timeout: 30 * 60_000 }, async () => {
  const failed: string[] = [];
  for (const seed of SEEDS) {
    try {
      await explore(seed);
    } catch (e) {
      failed.push((e as Error).message);
    }
  }
  assert.equal(failed.length, 0, `${failed.length} of ${SEEDS.length} networks failed:\n\n${failed.join("\n\n")}`);
});
