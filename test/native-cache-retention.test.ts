import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

test("the native cache removes cold versions while retaining recently used and locked versions", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "native-cache-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin"), cache = join(tmp, "cache"), part = join(cache, "shell-apple");
  mkdirSync(bin, { recursive: true });
  mkdirSync(part, { recursive: true });
  const now = Date.parse("2026-01-02T12:00:00Z"), clock = join(tmp, "clock.mjs");
  // Keep timestamps written by native.ts on the same fixed clock as its eviction decision.
  writeFileSync(clock, `import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
Date.now = () => ${now};
const write = fs.writeFileSync;
fs.writeFileSync = (path, ...args) => {
  const result = write(path, ...args);
  if (typeof path === "string") fs.utimesSync(path, ${now / 1000}, ${now / 1000});
  return result;
};
syncBuiltinESMExports();\n`);
  // A fixed, empty git input makes the artifact's real key independent of this test's checkout.
  writeFileSync(join(bin, "git"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "git"), 0o755);
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, STILLFAIL_NATIVE_CACHE: cache,
    STILLFAIL_NATIVE: "offline", STILLFAIL_NATIVE_CACHE_MAX_BYTES: "1" };
  const run = (...args: string[]) => spawnSync(process.execPath, ["--import", clock, join(root, "scripts/native.ts"), ...args], {
    cwd: root, encoding: "utf8", env,
  });
  const key = run("key", "shell-apple", "darwin-arm64");
  assert.equal(key.status, 0, key.stderr);
  const current = join(part, `darwin-arm64-${key.stdout.trim()}`);
  const old = join(part, `darwin-arm64-${"1".repeat(24)}`);
  const locked = join(part, `darwin-arm64-${"2".repeat(24)}`);
  const recent = join(part, `darwin-arm64-${"3".repeat(24)}`);
  const legacy = join(part, `darwin-arm64-${"4".repeat(24)}`);
  const unused = join(part, `darwin-arm64-${"5".repeat(24)}`);
  const protectedVersion = join(part, `darwin-arm64-${"6".repeat(24)}`);
  const longAgo = new Date("2020-01-01T00:00:00Z");
  const entry = (dir: string, used: "old" | "recent" | "legacy") => {
    mkdirSync(dir);
    writeFileSync(join(dir, "manifest.json"), "{}");
    writeFileSync(join(dir, "libstillfail_shell.a"), "archive");
    writeFileSync(join(dir, "libstillfail_shell.libs"), "libs");
    if (used !== "legacy") {
      const marker = join(cache, ".access", "shell-apple", basename(dir));
      mkdirSync(join(cache, ".access", "shell-apple"), { recursive: true });
      writeFileSync(marker, "");
      const lastUse = used === "old" ? longAgo : new Date(now);
      utimesSync(marker, lastUse, lastUse);
    }
    if (used === "legacy") utimesSync(dir, longAgo, longAgo);
  };
  for (const dir of [current, old, locked]) entry(dir, "old");
  entry(recent, "recent");
  entry(legacy, "legacy");
  entry(unused, "recent");
  entry(protectedVersion, "recent");
  const marker = (dir: string) => join(cache, ".access", "shell-apple", basename(dir));
  const sevenHoursAgo = new Date(now - 7 * 60 * 60 * 1000);
  const fiveHoursAgo = new Date(now - 5 * 60 * 60 * 1000);
  utimesSync(marker(unused), sevenHoursAgo, sevenHoursAgo);
  utimesSync(marker(protectedVersion), fiveHoursAgo, fiveHoursAgo);
  mkdirSync(`${locked}.lock`);
  writeFileSync(join(`${locked}.lock`, "pid"), String(process.pid));

  const result = run("path", "shell-apple", "darwin-arm64");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), current);
  assert.equal(existsSync(old), false, "an unused old version should be removed");
  assert.equal(existsSync(unused), false, "versions unused for over six hours should be removed when over budget");
  assert.equal(existsSync(protectedVersion), true, "versions used within six hours must remain usable");
  assert.equal(existsSync(current), true, "the requested version must remain usable");
  assert.equal(existsSync(recent), true, "a recently requested version may still be in use");
  assert.equal(existsSync(locked), true, "another process is working on this version");
  assert.equal(existsSync(legacy), true, "versions from before use tracking must first be observed");
});
