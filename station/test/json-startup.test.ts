// A new process sees an unreadable file: its CLI and an update's handover both say why, without file contents.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const main = fileURLToPath(new URL("../src/main.ts", import.meta.url));

test("status and a handover report an unreadable cloud file without exposing it", () => {
  const data = mkdtempSync(join(tmpdir(), "station-json-start-"));
  mkdirSync(join(data, "mesh"));
  mkdirSync(join(data, "run"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ language: "en" }));
  const path = join(data, "mesh", "cloud.json");
  writeFileSync(path, "%TSD-Header-###%private-content");
  const env = { ...process.env, STILLFAIL_CONFIG: join(data, "config.json") };
  const run = (args: string[]) => spawnSync(process.execPath, [main, ...args, "--data", data], { env, encoding: "utf8" });
  const status = run(["status"]);
  assert.equal(status.status, 1, status.stderr);
  assert.match(status.stderr, /encrypt/i);
  assert.ok(status.stderr.includes(path));
  assert.ok(status.stderr.includes(process.execPath));
  assert.doesNotMatch(status.stderr, /SyntaxError|private-content/);
  const start = run(["run", "--app", join(data, "app"), "--launcher-pipe", "unused"]);
  assert.equal(start.status, 1, start.stderr);
  assert.doesNotMatch(start.stderr, /SyntaxError|private-content/);
  assert.equal(readFileSync(join(data, "run", "handoff-error"), "utf8").trim(), start.stderr.trim());
});
