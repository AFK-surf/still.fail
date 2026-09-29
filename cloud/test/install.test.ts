import assert from "node:assert/strict";
import test from "node:test";
import { installScript, releaseType } from "../src/install.ts";

test("the installer braces every variable that words follow, so no shell takes a character for part of its name", () => {
  const script = installScript("https://ember.test");
  // A $name right before a non-ASCII character: under set -u some shells read the character's first byte as the name's.
  assert.deepEqual(script.match(/\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f])/g) ?? [], []);
  assert.match(script, /程序：\$\{app\}（/);
});

test("without a token the installer only updates a station already in a workspace", () => {
  const script = installScript("https://ember.test");
  assert.match(script, /if \[ -z "\$token" \] && \[ ! -f "\$data\/mesh\/cloud.json" \]; then/);
  assert.match(script, /if \[ -n "\$token" \]; then\n  echo "加入 workspace…"/);
});

test("an update hands over to the new release only when the running station says it can and its service is unchanged", () => {
  const script = installScript("https://ember.test");
  assert.match(script, /if \[ -n "\$pid" \] && \[ -n "\$\(said handoff\)" \] && \{ \[ -z "\$service_file" \] \|\| cmp -s "\$tmp\/service" "\$service_file"; \}; then/);
  assert.match(script, /kill -USR2 "\$pid"/);
  // Otherwise drained first (when it can be), then restarted as before.
  assert.match(script, /if \[ -z "\$handed" \] && \[ -n "\$pid" \] && \[ -n "\$\(said drain\)" \]/);
  assert.match(script, /kill -USR1 "\$pid"/);
  assert.match(script, /KillMode=process/);
});

test("the releases bucket serves the station's releases and the apps' builds, and nothing else", () => {
  assert.equal(releaseType("ember-station-linux-x64.tar.gz"), "application/gzip");
  assert.equal(releaseType("desktop/latest-mac.yml"), "text/yaml; charset=utf-8");
  assert.equal(releaseType("desktop/ember-0.1.890-arm64-mac.zip"), "application/zip");
  assert.equal(releaseType("android/latest.json"), "application/json");
  assert.equal(releaseType("station.json"), "application/json");
  assert.equal(releaseType("android/ember-890.apk"), "application/vnd.android.package-archive");
  assert.equal(releaseType("android/../secret"), null);
  assert.equal(releaseType("desktop/other.zip"), null);
});
