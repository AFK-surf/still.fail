// The station's place with still.fail cloud (src/cloud/state.ts) as kept in memory and in <data>/mesh/cloud.json.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Cloud, readState, writeState } from "../src/cloud/state.ts";
import { member } from "../src/mesh/peer.ts";
import { setStationLang } from "../src/ops/i18n.ts";

test("an unreadable cloud state names the file and suggests encryption without exposing its contents", () => {
  setStationLang("en");
  const data = mkdtempSync(join(tmpdir(), "cloud-invalid-"));
  mkdirSync(join(data, "mesh"));
  const file = join(data, "mesh", "cloud.json");
  writeFileSync(file, "%TSD-Header-###%secret");
  assert.throws(() => readState(data), (error: Error) =>
    error.message.includes(file) && /encrypt/i.test(error.message) && !error.message.includes("secret"));
});

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

test("a workspace lookup checks only that workspace and has the same members as the full roster", () => {
  const joined = (workspace: string, id: string, locked?: true) => ({ workspace, workspace_name: workspace, name: "here", peers: [{ id }], revocations: [], locked });
  const cloud: any = Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "home", workspace_name: "Home", name: "here", station: "here", peers: [{ id: "home-peer" }], revocations: [],
      joined: [joined("home", "ignored"), joined("waiting", "waiting-peer", true), joined("chosen", "chosen-peer"), joined("chosen", "other-peer"), joined("other", "other-peer")] },
    lock: null, peersCurrent: true,
  });
  const checked: string[] = [];
  cloud.pendingLock = (ws: string) => { checked.push(ws); return null; };
  const full = cloud.memberships();
  for (const ws of ["home", "waiting", "chosen", "other", "missing"]) {
    assert.deepEqual(cloud.membership(ws), full.find((m: any) => m.workspace === ws) ?? null);
  }

  checked.length = 0;
  assert.equal(member(cloud, "home-peer", "home"), "home");
  assert.deepEqual(checked, [], "a home peer does not inspect joined workspaces");
  assert.equal(member(cloud, "home-peer", null), "home");
  assert.deepEqual(checked, [], "finding a home peer does not inspect joined workspaces");
  assert.equal(member(cloud, "chosen-peer", "chosen"), "chosen");
  assert.deepEqual(checked, ["chosen"], "a joined peer does not inspect other workspaces");
  assert.throws(() => member(cloud, "other-peer", "chosen"), /not another station/);
  assert.throws(() => member(cloud, "waiting-peer", "waiting"), /outside this workspace/);
  cloud.state.removed_at = 1;
  assert.equal(cloud.membership("home"), null);
  assert.equal(cloud.membership("chosen"), null);
  assert.deepEqual(cloud.memberships(), []);
});
