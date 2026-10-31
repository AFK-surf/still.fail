import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

// Exercise the actual upload entry point with a fake bucket and fake credentials. The signed archive in the warm
// build directory is a different file from the copy handed to the upload step.
test("a local Mac archive goes only after the uploaded bytes have been checked", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "release-cache-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "curl"), `#!/bin/sh
out= upload=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -T) shift; upload=$1 ;; esac
  shift
done
if [ -n "$upload" ]; then
  [ "\${FAKE_PUT:-}" != fail ] || exit 1
  cp "$upload" "$FAKE_OBJECT"
elif [ -n "$out" ]; then
  [ "\${FAKE_GET:-}" != fail ] || exit 1
  if [ "\${FAKE_GET:-}" = corrupt ]; then printf wrong > "$out"; else cp "$FAKE_OBJECT" "$out"; fi
fi
`);
  writeFileSync(join(bin, "pnpm"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(bin, "sleep"), "#!/bin/sh\nexit 0\n");
  for (const name of ["curl", "pnpm", "sleep"]) chmodSync(join(bin, name), 0o755);
  const key = "desktop/stillfail-beta-0.1.123-arm64-mac.zip";
  const source = join(tmp, "stillfail-beta-123-arm64-mac.zip");
  const stage = join(tmp, "release", key);
  const object = join(tmp, "object");
  mkdirSync(join(tmp, "release", "desktop"), { recursive: true });
  const run = (options: Record<string, string> = {}) => spawnSync("sh", [join(root, "scripts/release-put.sh"), "--files", join(tmp, "release")], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: "fake",
      CLOUDFLARE_ACCOUNT_ID: "fake", STILLFAIL_DIRECT_DNS: "", FAKE_OBJECT: object,
      STILLFAIL_RELEASE_CACHE_KEY: key, STILLFAIL_RELEASE_CACHE_SOURCE: source, ...options },
  });
  const prepare = () => { writeFileSync(source, "signed archive"); writeFileSync(stage, "signed archive"); };

  prepare();
  let result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(object, "utf8"), "signed archive");
  assert.equal(existsSync(source), false);
  assert.equal(existsSync(stage), false);

  prepare();
  result = run({ FAKE_PUT: "fail" });
  assert.notEqual(result.status, 0, result.stderr);
  assert.equal(readFileSync(source, "utf8"), "signed archive");
  assert.equal(readFileSync(stage, "utf8"), "signed archive");

  result = run({ FAKE_GET: "corrupt" });
  assert.notEqual(result.status, 0, result.stderr);
  assert.equal(readFileSync(source, "utf8"), "signed archive");
  assert.equal(readFileSync(stage, "utf8"), "signed archive");

  // Another build's file at the warm path must not be mistaken for this upload.
  writeFileSync(source, "different archive");
  result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(source, "utf8"), "different archive");
  assert.equal(existsSync(stage), false);

  // Stable checks out the reviewed release, which can have an older helper; it runs the workflow's copy instead.
  const savedHelper = join(tmp, "release-put-cleanup.sh");
  copyFileSync(join(root, "scripts/release-put.sh"), savedHelper);
  const clean = (options: Record<string, string> = {}) => spawnSync("sh", [savedHelper,
    "--clean-uploaded", key, source], {
    cwd: root, encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
      CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake", STILLFAIL_DIRECT_DNS: "", FAKE_OBJECT: object,
      STILLFAIL_RELEASE_TOOLS_ROOT: root, ...options },
  });
  // The stable publisher uploads directly. Its local copy is cleaned by the same byte check afterwards.
  writeFileSync(source, "signed archive");
  result = clean({ FAKE_GET: "fail" });
  assert.notEqual(result.status, 0, result.stderr);
  assert.equal(existsSync(source), true);
  result = clean({ FAKE_GET: "corrupt" });
  assert.notEqual(result.status, 0, result.stderr);
  assert.equal(existsSync(source), true);
  result = clean();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(source), false);
});

test("the standalone Mac publisher removes only the verified build copy", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "mbui-release-cache-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin"), cache = join(tmp, "cache"), work = join(tmp, "work");
  const staged = join(tmp, "release", "mac", "mac"), built = join(work, "out/mac/stillfail-mbui-123-arm64-mac.zip");
  mkdirSync(bin, { recursive: true });
  mkdirSync(join(staged, "mbui"), { recursive: true });
  mkdirSync(join(work, "out/mac"), { recursive: true });
  writeFileSync(join(bin, "curl"), `#!/bin/sh
out= upload=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -T) shift; upload=$1 ;; esac
  shift
done
if [ -n "$upload" ]; then cp "$upload" "$FAKE_OBJECT"
elif [ -n "$out" ]; then
  if [ "\${FAKE_GET:-}" = corrupt ]; then printf wrong > "$out"; else cp "$FAKE_OBJECT" "$out"; fi
fi
`);
  chmodSync(join(bin, "curl"), 0o755);
  const name = "stillfail-mbui-123-arm64-mac.zip";
  writeFileSync(join(staged, "mbui/latest.json"), JSON.stringify({ versionCode: 123, file: `mac/${name}` }));
  const run = (fakeGet = "") => spawnSync("bash", [join(root, "apps/mbui/scripts/beta.sh"), "publish", "mac"], {
    cwd: root, encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
      MBUI_CACHE: cache, MBUI_FRESH: "0", WORK: work, RELEASE_DIR: join(tmp, "release"),
      CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake", STILLFAIL_DIRECT_DNS: "",
      STILLFAIL_RELEASE_CACHE_KEY: "", FAKE_OBJECT: join(tmp, "object"), FAKE_GET: fakeGet },
  });
  const prepare = () => { writeFileSync(built, "signed archive"); writeFileSync(join(staged, name), "signed archive"); };
  prepare();
  let result = run("corrupt");
  assert.notEqual(result.status, 0, result.stderr);
  assert.equal(existsSync(built), true);
  prepare();
  result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(built), false);
});
