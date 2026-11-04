import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

// Native releases prepare their own core dependencies. Building a staged app must work without the website's
// packages or an uploader; signing failure must never hand a feed to the publishing job.
test("the staged Mac release builds without website packages and hands over only a signed complete release", (t) => {
  const source = fileURLToPath(new URL("..", import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), "release-app-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const name of [".github", "scripts", "cloud", "bin", "tmp"]) mkdirSync(join(dir, name));
  copyFileSync(join(source, ".github/release-desktop.sh"), join(dir, ".github/release-desktop.sh"));
  const command = (name: string, body: string) => {
    writeFileSync(join(dir, "bin", name), `#!/bin/sh\nset -eu\n${body}\n`);
    chmodSync(join(dir, "bin", name), 0o755);
  };
  command("pnpm", 'echo "website or uploader packages requested" >&2; exit 42');
  command("git", 'printf "7232\\n"');
  command("python3", `
[ "$1" = .github/mac_signing.py ] && [ "$2" = run ] && [ "$3" = -- ]
[ -z "\${UNSIGNED:-}" ]
[ "$(cat "$STILLFAIL_POSTHOG")" = '{"project":"test"}' ]
if [ "\${FAIL_SIGN:-}" = 1 ]; then exit 7; fi
shift 3
export MAC_SIGN_IDENTITY='Developer ID Application: test'
exec "$@"`);
  writeFileSync(join(dir, "scripts/release.sh"), `#!/bin/sh
set -eu
[ "$MAC_SIGN_IDENTITY" = 'Developer ID Application: test' ]
suffix= channel= product=stillfail
if [ "$1" = --product ]; then product=$2; shift 2; fi
if [ "$1" = --beta ]; then suffix=-beta; channel=beta/; shift; fi
[ "$1" = desktop ]
mkdir -p "$RELEASE_DIR/desktop" "$RELEASE_DIR/mac/$channel"
printf signed > "$RELEASE_DIR/desktop/$product$suffix-0.1.7232-arm64-mac.zip"
printf feed > "$RELEASE_DIR/mac/\${channel}latest.json"
[ "\${INCOMPLETE:-}" = 1 ] || [ "$product" != stillfail ] || printf legacy > "$RELEASE_DIR/desktop/stillfail$suffix-mac.yml"
`);
  const run = (out: string, args: string[] = [], extra: Record<string, string> = {}) => spawnSync("sh", [".github/release-desktop.sh", ...args, "--out", out], {
    cwd: dir, encoding: "utf8", env: { ...process.env, PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      RUNNER_TEMP: join(dir, "tmp"), POSTHOG_JSON: '{"project":"test"}', UNSIGNED: "1", CLOUDFLARE_API_TOKEN: "", ...extra },
  });
  for (const stable of [false, true]) {
    const out = join(dir, stable ? "stable" : "beta");
    const result = run(out, stable ? ["--stable"] : []);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(join(out, `desktop/stillfail${stable ? "" : "-beta"}-0.1.7232-arm64-mac.zip`), "utf8"), "signed");
    assert.equal(readFileSync(join(out, `mac/${stable ? "" : "beta/"}latest.json`), "utf8"), "feed");
    assert.deepEqual(readdirSync(join(dir, "tmp")), [], "the signing configuration is removed after staging");
  }
  // monoid's: its own names, no Electron feed (it never had an Electron app)
  const monoid = join(dir, "monoid");
  const made = run(monoid, ["--product", "monoid"]);
  assert.equal(made.status, 0, made.stderr);
  assert.equal(readFileSync(join(monoid, "desktop/monoid-beta-0.1.7232-arm64-mac.zip"), "utf8"), "signed");
  assert.equal(existsSync(join(monoid, "desktop/stillfail-beta-mac.yml")), false);
  const failed = join(dir, "failed");
  let result = run(failed, [], { FAIL_SIGN: "1" });
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(failed), false, "a failed signing never hands out artifacts");
  assert.deepEqual(readdirSync(join(dir, "tmp")), []);
  result = run(failed, [], { INCOMPLETE: "1" });
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(failed), false, "an incomplete release never hands out either feed");
  assert.deepEqual(readdirSync(join(dir, "tmp")), []);
});

test("a staged Android app needs its signing key and no website or uploader installation", (t) => {
  const source = fileURLToPath(new URL("..", import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), "release-android-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const name of [".github", "scripts", "cloud", "bin", "tmp"]) mkdirSync(join(dir, name));
  copyFileSync(join(source, ".github/release.sh"), join(dir, ".github/release.sh"));
  writeFileSync(join(dir, "bin/pnpm"), "#!/bin/sh\nexit 42\n");
  chmodSync(join(dir, "bin/pnpm"), 0o755);
  writeFileSync(join(dir, "scripts/release.sh"), `#!/bin/sh
set -eu
[ "$1" = --beta ] && [ "$2" = android ]
[ "$(cat "$ANDROID_USER_HOME/debug.keystore")" = test-key ]
mkdir -p "$RELEASE_DIR"
printf verified > "$RELEASE_DIR/app.apk"
`);
  const env = { ...process.env, PATH: `${join(dir, "bin")}:${process.env.PATH}`, RUNNER_TEMP: join(dir, "tmp"),
    RELEASE_DIR: join(dir, "out"), ANDROID_DEBUG_KEYSTORE_B64: Buffer.from("test-key").toString("base64") };
  let result = spawnSync("sh", [".github/release.sh", "android"], { cwd: dir, encoding: "utf8", env });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(join(dir, "out/app.apk"), "utf8"), "verified");
  assert.deepEqual(readdirSync(join(dir, "tmp")), []);
  result = spawnSync("sh", [".github/release.sh", "android"], { cwd: dir, encoding: "utf8", env: { ...env, ANDROID_DEBUG_KEYSTORE_B64: "" } });
  assert.notEqual(result.status, 0, "no package can be made with an unspecified signing key");
});
