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
