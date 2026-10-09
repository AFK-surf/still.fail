# The Windows app (apps/desktop/build.sh --win) on a Windows machine (.github/workflows/pipeline.yml, windows-smoke):
# installed as a user would (the NSIS installer, silent), its iroh addon (mesh.node, MinGW's) loaded by its own
# Electron as Node, its core started on a data directory of its own, then the app itself started and its window
# photographed. What it saw goes to $RUNNER_TEMP/smoke (the run's artifact windows-smoke-<sha>).
param([Parameter(Mandatory)] [string] $Dir)
$ErrorActionPreference = "Stop"
$smoke = Join-Path $env:RUNNER_TEMP "smoke"
New-Item -ItemType Directory -Force $smoke | Out-Null

$installer = Get-ChildItem $Dir -Filter "*-win.exe" | Select-Object -First 1
if (-not $installer) { throw "no installer in $Dir" }
Write-Host "installing $($installer.Name)"
$install = Start-Process $installer.FullName -ArgumentList "/S" -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "the installer exited $($install.ExitCode)" }

# Per user (package.json build.nsis), in a folder of its own (build.sh: the package's name).
$exe = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Programs") -Recurse -Filter "*.exe" |
  Where-Object { $_.Name -in @("still.fail.exe", "youdid.wtf.exe") } | Select-Object -First 1
if (-not $exe) { throw "the app is not where the installer puts it" }
Write-Host "installed: $($exe.FullName)"
$resources = Join-Path $exe.DirectoryName "resources"

# A script in the app's Electron as Node, waited for (the app is a GUI program: PowerShell neither waits for it nor
# gets its exit code otherwise), its output shown.
function Run-Node([string] $name, [string] $js, [string[]] $more) {
  $file = Join-Path $smoke "$name.js"
  Set-Content -Path $file -Value $js -Encoding utf8
  $env:ELECTRON_RUN_AS_NODE = "1"
  $quoted = (@($file) + $more | ForEach-Object { '"' + $_ + '"' }) -join " "
  $out = Join-Path $smoke "$name.out.txt"
  $err = Join-Path $smoke "$name.err.txt"
  $p = Start-Process $exe.FullName -ArgumentList $quoted -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
  Remove-Item Env:ELECTRON_RUN_AS_NODE
  Get-Content $out, $err | Write-Host
  if ($p.ExitCode -ne 0) { throw "$name exited $($p.ExitCode)" }
}

# The addon: napi-rs finds Node-API in the executable (scripts/native.ts noLibnode).
$mesh = Join-Path $resources "mesh.node"
Run-Node "mesh" "const m = require(process.argv[2]); console.log('mesh.node:', Object.keys(m).sort().join(' '));" @($mesh)

# The core (apps/desktop/src/core.ts's start), a page connected to it, for a few seconds: nothing thrown.
$core = Join-Path $resources "app.asar/build/app/core-ts.js"
$data = Join-Path $env:RUNNER_TEMP "core-data"
Run-Node "core" @"
const [core, data, mesh] = process.argv.slice(2);
process.env.STILLFAIL_MESH_NATIVE = mesh;
process.on('uncaughtException', (e) => { console.error('core threw:', e); process.exit(1); });
const { start } = require(core);
const said = [];
const c = start(data, 'https://app.youdid.wtf', (_client, json) => said.push(json.slice(0, 200)), 'beta');
const client = c.connect();
setTimeout(() => { c.disconnect(client); console.log('core: up 8 s,', said.length, 'messages; first:', said[0] ?? '(none)'); process.exit(0); }, 8000);
"@ @($core, $data, $mesh)

# The app, as a user starts it: alive after 25 s, its window photographed.
$env:ELECTRON_ENABLE_LOGGING = "1"
$app = Start-Process $exe.FullName -PassThru -RedirectStandardError (Join-Path $smoke "app-stderr.txt") -RedirectStandardOutput (Join-Path $smoke "app-stdout.txt")
Start-Sleep -Seconds 25
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$shot = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
[System.Drawing.Graphics]::FromImage($shot).CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$shot.Save((Join-Path $smoke "window.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$windows = Get-Process | Where-Object { $_.Path -eq $exe.FullName -and $_.MainWindowTitle } | ForEach-Object { $_.MainWindowTitle }
Write-Host "windows: $($windows -join ' | ')"
if ($app.HasExited) { throw "the app exited ($($app.ExitCode))" }
if (-not $windows) { throw "the app shows no window" }
Get-Process | Where-Object { $_.Path -eq $exe.FullName } | Stop-Process -Force
Write-Host "ok"
