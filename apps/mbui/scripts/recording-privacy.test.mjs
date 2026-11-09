import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { containsLocalInformation, recordingPathAliases, recordingRealPath, stationWorkAlias, validateRecordingContext } from "./recording-privacy.mjs";

const config = { home: "/Users/example", work: "/Users/example/private-run", hostname: "example-machine" };
const line = (value) => JSON.stringify(value) + "\n";

test("a recording rejects raw and partially scrubbed local paths", () => {
  for (const note of [
    "/Users/example/file", "/Users/example/private-run/agent", "/test-home/private-run/agent", "example-machine",
  ]) {
    assert.equal(containsLocalInformation(line({ in: { note } }), config), true);
  }
  assert.equal(containsLocalInformation(line({ in: { note: "/test-e2e/agent" } }), config), false);
});

test("a recording rejects local information inside captured bytes", () => {
  const b = Buffer.from('{"path":"/test-home/private-run/agent"}').toString("hex");
  assert.equal(containsLocalInformation(line({ in: { b } }), config), true);
  assert.equal(containsLocalInformation(line({ in: { b: Buffer.from("ordinary bytes").toString("hex") } }), config), false);
});

test("a reported local station is rejected but an absent or null one is allowed", () => {
  assert.equal(containsLocalInformation(line({ host: { localStation: { id: "local-id" } } }), config), true);
  assert.equal(containsLocalInformation(line({ host: { localStation: null } }), config), false);
  assert.equal(containsLocalInformation(line({ host: { other: "value" } }), config), false);
});

test("recording paths must be absolute, specific and not aliases of the filesystem root", () => {
  const dir = mkdtempSync(join(tmpdir(), "recording-root-"));
  try {
    const rootLink = join(dir, "root");
    symlinkSync("/", rootLink, "dir");
    for (const [work, station] of [["", "/tmp/station"], ["/", "/tmp/station"], [".", "/tmp/station"], ["/tmp/work", "/"], ["/tmp/work", "."], ["/tmp/work", rootLink]]) {
      assert.throws(() => validateRecordingContext(work, station));
    }
    assert.doesNotThrow(() => validateRecordingContext(join(dir, "work"), join(dir, "station")));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a private checkout parent is rejected even in a sibling directory", () => {
  const options = { ...config, workspace: "/Users/example/private-session" };
  assert.equal(containsLocalInformation(line({ note: "/test-home/private-session/other/file" }), options), true);
  assert.equal(containsLocalInformation(line({ note: "/test-home/other/file" }), { ...options, workspace: options.home }), false);
});

test("private identifiers are rejected in text and bytes without being committed", () => {
  const options = { ...config, privateTerms: ["", "Private-Station", "  "] };
  assert.equal(containsLocalInformation(line({ note: "private-station is online" }), options), true);
  assert.equal(containsLocalInformation(line({ b: Buffer.from("PRIVATE-STATION").toString("hex") }), options), true);
  assert.equal(containsLocalInformation(line({ note: "a fictional station" }), options), false);
});

test("a station path and a symlink to the work directory are rejected, including object keys and bytes", () => {
  const dir = mkdtempSync(join(tmpdir(), "recording-paths-"));
  try {
    const work = join(dir, "work");
    const alias = join(dir, "short");
    mkdirSync(work);
    symlinkSync(work, alias, "dir");
    const station = join(alias, "s");
    const options = { ...config, work, station };
    assert.equal(stationWorkAlias(work, station), alias);
    for (const path of [join(station, "home"), join(alias, "other"), join(work, "s", "home")]) {
      assert.equal(containsLocalInformation(line({ in: { path } }), options), true);
      assert.equal(containsLocalInformation(line({ in: { [path]: "value" } }), options), true);
      assert.equal(containsLocalInformation(line({ b: Buffer.from(path).toString("hex") }), options), true);
    }
    assert.equal(containsLocalInformation(line({ in: { "/test-e2e/s/home": "value" } }), options), false);
    const independent = { ...options, station: "/tmp/mbui-e2e-123" };
    assert.equal(containsLocalInformation(line({ nested: { "/tmp/mbui-e2e-123/home": 1 } }), independent), true);
    assert.equal(containsLocalInformation(line({ nested: { ordinary: 1 } }), independent), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("work and station parent symlinks resolve to the same paths even before station creation", () => {
  const dir = mkdtempSync(join(tmpdir(), "recording-links-"));
  try {
    const physical = join(dir, "actual");
    const work = join(dir, "work-link");
    const parent = join(dir, "station-parent");
    mkdirSync(join(physical, "sub"), { recursive: true });
    const real = realpathSync(physical);
    symlinkSync(physical, work, "dir");
    symlinkSync(join(physical, "sub"), parent, "dir");
    const station = join(parent, "s");
    assert.equal(recordingRealPath(work), real);
    assert.equal(recordingRealPath(station), join(real, "sub", "s"));
    assert.ok(recordingPathAliases(work).includes(physical));
    assert.ok(recordingPathAliases(work).includes(real));
    assert.ok(recordingPathAliases(station).includes(join(physical, "sub", "s")));
    assert.ok(recordingPathAliases(station).includes(join(real, "sub", "s")));
    mkdirSync(join(dir, "unused"));
    const withDots = `${dir}/unused/../actual/sub/s`;
    assert.ok(recordingPathAliases(withDots).includes(withDots));
    assert.equal(containsLocalInformation(line({ in: { path: `${withDots}/home` } }), { ...config, station: withDots }), true);
    const ambiguous = `${parent}/../sub/s`;
    assert.throws(() => recordingPathAliases(ambiguous), /ambiguous path/);
    assert.equal(stationWorkAlias(work, station), "");
    const options = { ...config, work, station };
    for (const path of [join(station, "home"), join(work, "sub", "s", "home"), join(physical, "sub", "s", "home")]) {
      assert.equal(containsLocalInformation(line({ nested: { [path]: "value" } }), options), true);
      assert.equal(containsLocalInformation(line({ in: { path } }), options), true);
    }
    mkdirSync(station);
    assert.equal(recordingRealPath(station), join(real, "sub", "s"));
    assert.equal(containsLocalInformation(line({ nested: { "/test-e2e/sub/s/home": "value" } }), options), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the local run and recorder share default, recorded and explicit paths", () => {
  const helper = fileURLToPath(new URL("./e2e-paths.sh", import.meta.url));
  const app = fileURLToPath(new URL("..", import.meta.url));
  const run = (work, station, recorded = "") => spawnSync("sh", ["-c", '. "$1"; e2e_paths "$2" "$3"; printf "%s\\n%s\\n" "$E2E_WORK" "$E2E_STATION"', "sh", helper, app, recorded], {
    encoding: "utf8", env: { ...process.env, E2E_WORK: work, E2E_STATION: station },
  });
  const defaults = run("", "");
  assert.equal(defaults.status, 0);
  assert.deepEqual(defaults.stdout.trimEnd().split("\n"), [join(app, "..", "e2e-local"), `/tmp/mbui-e2e-${process.getuid()}`]);
  assert.equal(run("", "", "/tmp/recorded").stdout.trimEnd().split("\n")[1], "/tmp/recorded");
  assert.deepEqual(run("/tmp/our-work", "/tmp/short/s", "/tmp/recorded").stdout.trimEnd().split("\n"), ["/tmp/our-work", "/tmp/short/s"]);
});

test("the recording check reads a private list and fails closed if it is unavailable", () => {
  const dir = mkdtempSync(join(tmpdir(), "recording-privacy-"));
  try {
    const terms = join(dir, "terms");
    const trace = join(dir, "trace");
    writeFileSync(terms, "Private-Station\n");
    writeFileSync(trace, line({ note: "private-station" }));
    const run = () => spawnSync(process.execPath, [fileURLToPath(new URL("./recording-privacy.mjs", import.meta.url)), trace], {
      env: { ...process.env, E2E_PRIVATE_TERMS_FILE: terms },
    });
    assert.equal(run().status, 1);
    writeFileSync(trace, line({ note: "fictional station" }));
    assert.equal(run().status, 0);
    rmSync(terms);
    assert.equal(run().status, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
