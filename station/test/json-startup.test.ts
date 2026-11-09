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

test("channel and update explain unreadable files without exposing them or changing the config", () => {
  const data = mkdtempSync(join(tmpdir(), "station-json-commands-"));
  mkdirSync(join(data, "mesh"));
  const config = join(data, "config.json");
  const cloud = join(data, "mesh", "cloud.json");
  const hidden = "%TSD-Header-###%private-content";
  const env = { ...process.env, STILLFAIL_CONFIG: config };
  const run = (args: string[]) => spawnSync(process.execPath, [main, ...args, "--app", join(data, "app"), "--data", data], { env, encoding: "utf8" });
  const refuses = (args: string[], path: string) => {
    const result = run(args);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /加密|encrypt/i);
    assert.ok(result.stderr.includes(path));
    assert.ok(result.stderr.includes(process.execPath));
    assert.doesNotMatch(result.stderr, /SyntaxError|private-content/);
  };
  writeFileSync(config, hidden);
  writeFileSync(cloud, JSON.stringify({ origin: "https://example.test" }));
  refuses(["channel"], config);
  refuses(["channel", "beta"], config);
  refuses(["update"], config);
  assert.equal(readFileSync(config, "utf8"), hidden);
  writeFileSync(config, JSON.stringify({ language: "en" }));
  writeFileSync(cloud, hidden);
  refuses(["update"], cloud);
});
