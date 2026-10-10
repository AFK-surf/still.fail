import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
