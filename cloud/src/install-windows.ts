// The still.fail station's installer for Windows, served at /install.ps1 (install.ts is macOS's and Linux's): in
// PowerShell on the machine that is to be a station, `& ([scriptblock]::Create((irm <origin>/install.ps1))) <token>`.
// It does what install.sh does, the Windows way (docs/station-ts-native.md, "Windows"):
// - the release (stillfail-station-win32-x64.zip) in ~\.stillfail\app; the Node it runs on (NODE_VERSION) downloaded
//   once per version into ~\.stillfail\node\v<version> and checked, then copied to <app>\node (no links: they take a
//   privilege on Windows); the machine's own node.exe when it is that very version;
// - `stillfail` (a .cmd) in ~\.local\bin, which is put on the user's PATH when it is not;
// - joins the workspace the token is for;
// - runs the station at sign-in: a scheduled task of the user's (no administrator needed), started now, which runs the
//   launcher with no window (stillfail-station-w.exe) and starts it again should it end;
// - an update (no token, a station already in a workspace) stops the running station first: Windows keeps a running
//   program's files, so there is no handing over in place; the station stops its turns as it stops for a restart, and
//   the next one goes on with them. One already on this release is left as it is.
// The script uses no backtick and no "${" (it is a template here): PowerShell's escapes are not needed in it.

import { tr, type Lang } from "./i18n.ts";

/** A message as a PowerShell expression: its words, its {arguments} the PowerShell variables named in `args`. */
function say(lang: Lang, key: string, args: Record<string, string> = {}): string {
  const names = Object.keys(args);
  const marks = Object.fromEntries(names.map((n, i) => [n, `\u0000${i}\u0000`]));
  const text = tr(lang, key, marks)
    .replaceAll("'", "''")
    .replaceAll("{", "{{")
    .replaceAll("}", "}}")
    .replace(/\u0000(\d+)\u0000/g, (_, i) => `{${i}}`);
  return names.length === 0 ? `'${text}'` : `('${text}' -f ${names.map((n) => args[n]).join(", ")})`;
}

/** The installer for a still.fail cloud at `origin`, getting `channel`'s release unless STILLFAIL_CHANNEL says. */
export function windowsInstallScript(origin: string, channel: "stable" | "beta" = "stable", lang: Lang = "zh"): string {
  const s = (key: string, args?: Record<string, string>) => say(lang, key, args);
  return SCRIPT.replaceAll("__ORIGIN__", origin.replaceAll("'", "''"))
    .replaceAll("__CHANNEL__", channel)
    .replace(/__SAY\(([a-zA-Z.]+)(?:, ([^)]*))?\)/g, (_, key: string, args?: string) =>
      s(key, args ? Object.fromEntries(args.split(";").map((a) => a.split("=").map((x) => x.trim()) as [string, string])) : undefined),
    );
}

// __SAY(key, name=$variable; …) is a message (say above).
const SCRIPT = `# still.fail station installer for Windows (cloud/src/install-windows.ts).
param([string]$Token = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$origin = '__ORIGIN__'
if (-not $Token -and $env:STILLFAIL_TOKEN) { $Token = $env:STILLFAIL_TOKEN }
function Say([string]$text) { Write-Host $text }
function Fail([string]$text) { [Console]::Error.WriteLine($text); exit 1 }

$data = if ($env:STILLFAIL_DATA) { $env:STILLFAIL_DATA } elseif ($env:EMBER_DATA) { $env:EMBER_DATA } else { Join-Path $env:USERPROFILE '.stillfail' }
$run = Join-Path $data 'run'
# Where the update is, for the station to show on its pages: download, restart.
function Step([string]$what) { if (Test-Path $run) { Set-Content -Path (Join-Path $run 'update.step') -Value $what -ErrorAction SilentlyContinue } }
if (-not $Token -and -not (Test-Path (Join-Path $data 'mesh\\cloud.json'))) {
  [Console]::Error.WriteLine(__SAY(cloud.install.win.usage, origin=$origin))
  [Console]::Error.WriteLine(__SAY(cloud.install.updateNoToken))
  exit 2
}
$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
# x64, and ARM64 (which runs x64 programs).
if ($arch -notin 'AMD64', 'ARM64') { $machine = "Windows $arch"; Fail (__SAY(cloud.install.unsupported, machine=$machine)) }
$platform = 'win32-x64'
$app = Join-Path $data 'app'
# STILLFAIL_TASK and STILLFAIL_BIN, as STILLFAIL_DATA, put a station apart (a test's): its task, where its command goes.
# Kept in windows.json for its updates (the station's own update is not told them).
$apart = $null
try { $apart = Get-Content -Raw (Join-Path $data 'windows.json') | ConvertFrom-Json } catch {}
if ($env:STILLFAIL_TASK) { $task = $env:STILLFAIL_TASK } elseif ($apart.task) { $task = $apart.task } else { $task = 'still.fail station' }
if ($env:STILLFAIL_BIN) { $binApart = $env:STILLFAIL_BIN } elseif ($apart.bin) { $binApart = $apart.bin } else { $binApart = $null }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('stillfail-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
$channel = if ($env:STILLFAIL_CHANNEL) { $env:STILLFAIL_CHANNEL } else { '__CHANNEL__' }
if ($channel -eq 'beta') { $release = "beta/stillfail-station-$platform.zip"; Say (__SAY(cloud.install.downloadBeta)) }
else { $channel = 'stable'; $release = "stillfail-station-$platform.zip"; Say (__SAY(cloud.install.download)) }
Step 'download'
Invoke-WebRequest -UseBasicParsing "$origin/releases/$release" -OutFile (Join-Path $tmp 'stillfail.zip')
Expand-Archive -Path (Join-Path $tmp 'stillfail.zip') -DestinationPath $tmp -Force
$new = Join-Path $tmp 'stillfail'
Set-Content -Path (Join-Path $new 'CHANNEL') -Value $channel

# The Node it runs on: kept in node\\v<version> beside the data, once per version, and copied to <app>\\node.
$nodeVersion = (Get-Content (Join-Path $new 'NODE_VERSION') -Raw).Trim()
$nodeDir = Join-Path $data "node\\v$nodeVersion"
if (-not (Test-Path (Join-Path $nodeDir 'node.exe'))) {
  $part = "$nodeDir.part"
  if (Test-Path $part) { Remove-Item -Recurse -Force $part }
  New-Item -ItemType Directory -Force $part | Out-Null
  # The node.exe that node on PATH runs, when it is this version: what is on PATH can be a version manager's shim.
  $own = Get-Command node.exe -ErrorAction SilentlyContinue
  $ownExe = if ($own) { try { & $own.Source -e "if (process.version === 'v$nodeVersion') console.log(process.execPath)" 2>$null } catch { $null } }
  if ($ownExe -and (Test-Path -LiteralPath $ownExe)) {
    Copy-Item -LiteralPath $ownExe (Join-Path $part 'node.exe')
  } else {
    $nodeFile = "node-v$nodeVersion-win-x64.zip"
    Say (__SAY(cloud.install.node.download, version=$nodeVersion))
    try {
      Invoke-WebRequest -UseBasicParsing "$origin/releases/node/$nodeFile" -OutFile (Join-Path $tmp $nodeFile)
      $want = ((Invoke-WebRequest -UseBasicParsing "$origin/releases/node/$nodeFile.sha256").Content -split '\\s+')[0]
    } catch { Fail (__SAY(cloud.install.node.failed, version=$nodeVersion; origin=$origin)) }
    $got = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp $nodeFile)).Hash
    if (-not $want -or $want -ne $got) { Fail (__SAY(cloud.install.node.mismatch, version=$nodeVersion)) }
    Expand-Archive -Path (Join-Path $tmp $nodeFile) -DestinationPath (Join-Path $tmp 'node') -Force
    Copy-Item (Join-Path $tmp "node\\node-v$nodeVersion-win-x64\\node.exe") (Join-Path $part 'node.exe')
  }
  if ((& (Join-Path $part 'node.exe') -v) -ne "v$nodeVersion") { Fail (__SAY(cloud.install.node.broken, version=$nodeVersion)) }
  Move-Item $part $nodeDir
}
New-Item -ItemType Directory -Force (Join-Path $new 'node') | Out-Null
Copy-Item (Join-Path $nodeDir 'node.exe') (Join-Path $new 'node\\node.exe')

# What runs now, by run\\station.json: still that launcher (a pid is reused once its process is gone).
$station = $null
$said = $null
try { $said = Get-Content (Join-Path $run 'station.json') -Raw | ConvertFrom-Json } catch {}
if ($said -and $said.pid) {
  $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$said.pid) -ErrorAction SilentlyContinue
  if ($p -and $p.Name -like 'stillfail-station*') { $station = $p }
}
$haveTask = [bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
# Already on this release, and running as its task runs it: nothing to do.
$version = Join-Path $app 'VERSION'
if (-not $Token -and $station -and $haveTask -and (Test-Path $version) -and ((Get-Content $version -Raw).Trim() -eq (Get-Content (Join-Path $new 'VERSION') -Raw).Trim())) {
  Copy-Item (Join-Path $new 'CHANNEL') (Join-Path $app 'CHANNEL') -ErrorAction SilentlyContinue
  $short = (Get-Content $version -Raw).Trim().Substring(0, 7)
  Say (__SAY(cloud.install.upToDate, version=$short))
  exit 0
}

# Stopped before its files are replaced: the launcher ended (its task too), and the station, its control pipe closed,
# stops by itself; whatever of it is left after 30 s is ended.
Step 'restart'
if ($station -or $haveTask) {
  Say (__SAY(cloud.install.win.stopping))
  if ($haveTask) { Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue }
  if ($station) { Stop-Process -Id $station.ProcessId -Force -ErrorAction SilentlyContinue }
  $ours = { Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($app) -and $_.Name -in 'node.exe', 'stillfail-station.exe', 'stillfail-station-w.exe' } }
  $deadline = (Get-Date).AddSeconds(30)
  while ((& $ours) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  & $ours | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
New-Item -ItemType Directory -Force $data | Out-Null
# The release before goes aside: its runners (agents', jobs') go on running from there, which Windows lets a directory
# be moved but not removed for; what no runner holds any more is removed, now or at a next update.
$old = { Get-ChildItem $data -Directory -Filter 'app.old*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
& $old
if (Test-Path $app) { Move-Item $app ($app + '.old-' + (Get-Date -Format 'yyyyMMddHHmmss')) }
Move-Item $new $app
& $old
# The Nodes no release here runs on any more.
Get-ChildItem (Join-Path $data 'node') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $nodeDir } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# The command: ~\\.local\\bin\\stillfail.cmd, that directory on the user's PATH.
$bin = if ($binApart) { $binApart } else { Join-Path $env:USERPROFILE '.local\\bin' }
New-Item -ItemType Directory -Force $bin | Out-Null
Set-Content -Path (Join-Path $bin 'stillfail.cmd') -Encoding ASCII -Value ('@"' + (Join-Path $app 'bin\\stillfail.cmd') + '" %*')
$kept = @{}
if ($task -ne 'still.fail station') { $kept.task = $task }
if ($binApart) { $kept.bin = $binApart }
if ($kept.Count -gt 0) { $kept | ConvertTo-Json | Set-Content -Path (Join-Path $data 'windows.json') -Encoding UTF8 }
else { Remove-Item (Join-Path $data 'windows.json') -ErrorAction SilentlyContinue }
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $binApart -and -not (($userPath -split ';') -contains $bin)) {
  [Environment]::SetEnvironmentVariable('Path', ((@($bin) + @($userPath -split ';' | Where-Object { $_ })) -join ';'), 'User')
  Say (__SAY(cloud.install.win.pathAdded, dir=$bin))
}

if ($Token) {
  Say (__SAY(cloud.install.join))
  & (Join-Path $app 'mesh\\target\\release\\stillfail-station.exe') enroll $origin $Token --data $data
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# At sign-in, with no window; started again a minute after it ends (the launcher itself starts its station again).
$launch = Join-Path $app 'mesh\\target\\release\\stillfail-station-w.exe'
$arguments = 'run --app "' + $app + '" --data "' + $data + '"'
try {
  $action = New-ScheduledTaskAction -Execute $launch -Argument $arguments -WorkingDirectory $data
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
  $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
  Start-ScheduledTask -TaskName $task
  $taskSaid = __SAY(cloud.install.win.task, task=$task)
} catch {
  $why = $_.Exception.Message
  [Console]::Error.WriteLine(__SAY(cloud.install.win.taskFailed, why=$why))
  Start-Process -FilePath $launch -ArgumentList $arguments -WindowStyle Hidden
  $taskSaid = $null
}

Say ''
Say (__SAY(cloud.install.installed))
Say ('  ' + __SAY(cloud.install.win.where.app, app=$app))
Say ('  ' + __SAY(cloud.install.where.data, data=$data))
Say ('  ' + __SAY(cloud.install.where.status))
if ($taskSaid) { Say ('  ' + $taskSaid) }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { Say ''; Say (__SAY(cloud.install.win.noGit)) }
$missing = @()
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { $missing += 'Claude Code' }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { $missing += 'Codex' }
if ($missing.Count -gt 0) {
  $list = ' ' + ($missing -join ', ')
  Say ''
  Say (__SAY(cloud.install.agents.missing, missing=$list))
  Say ('  ' + __SAY(cloud.install.win.agents.claude))
  Say ('  ' + __SAY(cloud.install.win.agents.codex))
  Say (__SAY(cloud.install.agents.signIn))
}
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
`;
