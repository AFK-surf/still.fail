// The station's place with still.fail cloud (src/cloud/state.ts) as kept in memory and in <data>/mesh/cloud.json.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Cloud, writeState } from "../src/cloud/state.ts";

test("cloud.json's watch failing (macOS turning it down: EMFILE) ends the watch, not the station", () => {
  const data = mkdtempSync(join(tmpdir(), "cloud-state-"));
  writeState(data, {
    origin: "https://app.still.fail", station: "a".repeat(64), workspace: "w", workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: [], revocations: [],
  });
  const cloud = new Cloud(data);
  // As Node tells it when FSEventStreamStart fails: an 'error' event on the watcher.
  const watcher = (cloud as any).watcher;
  assert.ok(watcher, "cloud.json is watched");
  assert.doesNotThrow(() => watcher.emit("error", Object.assign(new Error("EMFILE: too many open files, watch"), { code: "EMFILE" })));
  assert.equal(cloud.state?.name, "s0");
  cloud.close();
});
