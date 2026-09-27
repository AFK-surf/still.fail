import assert from "node:assert/strict";
import test from "node:test";
import { installScript } from "../src/install.ts";

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
