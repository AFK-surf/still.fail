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

test("with no floor every core is answered; with one, a core older than it or not saying its build is told to update", () => {
  assert.equal(coreTooOld({}, 0), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.10" }, 0), false);
  assert.equal(coreTooOld({ "Stillfail-Build": "0.1.7000" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.6999" }, 7000), true);
  assert.equal(coreTooOld({ "stillfail-lang": "zh" }, 7000), true, "a core from before it said its build");
  assert.equal(coreTooOld({ "content-type": "application/json" }, 7000), false, "no core's");
});

test("a development build (0.1.1) and an iOS app's TestFlight number (0.1.50) are held to no floor", () => {
  assert.equal(coreTooOld({ "stillfail-build": "0.1.1" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.50" }, 7000), false);
  assert.equal(coreTooOld({ "stillfail-build": "0.1.1000" }, 7000), true);
});
