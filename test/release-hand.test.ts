import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

// What a CI Mac job handed the put stays in the bucket until the put has put everything: a put cancelled on the way
// (main 912c3551, 2026-11-03) is rerun from the same handover, and found it deleted (404) when taking it back deleted it.
test("a handover is taken back again by a rerun of the put, and deleted only by --drop", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "release-hand-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin");
  const bucket = join(tmp, "bucket");
  mkdirSync(bin);
  mkdirSync(bucket);
  // Cloudflare's R2 API as a directory: each object a file named by its key, / as _.
  writeFileSync(join(bin, "curl"), `#!/bin/sh
out= upload= method=GET url=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -T) shift; upload=$1 ;; -X) shift; method=$1 ;; https://*) url=$1 ;; esac
  shift
done
object="$FAKE_BUCKET/$(printf %s "\${url#*/objects/}" | tr / _)"
if [ -n "$upload" ]; then cp "$upload" "$object"
elif [ "$method" = DELETE ]; then rm "$object"
elif [ -n "$out" ]; then [ -f "$object" ] || exit 22; cp "$object" "$out"
fi
`);
  writeFileSync(join(bin, "pnpm"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(bin, "sleep"), "#!/bin/sh\nexit 0\n");
  for (const name of ["curl", "pnpm", "sleep"]) chmodSync(join(bin, name), 0o755);
  const run = (...args: string[]) => spawnSync("sh", [join(root, "scripts/release-put.sh"), ...args], {
    cwd: root, encoding: "utf8",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake",
      STILLFAIL_DIRECT_DNS: "", FAKE_BUCKET: bucket },
  });

  const made = join(tmp, "made");
  mkdirSync(made);
  writeFileSync(join(made, "station.json"), "{}");
  let result = run("--hand", made);
  assert.equal(result.status, 0, result.stderr);
  const key = result.stdout.trim().split("\n").at(-1)!;
  assert.match(key, /^staged\/\d+-[0-9a-f]+\/hand-[0-9a-f]+\.tar$/);

  // The put, then its rerun, each take it back.
  for (const attempt of ["first", "rerun"]) {
    const dir = join(tmp, attempt);
    result = run("--unhand", dir, key);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(join(dir, "station.json"), "utf8"), "{}");
  }

  result = run("--drop", key);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(bucket, key.replaceAll("/", "_"))), false);
});

// The deltas job takes the station's staged archives back (--unstage) to make their deltas; the put after finds them
// taken, puts them without getting them again, and deletes what was staged as before.
test("--unstage takes staged files back beside their markers; the put then puts them and drops the staged copies", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "release-unstage-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin"), bucket = join(tmp, "bucket"), log = join(tmp, "gets");
  mkdirSync(bin);
  mkdirSync(bucket);
  writeFileSync(join(bin, "curl"), `#!/bin/sh
out= upload= method=GET url=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -T) shift; upload=$1 ;; -X) shift; method=$1 ;; https://*) url=$1 ;; esac
  shift
done
key=\${url#*/objects/}
object="$FAKE_BUCKET/$(printf %s "$key" | tr / _)"
if [ -n "$upload" ]; then cp "$upload" "$object"
elif [ "$method" = DELETE ]; then rm "$object"
elif [ -n "$out" ]; then echo "$key" >> "$FAKE_GETS"; [ -f "$object" ] || exit 22; cp "$object" "$out"
fi
`);
  writeFileSync(join(bin, "pnpm"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(bin, "sleep"), "#!/bin/sh\nexit 0\n");
  for (const name of ["curl", "pnpm", "sleep"]) chmodSync(join(bin, name), 0o755);
  const run = (...args: string[]) => spawnSync("sh", [join(root, "scripts/release-put.sh"), ...args], {
    cwd: root, encoding: "utf8",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake",
      STILLFAIL_DIRECT_DNS: "", FAKE_BUCKET: bucket, FAKE_GETS: log },
  });
  const dir = join(tmp, "release");
  mkdirSync(join(dir, "beta"), { recursive: true });
  writeFileSync(join(dir, "beta/stillfail-station-linux-x64.tar.gz"), "archive");
  writeFileSync(join(dir, "station-beta.json"), "{}");
  let result = run("--stage", dir);
  assert.equal(result.status, 0, result.stderr);
  const marker = join(dir, "beta/stillfail-station-linux-x64.tar.gz.staged");
  const staged = readFileSync(marker, "utf8").trim();

  result = run("--unstage", dir);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(join(dir, "beta/stillfail-station-linux-x64.tar.gz"), "utf8"), "archive");
  assert.ok(existsSync(marker), "the marker stays, for the put to drop what was staged");
  const gets = readFileSync(log, "utf8");

  result = run(dir);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(log, "utf8"), gets, "not got again");
  assert.equal(readFileSync(join(bucket, "beta_stillfail-station-linux-x64.tar.gz"), "utf8"), "archive");
  assert.equal(existsSync(join(bucket, staged.replaceAll("/", "_"))), false, "the staged copy deleted");
  assert.equal(existsSync(marker), false);
});

// An Android release's symbols (scripts/release.sh: symbols/android/…) are put by --files as its APK is, as x-xz; one
// that cannot be put is a warning, taken out all the same (not handed on to a put that would try it again), and the
// release goes on; the APK's failure is still the put's.
test("--files puts an Android release's symbols; their failure alone never fails it", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "release-symbols-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin"), bucket = join(tmp, "bucket");
  mkdirSync(bin);
  mkdirSync(bucket);
  // (a key starting with $FAKE_FAIL is refused; each put's content type beside it, as <object>.type)
  writeFileSync(join(bin, "curl"), `#!/bin/sh
out= upload= method=GET url= type=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -T) shift; upload=$1 ;; -X) shift; method=$1 ;; -H) shift; case "$1" in Content-Type:*) type=\${1#Content-Type: } ;; esac ;; https://*) url=$1 ;; esac
  shift
done
key=\${url#*/objects/}
object="$FAKE_BUCKET/$(printf %s "$key" | tr / _)"
if [ -n "$upload" ]; then case "$key" in "$FAKE_FAIL"*) [ -n "$FAKE_FAIL" ] && exit 22 ;; esac; cp "$upload" "$object"; printf %s "$type" > "$object.type"
elif [ "$method" = DELETE ]; then rm "$object"
elif [ -n "$out" ]; then [ -f "$object" ] || exit 22; cp "$object" "$out"
fi
`);
  writeFileSync(join(bin, "pnpm"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(bin, "sleep"), "#!/bin/sh\nexit 0\n");
  for (const name of ["curl", "pnpm", "sleep"]) chmodSync(join(bin, name), 0o755);
  const run = (fail: string, ...args: string[]) => spawnSync("sh", [join(root, "scripts/release-put.sh"), ...args], {
    cwd: root, encoding: "utf8",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake",
      STILLFAIL_DIRECT_DNS: "", FAKE_BUCKET: bucket, FAKE_FAIL: fail },
  });
  const made = (name: string) => {
    const dir = join(tmp, name);
    mkdirSync(join(dir, "android/beta"), { recursive: true });
    mkdirSync(join(dir, "symbols/android"), { recursive: true });
    writeFileSync(join(dir, "android/stillfail-beta-8300.apk"), "apk");
    writeFileSync(join(dir, "android/beta/latest.json"), "{}");
    writeFileSync(join(dir, "symbols/android/stillfail-beta-8300.syms.xz"), "syms");
    return dir;
  };

  let dir = made("put");
  let result = run("", "--files", dir);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(join(bucket, "symbols_android_stillfail-beta-8300.syms.xz"), "utf8"), "syms");
  assert.equal(readFileSync(join(bucket, "symbols_android_stillfail-beta-8300.syms.xz.type"), "utf8"), "application/x-xz");
  assert.equal(existsSync(join(dir, "symbols/android/stillfail-beta-8300.syms.xz")), false, "taken out once put");
  assert.ok(existsSync(join(dir, "android/beta/latest.json")), "the feed left for the put after");
  rmSync(bucket, { recursive: true });
  mkdirSync(bucket);

  dir = made("refused");
  result = run("symbols/", "--files", dir);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /warning: symbols\/android\/stillfail-beta-8300\.syms\.xz not put/);
  assert.equal(readFileSync(join(bucket, "android_stillfail-beta-8300.apk"), "utf8"), "apk");
  assert.equal(existsSync(join(bucket, "symbols_android_stillfail-beta-8300.syms.xz")), false);
  assert.equal(existsSync(join(dir, "symbols/android/stillfail-beta-8300.syms.xz")), false, "not handed on");

  dir = made("apk-refused");
  result = run("android/stillfail-beta", "--files", dir);
  assert.notEqual(result.status, 0, "the APK's failure is the put's");
});
