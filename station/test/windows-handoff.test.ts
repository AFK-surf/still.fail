// The old station reads update.log as UTF-8: a new installer's diagnostic must survive that whole path.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { windowsInstallScript } from "../../cloud/src/install-windows.ts";
import { windowsUpdateScript } from "../src/platform/windows.ts";

test("a Windows handover reason reaches the old station's update log in Chinese", { skip: process.platform !== "win32" && "Windows' PowerShell" }, () => {
  const dir = mkdtempSync(join(tmpdir(), "handoff-log-"));
  try {
    const script = windowsInstallScript("https://ember.test", "stable", "zh");
    const why = script.match(/^function HandoffWhy \{.*?^\}/ms)?.[0];
    const fail = script.match(/^function Fail\([^\n]+$/m)?.[0];
    assert.ok(why && fail);
    const reason = "无法读取配置：文件可能已加密或损坏，请允许程序读取。";
    writeFileSync(join(dir, "handoff-error"), reason + "\n");
    writeFileSync(join(dir, "install.ps1"), "\ufeff$run = $env:STILLFAIL_DATA\n" + why + "\n" + fail + "\nFail (HandoffWhy)\n");
    const update = join(dir, "update.ps1");
    writeFileSync(update, windowsUpdateScript(dir, { STILLFAIL_DATA: dir }, "still.fail diagnostic test (not registered)"));
    const ran = spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", update], { encoding: "utf8", timeout: 60_000 });
    assert.equal(ran.status, 0, ran.stderr);
    assert.equal(readFileSync(join(dir, "update.exit"), "utf8").trim(), "1");
    assert.ok(readFileSync(join(dir, "update.log"), "utf8").includes(reason));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
