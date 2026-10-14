import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { bundledWindowsInstallScript, windowsInstallScript } from "../src/install-windows.ts";

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

test("the installer a Windows release carries is the cloud's, its cloud the one the station names", () => {
  for (const lang of ["zh", "en"] as const) {
    const script = bundledWindowsInstallScript(lang);
    assert.ok(script.startsWith(String.fromCharCode(0xfeff)), "with a BOM");
    assert.doesNotMatch(script, /__[A-Z]+_*/);
    assert.match(script, /^\$origin = \$env:STILLFAIL_ORIGIN\nif \(-not \$origin\) \{/m);
    assert.match(script, new RegExp(`\\$lang = if \\(\\$env:STILLFAIL_INSTALL_LANG\\) \\{ \\$env:STILLFAIL_INSTALL_LANG \\} else \\{ '${lang}' \\}`));
  }
  const script = windowsInstallScript("https://ember.test");
  // The release's hash, when the station gives it, checked before it is opened; its own installer handed it, once.
  assert.match(script, /if \(\$env:STILLFAIL_RELEASE_SHA256 -and \(Get-FileHash -Algorithm SHA256 \$zip\)\.Hash -ne \$env:STILLFAIL_RELEASE_SHA256\) \{ Fail/);
  assert.ok(script.indexOf("STILLFAIL_RELEASE_SHA256 -and (Get-FileHash") < script.indexOf("Expand-Archive -Path $zip"));
  assert.ok(script.includes("-match '[\\\\/]stillfail-handed-[0-9a-f]+[\\\\/]stillfail\\.zip$'"));
  assert.match(script, /if \(\$env:STILLFAIL_RELEASE_SHA256 -and -not \$env:STILLFAIL_INSTALLER_HANDED -and \(Test-Path -LiteralPath \$itsOwn\)\)/);
  // node.exe checked by its signed hash when there is one.
  assert.match(script, /if \(\$signedNode -and \(Get-FileHash -Algorithm SHA256 \(Join-Path \$part 'node\.exe'\)\)\.Hash -ne \$signedNode\) \{ Fail/);
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

/** PowerShell here, if any: Windows' own, or pwsh (STILLFAIL_PWSH names one elsewhere). */
const powershell = [process.env.STILLFAIL_PWSH, "powershell", "pwsh"].find((p) => p && spawnSync(p, ["-NoProfile", "-Command", "exit 0"]).status === 0);

test("a Windows station updating itself installs only the release its signed words name, by that release's own installer", { skip: !powershell && "no PowerShell" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "install-signed-"));
  const { createHash } = await import("node:crypto");
  const { execFile, execFileSync } = await import("node:child_process");
  const { createServer } = await import("node:http");
  const server = createServer((req, res) => {
    if (req.url === "/releases/stillfail-station-win32-x64.zip") return void res.end(readFileSync(join(dir, "release.zip")));
    res.writeHead(404).end();
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  try {
    // The release, carrying its installer: here one that says it ran, handed the download.
    const release = join(dir, "release", "stillfail", "bin");
    mkdirSync(release, { recursive: true });
    writeFileSync(join(release, "install.en.ps1"), "Set-Content -Path (Join-Path $env:STILLFAIL_DATA 'handed') -Value ('handed ' + $env:STILLFAIL_INSTALLER_HANDED + ' ' + (Test-Path -LiteralPath $env:STILLFAIL_ARCHIVE))\nexit 0\n");
    execFileSync("zip", ["-qr", join(dir, "release.zip"), "stillfail"], { cwd: join(dir, "release") });
    const sha = createHash("sha256").update(readFileSync(join(dir, "release.zip"))).digest("hex");
    const data = join(dir, "data");
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), "{}");
    const script = join(dir, "install.ps1");
    writeFileSync(script, bundledWindowsInstallScript("en"));
    const run = (sha256: string) =>
      new Promise<{ code: number; out: string }>((resolve) =>
        execFile(powershell!, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script], {
          env: { ...process.env, STILLFAIL_ORIGIN: `http://127.0.0.1:${(server.address() as { port: number }).port}`, STILLFAIL_DATA: data, STILLFAIL_RELEASE_SHA256: sha256, STILLFAIL_INSTALL_LANG: "en", PROCESSOR_ARCHITECTURE: "AMD64", USERPROFILE: dir },
          timeout: 120_000,
        }, (e, out, err) => resolve({ code: e ? ((e as { code?: number }).code ?? 1) : 0, out: out + err })),
      );
    const bad = await run("0".repeat(64));
    assert.equal(bad.code, 1, bad.out);
    assert.match(bad.out, /not the one its signature names/);
    assert.ok(!existsSync(join(data, "handed")) && !existsSync(join(data, "app")));
    const good = await run(sha);
    assert.equal(good.code, 0, good.out);
    assert.equal(readFileSync(join(data, "handed"), "utf8").trim(), "handed 1 True");
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
