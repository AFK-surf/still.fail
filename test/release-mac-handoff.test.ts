import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

// The same signed Mac archive goes both to the release bucket and to the monoid build. The bucket put consumes
// its staging copy, so the handoff must see it first (main 8aaaab30, 2026-11-06).
test("the monoid handoff gets the Mac archive before the release put consumes it", (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const workflow = readFileSync(join(root, ".github/workflows/pipeline.yml"), "utf8");
  const desktop = workflow.match(/^  desktop:\n([\s\S]*?)(?=^  [\w-]+:\n)/m)?.[1];
  assert.ok(desktop, "desktop job is present");
  const artifact = desktop.indexOf("name: mac-beta-${{ github.sha }}");
  const put = desktop.indexOf('sh scripts/release-put.sh --files "$RUNNER_TEMP/release"');
  assert.ok(artifact >= 0 && put >= 0, "desktop job hands off the Mac archive and puts its release files");
  assert.match(desktop.slice(artifact, artifact + 250), /path: \$\{\{ runner\.temp \}\}\/release\/desktop\/stillfail-beta-\*-arm64-mac\.zip/);
  assert.match(desktop.slice(artifact, artifact + 250), /if-no-files-found: error/);

  const tmp = mkdtempSync(join(tmpdir(), "release-mac-handoff-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const bin = join(tmp, "bin"), release = join(tmp, "release"), bucket = join(tmp, "bucket");
  mkdirSync(bin);
  mkdirSync(join(release, "desktop"), { recursive: true });
  writeFileSync(join(bin, "curl"), `#!/bin/sh
upload=
while [ "$#" -gt 0 ]; do
  case "$1" in -T) shift; upload=$1 ;; esac
  shift
done
[ -n "$upload" ] && cp "$upload" "$FAKE_OBJECT"
`);
  chmodSync(join(bin, "curl"), 0o755);
  const archive = join(release, "desktop", "stillfail-beta-0.1.123-arm64-mac.zip");
  writeFileSync(archive, "signed archive");
  let handoff = "";
  for (const step of [{ at: artifact, kind: "handoff" }, { at: put, kind: "put" }].sort((a, b) => a.at - b.at)) {
    if (step.kind === "handoff") {
      assert.ok(existsSync(archive), "the upload-artifact step can find the signed archive");
      handoff = readFileSync(archive, "utf8");
    } else {
      const result = spawnSync("sh", [join(root, "scripts/release-put.sh"), "--files", release], {
        cwd: root, encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
          CLOUDFLARE_API_TOKEN: "fake", CLOUDFLARE_ACCOUNT_ID: "fake", STILLFAIL_DIRECT_DNS: "", FAKE_OBJECT: bucket },
      });
      assert.equal(result.status, 0, result.stderr);
    }
  }
  assert.equal(handoff, "signed archive");
  assert.equal(readFileSync(bucket, "utf8"), handoff);
  assert.equal(existsSync(archive), false);
});
