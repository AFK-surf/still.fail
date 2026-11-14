// The oldest core a station answers (api/oldest.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildOf, coreTooOld } from "../src/api/oldest.ts";

test("a core's build is read as its 0.1.<n>, or <n>", () => {
  assert.equal(buildOf("0.1.6936"), 6936);
  assert.equal(buildOf("0.34.6936"), 6936);
  assert.equal(buildOf(" 6936 "), 6936);
  assert.equal(buildOf("dev"), null);
  assert.equal(buildOf(undefined), null);
});

test("with no floor every core is answered; with one, a core saying a build older than it is told to update", () => {
  assert.equal(coreTooOld({}, 0), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.10" }, 0), false);
  assert.equal(coreTooOld({ "Stillfail-Build": "0.1.7000" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.6999" }, 7000), true);
  assert.equal(coreTooOld({ "content-type": "application/json" }, 7000), false, "no core's");
});

// 2026-11-10: the stable web (built 2026-11-08) on stations with the floor: every request of its refused as too old,
// its four stations up and none reached, its chats as they were. The app on the web tells its core no build, so its
// core said none with its requests (`0.1.0` only since the floor was raised).
test("a core that says a language and no build (the app on the web, of a release before it said 0.1.0) is answered, not told to update", () => {
  assert.equal(coreTooOld({ "stillfail-lang": "zh" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-lang": "zh", "stillfail-runtimes": "claude,codex", traceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01" }), false, "at the station's own floor");
  assert.equal(coreTooOld({ "stillfail-lang": "zh", "stillfail-build": "dev" }, 7000), false, "nor one whose build is no number");
});

test("a development build (0.1.1) and an iOS app's TestFlight number (0.1.50) are held to no floor", () => {
  assert.equal(coreTooOld({ "stillfail-build": "0.1.1" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.50" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.1000" }, 7000), true);
});
