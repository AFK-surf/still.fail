// What build each device a lock here names last ran (mesh/device-builds.ts), on the station's own code: kept by the
// device's id in the lock as its requests say a build (serve.ts `sawBuild`, the id admission found, `inLock`), the
// highest said and when last seen, written to stillfail.db only as the build rises or the day changes, kept across a
// restart with the day it was first kept (`since`); given in GET /lock (`serves` `builds`) for the devices of that
// lock's list, and in GET /lock/person for those of the asker's own log, nothing of any other device.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { wall } from "../src/ops/fibers.ts";
import { Store } from "../src/store/store.ts";
import { DeviceBuilds, deviceBuildsOf } from "../src/mesh/device-builds.ts";
import { inLock, lockPartRoute, lockRoute, movedFloor, movedTooOld, sawBuild } from "../src/mesh/serve.ts";
import { MOVED_FROM_BUILD } from "../src/api/moved-from.ts";
import { Log, WS2, bring, station, viewerOf, world } from "./lock-moved-world.ts";

const DAY = 86400;
let now = 1_800_000_000;
mock.method(wall, "now", () => now * 1000);

/// A store on a file, its writes of builds counted.
function kept(path: string) {
  const store = Store.open(path);
  const writes: [string, number, number][] = [];
  return {
    store,
    writes,
    kept: {
      deviceBuilds: () => store.deviceBuilds(),
      putDeviceBuild: (id: string, build: number, at: number) => {
        writes.push([id, build, at]);
        store.putDeviceBuild(id, build, at);
      },
      deviceBuildsSince: (n: number) => store.deviceBuildsSince(n),
    },
  };
}

const admitted = (v: ReturnType<typeof viewerOf>) => ({ viewer: v, exp: 4102444800, iat: 0, sid: "s" });
/// The connection of a member's device as admission lets it in (its endpoint the one its proof is for).
const letIn = (c: Parameters<typeof inLock>[0], v: ReturnType<typeof viewerOf>) => inLock(c, admitted(v) as never, v.role, v.device).viewer;
const said = (build?: string) => (build === undefined ? {} : { "stillfail-build": build });
const builds = (answer: [number, unknown]) => (answer[1] as { builds: { since: number; devices: Record<string, { build: number; at: number }> } }).builds;

test("a device the lock names: its build kept by its id as it asks, the highest, written only as it rises or the day changes, kept across a restart; GET /lock gives it with since", () => {
  now = 1_800_000_000;
  const w = world();
  const c = station(w, 0, false);
  const dir = mkdtempSync(join(tmpdir(), "device-builds-"));
  const k = kept(join(dir, "stillfail.db"));
  deviceBuildsOf(c, k.kept);
  const t0 = now;
  const bob = letIn(c, viewerOf("bob", w.bob.app, "admin", w.ws));
  assert.equal(bob.lockId, w.bob.app.base.hex, "bob's app found by its id in the lock");
  const alice = letIn(c, viewerOf("alice", w.alice.app, "owner", w.ws));
  const ask = () => builds(lockRoute(c, "GET", [], Buffer.alloc(0), alice as never));
  assert.ok((lockRoute(c, "GET", [], Buffer.alloc(0), alice as never)[1] as { serves: string[] }).serves.includes("builds"), "serves builds");
  assert.deepEqual(ask(), { since: t0, devices: {} }, "nobody seen yet");

  assert.equal(sawBuild(c, bob, said("0.1.9007")), 9007);
  assert.deepEqual(ask().devices[w.bob.app.base.hex], { build: 9007, at: t0 });
  now += 600;
  sawBuild(c, bob, said("0.1.9007"));
  assert.equal(k.writes.length, 1, "the same build the same day: not written again");
  sawBuild(c, bob, said("0.2.9008"));
  assert.deepEqual(ask().devices[w.bob.app.base.hex], { build: 9008, at: t0 + 600 }, "risen: written, its sight too");
  sawBuild(c, bob, said("0.1.9007"));
  assert.equal(k.writes.length, 2, "a lower build the same day: nothing written");
  assert.equal(ask().devices[w.bob.app.base.hex]?.build, 9008, "the highest said");
  now += DAY;
  sawBuild(c, bob, said("0.1.9008"));
  assert.equal(k.writes.length, 3, "another day: written");
  assert.deepEqual(ask().devices[w.bob.app.base.hex], { build: 9008, at: now });
  sawBuild(c, alice, said());
  assert.equal(ask().devices[w.alice.app.base.hex]?.build, -1, "one that said no build: seen, -1");
  assert.equal(ask().devices[w.carol.app.base.hex], undefined, "carol never asked: not there");

  // The station started again on the same database: the same since, the same builds.
  k.store.close();
  now += DAY;
  const again = kept(join(dir, "stillfail.db"));
  const b = new DeviceBuilds(again.kept, now);
  assert.equal(b.since, t0, "since: the first start with this");
  assert.deepEqual(b.of([w.bob.app.base.hex, w.alice.app.base.hex]).devices, { [w.bob.app.base.hex]: { build: 9008, at: t0 + 600 + DAY }, [w.alice.app.base.hex]: { build: -1, at: t0 + 600 + DAY } });
  again.store.close();
});

test("nothing of a device the lock does not name: not in GET /lock; GET /lock/person gives the asker's own log's devices alone", () => {
  now = 1_800_000_000;
  const w = world();
  const c = station(w, 0, false);
  bring(c, w.bob, false, w.ws);
  bring(c, w.alice, false, w.ws);
  const alice = letIn(c, viewerOf("alice", w.alice.app, "owner", w.ws));
  const bob = letIn(c, viewerOf("bob", w.bob.app, "admin", w.ws));
  const dave = new Log("dave");
  const daveViewer = viewerOf("dave", dave.app, "member", w.ws);
  assert.throws(() => letIn(c, daveViewer), "dave's app is not let in by the lock");
  // (his base key kept all the same, as a connection of a workspace with no lock here is kept by it)
  sawBuild(c, { ...daveViewer, lockId: dave.app.base.hex } as never, said("0.1.9100"));
  sawBuild(c, alice, said("0.1.9100"));
  sawBuild(c, bob, said("0.1.9001"));
  const ids = Object.keys(builds(lockRoute(c, "GET", [], Buffer.alloc(0), bob as never)).devices).sort();
  assert.deepEqual(ids, [w.alice.app.base.hex, w.bob.app.base.hex].sort(), "the lock's devices alone, dave's not");
  const person = lockPartRoute(c, "person", "GET", Buffer.alloc(0), bob as never);
  assert.ok((person[1] as { serves: string[] }).serves.includes("builds") && (person[1] as { serves: string[] }).serves.includes("logs"), "GET /lock/person says it serves logs and builds");
  assert.deepEqual(builds(person).devices, { [w.bob.app.base.hex]: { build: 9001, at: now } }, "bob's own log's device alone");
});

// A core too old for a workspace whose chain moved (api/moved-from.ts): told to update as one under OLDEST_CORE is (426,
// `update`), for that workspace's requests alone; one that says no build is answered as `coreTooOld` answers it.
test("a counted build under MOVED_FROM_BUILD at a workspace whose chain moved: too old there; MOVED_FROM_BUILD, none said, one under COUNTED_FROM, the chain not moved, another workspace's: not", () => {
  const w = world();
  const moved = station(w, 0, true), not = station(w, 1, false);
  const v = viewerOf("bob", w.bob.app, "admin", w.ws) as never;
  assert.equal(movedTooOld(moved, v, MOVED_FROM_BUILD - 1), true, "one under it where it moved");
  assert.equal(movedTooOld(moved, v, MOVED_FROM_BUILD), false, "it");
  assert.equal(movedTooOld(moved, v, null), false, "none said: as coreTooOld answers it");
  assert.equal(movedTooOld(moved, v, 0), false, "an unnumbered build (a development build's, an iOS app's)");
  assert.equal(movedTooOld(not, v, MOVED_FROM_BUILD - 1), false, "its chain not moved");
  assert.equal(movedTooOld(moved, viewerOf("bob", w.bob.app, "admin", WS2) as never, MOVED_FROM_BUILD - 1), false, "another workspace of the station's");
  // the floor the MoonBit program is told of a connection in each (mesh/served.ts): the same rule
  assert.deepEqual([movedFloor(moved, w.ws), movedFloor(not, w.ws), movedFloor(moved, WS2)], [MOVED_FROM_BUILD, null, null], "the floor told: moved, not moved, another workspace");
});
