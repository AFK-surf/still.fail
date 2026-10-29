// Running a Windows station as the machine's administrator (docs/station-ts-native.md, "以管理员运行"), switched on and
// off from its page rather than only by `install.ps1 -Admin`. The station is never stopped before the change can take:
// - Windows asks (UAC) in a PowerShell of its own, which the station ends after ASK_MS: a prompt nobody can answer (on
//   the secure desktop, which no remote screen shows) leaves the station as it was, said `unanswered`; one refused,
//   `declined`. A station already elevated asks nothing (going back to Limited, say).
// - Elevated, run/elevation-apply.ps1 sets the logon task's RunLevel and windows.json's `admin` (what install.ps1 and
//   the update task keep), then starts a task of its own ("<task> elevation", elevated, nobody's child here), which
//   restarts the station as its task now runs it: drained first (as an update does), stopped, started.
// - That task waits for the new start (run/station.json, written once its Node serves). None in RESTART_S: the task's
//   RunLevel and windows.json put back and the station started as before, said `notStarted`.
// What is under way or how the last change failed is in run/elevation.json, which outlives the restart.
import { type ChildProcess, execFile, spawn } from "node:child_process";
import { copyFileSync, existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

/// How long Windows' prompt is waited for before the change is given up.
export const ASK_MS = 120_000;
/// How long the restarted station has to say its start before its task is put back.
const RESTART_S = 180;
/// How long an elevated change has to say it restarts the station (or why not) once its prompt is answered.
const APPLY_MS = 60_000;

export type Failure = "declined" | "unanswered" | "notStarted" | "error";

/// run/elevation.json: a change under way (`step`), or how the last one failed (`failed`), both for `want`.
export type Kept = { want: boolean; at: number; step?: "asking" | "applying" | "restarting"; failed?: Failure; message?: string };

/// The overview's `elevation` (Windows only): the setting, whether this process runs elevated, whether its user can be
/// (in the Administrators group), the change under way or how the last one failed, and whether the viewer may change it.
export type ElevationView = {
  on: boolean;
  elevated: boolean;
  canElevate: boolean;
  step?: Kept["step"];
  want?: boolean;
  failed?: Failure;
  message?: string;
  manage: boolean;
};

/// What the station is (`probe`: elevated, and its user an administrator) and does on Windows; a test's otherwise.
export type ElevationDeps = {
  data: string;
  app: string;
  now: () => number;
  changed: () => void;
  probe?: () => Promise<{ elevated: boolean; admin: boolean }>;
  /// Runs `script` (PowerShell) apart: hidden, its exit code when it ends.
  run?: (script: string) => ChildProcess;
};

export class ChangeRefused extends Error {
  readonly key: "busy" | "notAdmin" | "notInstalled";
  constructor(key: "busy" | "notAdmin" | "notInstalled") {
    super(key);
    this.key = key;
  }
}

export class Elevation {
  #probed: { elevated: boolean; admin: boolean } | null = null;
  #asking: ChildProcess | null = null;
  #timer: ReturnType<typeof setTimeout> | null = null;
  readonly #d: ElevationDeps;

  constructor(d: ElevationDeps) {
    this.#d = d;
  }

  get #run() {
    return join(this.#d.data, "run");
  }

  /// Looks at how it runs, once; and what a change before the restart left (one that said it restarts and now runs as
  /// it wanted is done; one under way in a process gone is over).
  async start(): Promise<void> {
    this.#probed = await (this.#d.probe ?? probe)().catch(() => ({ elevated: false, admin: false }));
    const kept = this.kept();
    if (kept?.step !== undefined) {
      if (kept.step === "restarting" && kept.want !== this.#probed.elevated) this.#keep({ want: kept.want, at: this.#d.now(), failed: "notStarted" });
      else if (kept.step !== "restarting" || kept.want === this.#probed.elevated) this.#clear();
    }
    this.#d.changed();
  }

  stop(): void {
    if (this.#timer !== null) clearTimeout(this.#timer);
    this.#asking?.kill();
  }

  kept(): Kept | null {
    try {
      const k = JSON.parse(readFileSync(join(this.#run, "elevation.json"), "utf8").replace(/^﻿/, ""));
      return typeof k?.want === "boolean" ? k : null;
    } catch {
      return null;
    }
  }

  #keep(k: Kept) {
    writeFileSync(join(this.#run, "elevation.json"), JSON.stringify(k));
  }

  #clear() {
    rmSync(join(this.#run, "elevation.json"), { force: true });
  }

  /// windows.json's `admin`: what its logon task is registered with, by install.ps1 or a change from here.
  on(): boolean {
    try {
      return JSON.parse(readFileSync(join(this.#d.data, "windows.json"), "utf8").replace(/^﻿/, ""))?.admin === true;
    } catch {
      return false;
    }
  }

  view(manage: boolean): ElevationView {
    const p = this.#probed ?? { elevated: false, admin: false };
    const k = this.kept();
    return {
      on: this.on(),
      elevated: p.elevated,
      canElevate: p.elevated || p.admin,
      ...(k?.step !== undefined ? { step: k.step, want: k.want } : {}),
      ...(k?.failed !== undefined ? { failed: k.failed, want: k.want, ...(k.message ? { message: k.message } : {}) } : {}),
      manage,
    };
  }

  /// Switched to `on`: asked of Windows, applied elevated, the station restarted as its task then runs it (see above).
  /// Answered as soon as it is asked; the overview says how it goes.
  change(on: boolean): void {
    const p = this.#probed ?? { elevated: false, admin: false };
    if (this.kept()?.step !== undefined) throw new ChangeRefused("busy");
    if (!p.elevated && !p.admin) throw new ChangeRefused("notAdmin");
    const hidden = join(this.#d.app, "mesh", "target", "release", "stillfail-station-w.exe");
    if (!existsSync(hidden)) throw new ChangeRefused("notInstalled");
    const now = this.#d.now();
    const deadline = now + ASK_MS;
    const kept = readWindowsJson(this.#d.data);
    const task = typeof kept.task === "string" && kept.task !== "" ? kept.task : "still.fail station";
    // Copied out of <app>: what runs from there is stopped as the station is.
    const runner = join(this.#run, "stillfail-elevation-w.exe");
    copyFileSync(hidden, runner);
    writeFileSync(join(this.#run, "elevation-restart.ps1"), restartScript({ run: this.#run, data: this.#d.data, app: this.#d.app, task, on }));
    writeFileSync(join(this.#run, "elevation-apply.ps1"), applyScript({ run: this.#run, data: this.#d.data, task, on, deadline, restart: on !== p.elevated, runner }));
    this.#keep({ want: on, at: now, step: "asking" });
    this.#d.changed();
    const child = (this.#d.run ?? runHidden)(askScript(join(this.#run, "elevation-apply.ps1"), !p.elevated));
    this.#asking = child;
    const over = (failed: Failure | null) => {
      if (this.#timer !== null) clearTimeout(this.#timer);
      this.#timer = null;
      this.#asking = null;
      const k = this.kept();
      // Said by the elevated side meanwhile (applying, restarting, failed): its, not this.
      if (failed !== null && k?.step === "asking") this.#keep({ want: on, at: this.#d.now(), failed });
      this.#d.changed();
    };
    this.#timer = setTimeout(() => {
      child.kill();
      over("unanswered");
    }, ASK_MS);
    child.on("error", () => over("error"));
    child.on("exit", (code) => {
      if (this.#asking !== child) return;
      if (code === 4) return over("declined");
      if (code !== 0) return over("error");
      // Answered: the elevated side says how it goes; not heard from at all, the change is over.
      if (this.#timer !== null) clearTimeout(this.#timer);
      this.#asking = null;
      this.#d.changed();
      const until = this.#d.now() + APPLY_MS;
      const look = () => {
        const k = this.kept();
        this.#d.changed();
        if (k?.step === "asking" || k?.step === "applying") {
          if (this.#d.now() < until) this.#timer = setTimeout(look, 1000);
          else this.#keep({ want: on, at: this.#d.now(), failed: "error" });
        } else this.#timer = null;
      };
      this.#timer = setTimeout(look, 1000);
    });
  }
}

function readWindowsJson(data: string): Record<string, unknown> {
  try {
    const j = JSON.parse(readFileSync(join(data, "windows.json"), "utf8").replace(/^﻿/, ""));
    return j !== null && typeof j === "object" ? j : {};
  } catch {
    return {};
  }
}

/// A PowerShell string of `s`.
const q = (s: string) => `'${s.replaceAll("'", "''")}'`;

const run = promisify(execFile);

/// Whether this process runs elevated, and whether its user is an administrator (the Administrators group in its token,
/// deny-only while not elevated: whoami says so, where .NET leaves it out).
async function probe(): Promise<{ elevated: boolean; admin: boolean }> {
  const script = [
    "$id = [Security.Principal.WindowsIdentity]::GetCurrent()",
    "$e = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
    "$a = [bool](whoami /groups /fo csv | Select-String -SimpleMatch 'S-1-5-32-544')",
    "Write-Output ([string]$e + ' ' + [string]$a)",
  ].join("\r\n");
  const { stdout } = await run("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")], { windowsHide: true });
  const [e, a] = stdout.trim().split(/\s+/);
  return { elevated: e === "True", admin: a === "True" };
}

function runHidden(script: string): ChildProcess {
  return spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")], { stdio: "ignore", windowsHide: true });
}

/// The station's own PowerShell: run/elevation-apply.ps1 started elevated (`elevate`: through Windows' prompt, which
/// waits for its answer), exiting 0 once it is started, 4 when the prompt was refused, 5 when it could not be started.
export function askScript(apply: string, elevate: boolean): string {
  const args = `-ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ${q(`"${apply}"`)}`;
  return [
    "$ps = (Get-Process -Id $PID).Path",
    "try {",
    `  Start-Process $ps ${args} -WindowStyle Hidden${elevate ? " -Verb RunAs" : ""} -ErrorAction Stop | Out-Null`,
    "  exit 0",
    "} catch {",
    // ERROR_CANCELLED: the prompt's No.
    "  $e = $_.Exception; while ($e -and -not ($e -is [ComponentModel.Win32Exception])) { $e = $e.InnerException }",
    "  if ($e -and $e.NativeErrorCode -eq 1223) { exit 4 }",
    "  exit 5",
    "}",
  ].join("\r\n");
}

/// PowerShell's lines writing run/elevation.json (`Note @{…}`) and setting windows.json's `admin` (`Keep $true`).
function notes(run: string, data: string, on: boolean): string[] {
  return [
    `$state = ${q(join(run, "elevation.json"))}`,
    `$windowsJson = ${q(join(data, "windows.json"))}`,
    "function Note([hashtable]$s) {",
    `  $s.want = $${on}`,
    "  $s.at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()",
    "  [IO.File]::WriteAllText($state, ($s | ConvertTo-Json -Compress))",
    "}",
    "function Keep([bool]$admin) {",
    "  $kept = [ordered]@{}",
    "  try { (Get-Content -Raw -LiteralPath $windowsJson | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $kept[$_.Name] = $_.Value } } catch {}",
    "  if ($admin) { $kept.admin = $true } else { $kept.Remove('admin') }",
    "  if ($kept.Count -gt 0) { $kept | ConvertTo-Json | Set-Content -LiteralPath $windowsJson -Encoding UTF8 }",
    "  else { Remove-Item -LiteralPath $windowsJson -ErrorAction SilentlyContinue }",
    "}",
    "function Level([string]$task, [string]$level) {",
    "  $t = Get-ScheduledTask -TaskName $task -ErrorAction Stop",
    "  Set-ScheduledTask -TaskName $task -Principal (New-ScheduledTaskPrincipal -UserId $t.Principal.UserId -LogonType Interactive -RunLevel $level) -ErrorAction Stop | Out-Null",
    "}",
  ];
}

/// run/elevation-apply.ps1, run elevated: nothing once `deadline` is past (the station gave the prompt up); else the
/// logon task's RunLevel and windows.json set, and (`restart`: the station does not run so now) the restart's task
/// registered and started. A failure puts both back and says why.
export function applyScript(o: { run: string; data: string; task: string; on: boolean; deadline: number; restart: boolean; runner: string }): string {
  const level = o.on ? "Highest" : "Limited";
  const own = `${o.task} elevation`;
  return String.fromCharCode(0xfeff) + `${[
    "$ErrorActionPreference = 'Stop'",
    ...notes(o.run, o.data, o.on),
    `if ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -gt ${o.deadline}) { exit 3 }`,
    "Note @{ step = 'applying' }",
    "$was = $null",
    "try {",
    `  $was = [string](Get-ScheduledTask -TaskName ${q(o.task)}).Principal.RunLevel`,
    `  Level ${q(o.task)} '${level}'`,
    `  Keep $${o.on}`,
    ...(o.restart
      ? [
          "  $ps = (Get-Process -Id $PID).Path",
          `  $action = New-ScheduledTaskAction -Execute ${q(o.runner)} -Argument ('--run "' + $ps + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ${q(join(o.run, "elevation-restart.ps1"))} + '"') -WorkingDirectory ${q(o.run)}`,
          "  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew",
          "  $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest",
          `  Register-ScheduledTask -TaskName ${q(own)} -Action $action -Settings $settings -Principal $principal -Force | Out-Null`,
          "  Note @{ step = 'restarting' }",
          `  Start-ScheduledTask -TaskName ${q(own)}`,
        ]
      : ["  Remove-Item -LiteralPath $state -ErrorAction SilentlyContinue"]),
    "} catch {",
    "  $why = $_.Exception.Message",
    `  if ($was) { try { Level ${q(o.task)} $was } catch {}; Keep ($was -eq 'Highest') }`,
    "  Note @{ failed = 'error'; message = $why }",
    "  exit 1",
    "}",
  ].join("\r\n")}\r\n`;
}

/// run/elevation-restart.ps1, run by its own elevated task: the station drained (at most 10 minutes, as an update),
/// stopped and started by its task; no new start said in RESTART_S, the task's RunLevel and windows.json put back and
/// it started again. Its task removed at the end.
export function restartScript(o: { run: string; data: string; app: string; task: string; on: boolean }): string {
  const back = o.on ? "Limited" : "Highest";
  return String.fromCharCode(0xfeff) + `${[
    "$ErrorActionPreference = 'Continue'",
    ...notes(o.run, o.data, o.on),
    `$run = ${q(o.run)}`,
    `$app = ${q(o.app)}`,
    `$task = ${q(o.task)}`,
    "function Said { try { Get-Content (Join-Path $run 'station.json') -Raw | ConvertFrom-Json } catch { $null } }",
    "function Ask([int]$launcher, [string]$op) {",
    "  try {",
    "    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', ('stillfail-launcher-' + $launcher), [System.IO.Pipes.PipeDirection]::Out)",
    "    $pipe.Connect(5000)",
    "    $line = [Text.Encoding]::UTF8.GetBytes('{\"op\":\"' + $op + '\"}' + [char]10)",
    "    $pipe.Write($line, 0, $line.Length)",
    "    $pipe.Flush()",
    "    $pipe.Dispose()",
    "    return $true",
    "  } catch { return $false }",
    "}",
    // The launcher's and its station's processes, by <app> in their command lines (install.ps1's way).
    "$ours = { Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($app) -and $_.Name -in 'node.exe', 'stillfail-station.exe', 'stillfail-station-w.exe' } }",
    "function Restart {",
    "  $said = Said",
    "  $station = $null",
    "  if ($said -and $said.pid) {",
    "    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$said.pid) -ErrorAction SilentlyContinue",
    "    if ($p -and $p.Name -like 'stillfail-station*') { $station = $p }",
    "  }",
    "  if ($station -and $said.drain -eq 1) {",
    "    Remove-Item (Join-Path $run 'drained') -ErrorAction SilentlyContinue",
    "    if (Ask $station.ProcessId 'drain') {",
    "      $deadline = (Get-Date).AddSeconds(630)",
    "      while ((Get-Date) -lt $deadline -and -not (Test-Path (Join-Path $run 'drained')) -and (Get-Process -Id $station.ProcessId -ErrorAction SilentlyContinue)) { Start-Sleep 1 }",
    "    }",
    "  }",
    "  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue",
    "  if ($station) { Stop-Process -Id $station.ProcessId -Force -ErrorAction SilentlyContinue }",
    "  $deadline = (Get-Date).AddSeconds(30)",
    "  while ((& $ours) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }",
    "  & $ours | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
    "  $started = if ($said) { $said.startedAt } else { $null }",
    "  Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue",
    `  $deadline = (Get-Date).AddSeconds(${RESTART_S})`,
    "  while ((Get-Date) -lt $deadline) {",
    "    Start-Sleep 1",
    "    $now = Said",
    "    if ($now -and $now.startedAt -ne $started -and (Get-Process -Id $now.pid -ErrorAction SilentlyContinue)) { return $true }",
    "  }",
    "  return $false",
    "}",
    "if (-not (Restart)) {",
    `  try { Level $task '${back}' } catch {}`,
    `  Keep $${!o.on}`,
    "  Note @{ failed = 'notStarted' }",
    "  Restart | Out-Null",
    "}",
    `try { Unregister-ScheduledTask -TaskName ${q(`${o.task} elevation`)} -Confirm:$false -ErrorAction Stop } catch {}`,
  ].join("\r\n")}\r\n`;
}
