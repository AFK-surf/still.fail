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
  // A fixed, empty git input makes the artifact's real key independent of this test's checkout.
  writeFileSync(join(bin, "git"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "git"), 0o755);
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, STILLFAIL_NATIVE_CACHE: cache,
    STILLFAIL_NATIVE: "offline", STILLFAIL_NATIVE_CACHE_MAX_BYTES: "1" };
  const run = (...args: string[]) => spawnSync(process.execPath, [join(root, "scripts/native.ts"), ...args], {
    cwd: root, encoding: "utf8", env,
  });
  const key = run("key", "shell-apple", "darwin-arm64");
  assert.equal(key.status, 0, key.stderr);
  const current = join(part, `darwin-arm64-${key.stdout.trim()}`);
  const old = join(part, `darwin-arm64-${"1".repeat(24)}`);
  const locked = join(part, `darwin-arm64-${"2".repeat(24)}`);
  const recent = join(part, `darwin-arm64-${"3".repeat(24)}`);
  const legacy = join(part, `darwin-arm64-${"4".repeat(24)}`);
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
      if (used === "old") utimesSync(marker, longAgo, longAgo);
    }
    if (used === "legacy") utimesSync(dir, longAgo, longAgo);
  };
  for (const dir of [current, old, locked]) entry(dir, "old");
  entry(recent, "recent");
  entry(legacy, "legacy");
  mkdirSync(`${locked}.lock`);
  writeFileSync(join(`${locked}.lock`, "pid"), String(process.pid));

  const result = run("path", "shell-apple", "darwin-arm64");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), current);
  assert.equal(existsSync(old), false, "an unused old version should be removed");
  assert.equal(existsSync(current), true, "the requested version must remain usable");
  assert.equal(existsSync(recent), true, "a recently requested version may still be in use");
  assert.equal(existsSync(locked), true, "another process is working on this version");
  assert.equal(existsSync(legacy), true, "versions from before use tracking must first be observed");
});
