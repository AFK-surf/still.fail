import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const envScript = fileURLToPath(new URL("../../../libs/mbui/scripts/env.sh", import.meta.url));

test("the default toolchain does not name a private station session", () => {
  const hasPrivateSession = /\.stillfail\/remote\/sessions\//.test(readFileSync(envScript, "utf8"));
  assert.equal(hasPrivateSession, false, "the toolchain must not name a private station session");
});

test("an explicitly configured toolchain is used, otherwise PATH is left alone", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "mbui-env-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const run = (tools, ci = false) => {
    const env = { HOME: dir, PATH: "/usr/bin:/bin" };
    if (tools) env.MBUI_TOOLS = tools;
    if (ci) env.GITHUB_ACTIONS = "true";
    const child = spawnSync("/bin/bash", ["-c", 'source "$1"; printf "%s\\n%s\\n" "${MOON_HOME:-}" "$PATH"', "_", envScript], { env, encoding: "utf8" });
    assert.equal(child.status, 0, child.stderr);
    return child.stdout.trimEnd().split("\n");
  };
  assert.deepEqual(run(""), ["", "/usr/bin:/bin"]);
  assert.deepEqual(run(dir), [`${dir}/moon`, `${dir}/moon/bin:${dir}/go/bin:${dir}/.local/bin:/usr/bin:/bin`]);
  assert.deepEqual(run("", true), ["", "/usr/bin:/bin"]);
  assert.deepEqual(run(dir, true), [`${dir}/moon`, `${dir}/moon/bin:${dir}/go/bin:${dir}/.local/bin:/usr/bin:/bin`]);
});
