// The Rust core's preview_load.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Loads } from "../src/preview-load.ts";

test("counts_failures_and_ignores_old_navigation_completions", () => {
  const loads = new Loads();
  const document: [string, string][] = [["Accept", "text/html"]];
  const first = loads.start("ws/a", 3000, "GET", "/", document, 0);
  const script = loads.start("ws/a", 3000, "GET", "/app.js", [], 1);
  loads.head(first, 200);
  loads.end(first, 2, null);
  assert.equal(loads.value(first[0]).percent, 50);
  loads.head(script, 404);
  loads.end(script, 3, null);
  loads.end(script, 4, null);
  assert.equal(loads.value(first[0]).failed, 1);
  assert.equal(loads.value(first[0]).percent, 100);
  const next = loads.start("ws/a", 3000, "GET", "/next", document, 5);
  loads.end(script, 6, "cancelled");
  assert.equal(loads.value(next[0]).total, 1);
  assert.equal(loads.value(next[0]).finished, 0);
  assert.equal(loads.value({ topic: "previewLoad", station: "other/a", port: 3000 }).total, 0);
});

test("retains_totals_when_old_details_are_trimmed", () => {
  const loads = new Loads();
  for (let n = 0; n < 250; n++) {
    const key = loads.start("ws/a", 3000, "GET", "/data", [], n);
    loads.end(key, n + 1, null);
  }
  const value = loads.value({ topic: "previewLoad", station: "ws/a", port: 3000 });
  assert.equal(value.total, 250);
  assert.equal(value.percent, 100);
  assert.equal(value.resources.length, 200);
});
