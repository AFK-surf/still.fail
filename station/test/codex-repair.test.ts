import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { canSwitchCodex, captureCodex, codexBinary, missingCodexHost, restoreCodex, switchCodex } from "../src/updates/codex-repair.ts";
import { platform as machine } from "../src/platform/index.ts";
import { platform } from "../src/updates/versions.ts";

const temp = () => realpathSync(mkdtempSync(join(tmpdir(), "stillfail-codex-repair-")));
const native = (path: string) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, Buffer.from("7f454c4601020304", "hex"), { mode: 0o755 });
};
const active = async () => "other stable true\ncode_mode_host stable true\n";

test("a native Codex missing the enabled host is diagnosed; old releases and wrappers are not", async () => {
  const home = temp(), binary = join(home, "bin", "codex");
  native(binary);
  const found = { onPath: binary, real: binary };
  const helper = join(dirname(binary), machine.exe("codex-code-mode-host"));
  assert.deepEqual(await missingCodexHost(found, { HOME: home }, active), { binary, helper });
  assert.equal(await missingCodexHost(found, {}, async () => "code_mode_host stable false\n"), null);
  assert.equal(await missingCodexHost(found, {}, async () => "code_mode_host removed true\n"), null);
  assert.equal(await missingCodexHost(found, {}, async () => "code_mode_host stable false\nother stable true\n"), null);
  assert.equal(await missingCodexHost(found, {}, async () => null), null);
  native(helper);
  assert.equal(await missingCodexHost(found, {}, active), null);
  const wrapper = join(home, "wrapper");
  writeFileSync(wrapper, "#!/bin/sh\n", { mode: 0o755 });
  assert.equal(await missingCodexHost({ onPath: wrapper, real: wrapper }, {}, active), null);
});

test("npm's launcher resolves its platform executable and missing companion", async (t) => {
  const target = platform();
  const triples: Record<string, string> = { "linux-x64": "x86_64-unknown-linux-musl", "linux-arm64": "aarch64-unknown-linux-musl", "darwin-x64": "x86_64-apple-darwin", "darwin-arm64": "aarch64-apple-darwin" };
  if (!target || !triples[target]) return t.skip("no supported native Codex package on this machine");
  const home = temp(), root = join(home, "lib", "node_modules", "@openai", "codex");
  const entry = join(root, "bin", "codex.js");
  mkdirSync(dirname(entry), { recursive: true });
  writeFileSync(entry, "// npm launcher\n");
  const pkg = join(root, "node_modules", "@openai", `codex-${target}`);
  mkdirSync(pkg, { recursive: true });
  writeFileSync(join(pkg, "package.json"), "{}");
  const binary = join(pkg, "vendor", triples[target]!, "bin", machine.exe("codex"));
  native(binary);
  const found = { onPath: entry, real: entry };
  assert.equal(codexBinary(found), binary);
  assert.equal((await missingCodexHost(found, {}, active))?.helper, join(dirname(binary), machine.exe("codex-code-mode-host")));
});

test("switching keeps the old entry and rolls back; it refuses changed or outside-home commands", { skip: !machine.codexStandalone }, () => {
  const home = temp(), old = join(home, "old-codex"), entry = join(home, "bin", "codex"), launcher = join(home, "npm", "codex");
  native(old);
  native(launcher);
  mkdirSync(dirname(entry), { recursive: true });
  symlinkSync(old, entry);
  const found = { onPath: entry, real: old }, env = { HOME: home };
  assert.equal(canSwitchCodex(found, env), true);
  assert.equal(canSwitchCodex(found, { HOME: temp() }), false);
  const captured = captureCodex(found, env)!;
  const backup = switchCodex(captured, launcher, env);
  assert.equal(readlinkSync(backup), old);
  assert.equal(realpathSync(entry), launcher);
  restoreCodex(entry, launcher, backup);
  assert.equal(readlinkSync(entry), old);
  assert.equal(existsSync(backup), false);
  assert.deepEqual(readFileSync(old), Buffer.from("7f454c4601020304", "hex"));
  const stale = captureCodex(found, env)!;
  writeFileSync(old, Buffer.from("7f454c460102030405", "hex"));
  assert.throws(() => switchCodex(stale, launcher, env), /changed/);
  assert.equal(readlinkSync(entry), old);
});

test("rollback preserves a command changed after the switch and keeps its backup", { skip: !machine.codexStandalone }, () => {
  const home = temp(), entry = join(home, "codex"), launcher = join(home, "npm-codex");
  native(entry);
  native(launcher);
  const env = { HOME: home }, captured = captureCodex({ onPath: entry, real: entry }, env)!;
  const backup = switchCodex(captured, launcher, env);
  unlinkSync(entry);
  writeFileSync(entry, "a different command");
  assert.throws(() => restoreCodex(entry, launcher, backup), /command changed/);
  assert.equal(readFileSync(entry, "utf8"), "a different command");
  assert.ok(existsSync(backup));
  unlinkSync(entry);
  symlinkSync(launcher, entry);
  restoreCodex(entry, launcher, backup);
  assert.deepEqual(readFileSync(entry), Buffer.from("7f454c4601020304", "hex"));
  assert.equal(existsSync(backup), false);
});
