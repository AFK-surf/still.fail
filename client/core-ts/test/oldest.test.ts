// The oldest station a core talks to (station/oldest.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { stationTooOld } from "../src/station/oldest.ts";

test("with no floor every station is talked to; with one, a station older than it or not saying its build fails as too old", () => {
  assert.equal(stationTooOld([]), null);
  assert.equal(stationTooOld([["stillfail-build", "0.1.7000"]], 7000), null);
  // 0.<m>.<n>: by n alone, whatever m says.
  assert.equal(stationTooOld([["stillfail-build", "0.34.7000"]], 7000), null);
  assert.equal(stationTooOld([["stillfail-build", "0.99.6999"]], 7000)?.code, "station_too_old");
  const old = stationTooOld([["stillfail-build", "0.1.6999"]], 7000);
  assert.deepEqual([old?.code, old?.status], ["station_too_old", 426]);
  assert.equal(stationTooOld([["content-type", "application/json"]], 7000)?.code, "station_too_old");
});
