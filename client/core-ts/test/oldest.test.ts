// The oldest station a core talks to (station/oldest.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { stationTooOld } from "../src/station/oldest.ts";

test("with no floor every station is talked to; with one, a station older than it or not saying its build fails as too old", () => {
  assert.equal(stationTooOld([], "/sessions", 0), null);
  assert.equal(stationTooOld([["stillfail-build", "0.1.7000"]], "/sessions", 7000), null);
  // 0.<m>.<n>: by n alone, whatever m says.
  assert.equal(stationTooOld([["stillfail-build", "0.34.7000"]], "/sessions", 7000), null);
  assert.equal(stationTooOld([["stillfail-build", "0.99.6999"]], "/sessions", 7000)?.code, "station_too_old");
  const old = stationTooOld([["stillfail-build", "0.1.6999"]], "/events?running=1", 7000);
  assert.deepEqual([old?.code, old?.status], ["station_too_old", 426]);
  assert.equal(stationTooOld([["stillfail-idempotent", "1"]], "/sessions", 7000)?.code, "station_too_old", "a station from before it said its build");
  assert.equal(stationTooOld([["content-type", "application/json"]], "/sessions", 7000), null, "no station's");
});

test("a station too old is still asked what its updates are and for one, so it can be updated from here", () => {
  for (const path of ["/overview", "/updates", "/updates/all", "/updates/check", "/overview?lang=zh"]) {
    assert.equal(stationTooOld([["stillfail-build", "0.1.6004"]], path, 7000), null, path);
  }
  assert.equal(stationTooOld([["stillfail-build", "0.1.6004"]], "/overviews", 7000)?.code, "station_too_old");
});

test("a station run from the sources (0.1.0) is held to no floor", () => {
  assert.equal(stationTooOld([["stillfail-build", "0.1.0"]], "/sessions", 7000), null);
});
