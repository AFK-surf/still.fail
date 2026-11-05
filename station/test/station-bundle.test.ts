import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

test("a station release includes every worker built, including workers in new directories", { skip: process.platform === "win32" }, () => {
  const root = mkdtempSync(join(tmpdir(), "station-bundle-"));
  const file = (path: string, content = "fixture") => {
    const absolute = join(root, path);
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, content);
  };
  try {
    mkdirSync(join(root, "scripts"), { recursive: true });
    cpSync(fileURLToPath(new URL("../../scripts/station-bundle.sh", import.meta.url)), join(root, "scripts/station-bundle.sh"));
    for (const path of ["bin/stillfail", "bin/stillfail.cmd", "bin/stillfail.ps1", ".node-version", "natives/stillfail-station",
      "natives/stillfail-station-w.exe", "natives/mesh.node", "natives/stillfail-runner", "natives/stillfail-screen.exe",
      "natives/agent-desktop.exe", "natives/still.fail Helper.app/Contents/MacOS/helper"]) file(path);
    // A release may run after a different build in the same checkout; its files must not leak into this one.
    file("station/dist/stale/old-worker.js");
    file("mock-bin/node", `#!/bin/sh
set -eu
case "$1" in
  */posthog-key.ts) mkdir -p "$BUNDLE_TEST_ROOT/dist/admin"; printf '{}' > "$BUNDLE_TEST_ROOT/dist/admin/posthog.json" ;;
  */native.ts) case "$3" in
    launcher) name=stillfail-station ;; mesh) name=mesh.node ;; runner) name=stillfail-runner ;;
    helper) name='still.fail Helper.app' ;; screen) name=stillfail-screen.exe ;; agent-desktop) name=agent-desktop.exe ;;
    *) exit 1 ;;
  esac; printf '%s/natives/%s\\n' "$BUNDLE_TEST_ROOT" "$name" ;;
  */installers.ts) : ;;
  *) exit 1 ;;
esac
`);
    file("mock-bin/pnpm", `#!/bin/sh
set -eu
for name in main.js read/worker.js read/said-worker.js search/worker.js vault/use-index-worker.js vault/signin-save-worker.js \\
  usage/minute-worker.js sessions/workspace-activity-worker.js sessions/post-block-worker.js outflow/chat-index-worker.js future/another-worker.js \\
  skills/example.md dsh-bridge.mjs cursor-bridge.mjs sandbox-bridge.mjs scrcpy-server linux-portal.py linux-x11.py; do
  mkdir -p "dist/$(dirname "$name")"
  printf '%s' "$name" > "dist/$name"
done
`);
    file("mock-bin/git", `#!/bin/sh\nprintf '123\\n'\n`);
    for (const executable of ["node", "pnpm", "git"]) execFileSync("chmod", ["+x", join(root, "mock-bin", executable)]);
    const env: NodeJS.ProcessEnv = { ...process.env, BUNDLE_TEST_ROOT: root, PATH: `${join(root, "mock-bin")}:${process.env.PATH ?? ""}` };
    delete env.STILLFAIL_SIGN_STATION;
    for (const platform of ["darwin-arm64", "linux-x64", "linux-arm64", "win32-x64"]) {
      execFileSync("/bin/sh", [join(root, "scripts/station-bundle.sh"), join(root, "out"), platform], { env });
      const station = join(root, "out/stillfail/station");
      for (const worker of ["read/worker.js", "read/said-worker.js", "search/worker.js", "vault/use-index-worker.js", "vault/signin-save-worker.js",
        "usage/minute-worker.js", "sessions/workspace-activity-worker.js", "sessions/post-block-worker.js", "outflow/chat-index-worker.js", "future/another-worker.js"]) {
        assert.equal(readFileSync(join(station, worker), "utf8"), worker, `${platform}: ${worker}`);
      }
      assert.equal(existsSync(join(station, "stale/old-worker.js")), false, `${platform}: nothing left from an earlier build`);
      assert.equal(existsSync(join(station, "linux-portal.py")), platform.startsWith("linux-"));
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("files a module finds beside itself are named as they lie beside main.js in a release, where every module is bundled", () => {
  // The release copies them flat beside main.js (package.json build), so a path into another directory of src only
  // works from the source (2026-11-04: the chat's own phone screen looked for ../screens/scrcpy-server and found none).
  const src = fileURLToPath(new URL("../src/", import.meta.url));
  const wrong: string[] = [];
  for (const name of readdirSync(src, { recursive: true, encoding: "utf8" })) {
    if (!name.endsWith(".ts")) continue;
    readFileSync(join(src, name), "utf8").split("\n").forEach((line, i) => {
      // Built from the source only: mesh's library from a local cargo build, and skills found by where the module runs.
      if (line.includes("native/mesh/target/") || line.includes('import.meta.url.endsWith(".ts")')) return;
      for (const m of line.matchAll(/new URL\("([^"]*)", import\.meta\.url\)/g)) {
        if (!/^\.\/[^/]+\/?$/.test(m[1])) wrong.push(`${name}:${i + 1} ${m[1]}`);
      }
    });
  }
  assert.deepEqual(wrong, []);
});
