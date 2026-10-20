// Where this machine's station stands, by its cloud.json, and joining it to a workspace (「添加这台 Mac」): the
// workspaces it joined beside its own are said, for the page to offer joining more, and joining never moves it out of
// the one it is in (`enroll --stay`). The station is a script that writes down what it was asked.
// Run: node --test apps/desktop/test/station-place.test.ts
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const home = mkdtempSync(join(tmpdir(), "stillfail-station-place-"));
const release = join(home, "app");
mkdirSync(join(release, "mesh", "target", "release"), { recursive: true });
const bin = join(release, "mesh", "target", "release", "stillfail-station");
writeFileSync(bin, `#!/bin/sh\nprintf '%s\\n' "$*" > "${home}/said"\n`);
chmodSync(bin, 0o755);
const data = join(home, "data");
process.env.STILLFAIL_DATA = data;
const { LocalStation } = await import("../src/station.ts");
after(() => rmSync(home, { recursive: true, force: true }));

const cloud = (state: object) => {
  mkdirSync(join(data, "mesh"), { recursive: true });
  writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify(state));
};

test("its place says the workspaces it joined beside its own", { skip: process.platform === "win32" }, () => {
  const station = new LocalStation(release);
  rmSync(data, { recursive: true, force: true });
  assert.deepEqual(station.place, { state: "off", joined: [] });
  cloud({ workspace: "w1", station: "k" });
  assert.deepEqual(station.place, { state: "running", workspace: "w1", station: "k", joined: [] });
  cloud({ workspace: "w1", station: "k", joined: [{ workspace: "w2", name: "studio" }, { name: "none" }] });
  assert.deepEqual(station.place, { state: "running", workspace: "w1", station: "k", joined: ["w2"] });
  cloud({ workspace: "w1", station: "k", removed_at: 1_790_000_000 });
  assert.equal(station.place.state, "removed");
});

test("joining it to a workspace stays in the one it is in", { skip: process.platform === "win32" }, async () => {
  const station = new LocalStation(release);
  await station.enroll("https://app.youdid.wtf", "tok");
  assert.equal(readFileSync(join(home, "said"), "utf8").trim(), `enroll https://app.youdid.wtf tok --stay --data ${data}`);
});
