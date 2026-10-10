import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { windowsInstallScript } from "../src/install-windows.ts";

test("the Windows installer has every placeholder filled, in both languages and channels", () => {
  for (const lang of ["zh", "en"] as const) {
    for (const channel of ["stable", "beta"] as const) {
      const script = windowsInstallScript("https://ember.test", channel, lang);
      assert.doesNotMatch(script, /__[A-Z]+_*/);
      assert.match(script, new RegExp(`\\$channel = if \\(\\$env:STILLFAIL_CHANNEL\\) \\{ \\$env:STILLFAIL_CHANNEL \\} else \\{ '${channel}' \\}`));
    }
  }
  // A message with values is PowerShell's -f over them, its quotes doubled.
  assert.match(windowsInstallScript("https://ember.test", "stable", "en"), /\('[^']*\{0\}[^']*' -f \$nodeVersion\)/);
});

test("the Windows installer keeps its state in its own scope", () => {
  // It runs as a script block (`& ([scriptblock]::Create(...))`): $script: and $global: there are its caller's, so a
  // function setting one leaves the installer's variable as it was.
  assert.deepEqual(windowsInstallScript("https://ember.test").match(/\$(script|global):\w+/gi) ?? [], []);
});

test("the stillfail command the installer writes runs the release under a home with other than ASCII in its path", { skip: (spawnSync("powershell", ["-NoProfile", "-Command", "exit 0"]).status !== 0 || spawnSync("cmd", ["/d", "/c", "exit 0"]).status !== 0) && "no PowerShell and cmd" }, () => {
  const dir = mkdtempSync(join(tmpdir(), "install-cmd-"));
  try {
    const home = join(dir, "张三");
    const release = join(home, ".stillfail", "app", "bin");
    mkdirSync(release, { recursive: true });
    writeFileSync(join(release, "stillfail.cmd"), "@echo the release's stillfail %*\r\n");
    // The installer's own functions, as it has them, with its Fail.
    const script = windowsInstallScript("https://ember.test");
    const fn = (name: string) => script.match(new RegExp(`^function ${name}\\(.*?^}$`, "ms"))![0];
    const file = join(dir, "write.ps1");
    writeFileSync(file, "﻿" + ["function Fail([string]$t) { throw $t }", fn("CmdPath"), fn("WriteCmd"),
      `WriteCmd (Join-Path $env:TEST_DIR 'stillfail.cmd') (Join-Path $env:USERPROFILE '.stillfail\\app\\bin\\stillfail.cmd')`].join("\n"));
    const env = { ...process.env, USERPROFILE: home, TEST_DIR: dir };
    const wrote = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", file], { env, encoding: "utf8" });
    assert.equal(wrote.status, 0, wrote.stdout + wrote.stderr);
    assert.equal(readFileSync(join(dir, "stillfail.cmd"), "utf8").trim(), '@"%USERPROFILE%\\.stillfail\\app\\bin\\stillfail.cmd" %*');
    const ran = spawnSync("cmd", ["/d", "/c", join(dir, "stillfail.cmd"), "status"], { env, encoding: "utf8" });
    assert.equal(ran.stdout.trim(), "the release's stillfail status", ran.stderr);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the Windows installer is one PowerShell parses", { skip: spawnSync("powershell", ["-NoProfile", "-Command", "exit 0"]).status !== 0 && "no PowerShell" }, () => {
  const dir = mkdtempSync(join(tmpdir(), "install-ps1-"));
  try {
    for (const lang of ["zh", "en"] as const) {
      const file = join(dir, `install-${lang}.ps1`);
      // With a BOM, as PowerShell 5.1 reads a file of non-ASCII words.
      writeFileSync(file, "﻿" + windowsInstallScript("https://it's.ember.test", "stable", lang));
      const parsed = spawnSync("powershell", ["-NoProfile", "-Command",
        `$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('${file.replaceAll("'", "''")}', [ref]$null, [ref]$e); $e | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }`,
      ], { encoding: "utf8" });
      assert.equal(parsed.status, 0, parsed.stderr);
      assert.equal(parsed.stdout.trim(), "", `${lang}: ${parsed.stdout}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
