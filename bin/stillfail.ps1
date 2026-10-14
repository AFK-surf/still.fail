# still.fail's command line on Windows (bin/stillfail is Unix's; stillfail.cmd beside this runs it), from a clone or from
# an installed release (~\.stillfail\app, see cloud/src/install.ts's install.ps1):
#   stillfail start [--port N]                    runs the station in this window (the installed one runs at logon)
#   stillfail status                              where the station is: its workspace and cloud, whether it is online
#   stillfail update [--beta|--stable]            updates this station to its cloud's latest release, on its channel
#   stillfail station enroll <cloud-origin> <token> [--provider comma]
#   stillfail station id
#   stillfail lock status|reset                   the workspace lock on this station (docs/workspace-lock.md)
# The data is in $env:STILLFAIL_DATA (else $env:EMBER_DATA), default ~\.stillfail.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$data = if ($env:STILLFAIL_DATA) { $env:STILLFAIL_DATA } elseif ($env:EMBER_DATA) { $env:EMBER_DATA } else { Join-Path $env:USERPROFILE '.stillfail' }
$station = if ($env:STILLFAIL_STATION_BIN) { $env:STILLFAIL_STATION_BIN } else { Join-Path $here 'mesh\target\release\stillfail-station.exe' }
$usage = 'usage: stillfail start [--port N] | stillfail status | stillfail update [--beta|--stable] | stillfail station enroll <cloud-origin> <token> [--provider comma] | stillfail station id | stillfail lock status|reset'
$a = @($args)

function Run([string[]] $more) {
  & $station @more
  exit $LASTEXITCODE
}

switch ("$($a[0]) $($a[1])".Trim()) {
  { $a[0] -eq 'start' } { Run (@('run', '--app', $here, '--data', $data) + $a[1..($a.Count)]) }
  { $a[0] -eq 'status' -or $_ -eq 'station status' } { Run @('status', '--data', $data) }
  'station id' { Run @('id', '--data', $data) }
  { $_ -eq 'lock status' -or $_ -eq 'lock reset' } { Run @('lock', $a[1], '--data', $data) }
  { $_ -like 'station enroll*' } { Run (@('enroll') + $a[2..($a.Count)] + @('--data', $data)) }
  { $a[0] -eq 'update' } {
    # The channel's latest release, verified by this release's Node (the station's `update`: its signature, newer than
    # this one) and installed by the installer this release carries, told what it must hash to
    # (docs/release-signing.md). Not the cloud's installer: whoever serves it could put anything here. Node only says
    # what to run: the installer ends what runs from the release, which it is.
    if ($a.Count -gt 2 -or ($a.Count -eq 2 -and $a[1] -notin '--beta', '--stable')) { [Console]::Error.WriteLine('usage: stillfail update [--beta|--stable]'); exit 2 }
    $node = if ($env:STILLFAIL_NODE) { $env:STILLFAIL_NODE } else { Join-Path $here 'node\node.exe' }
    $main = Join-Path $here 'station\main.js'
    if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $main)) { [Console]::Error.WriteLine("stillfail update: $here is not an installed release (no node\node.exe or station\main.js)"); exit 1 }
    $plan = & $node $main update @($a[1..($a.Count)] | Where-Object { $_ }) --app $here --data $data
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $script = $null
    foreach ($line in @($plan)) {
      $key, $value = $line -split '=', 2
      if ($key -eq 'script') { $script = $value }
      elseif ($key -in 'STILLFAIL_ORIGIN', 'STILLFAIL_CHANNEL', 'STILLFAIL_RELEASE_SHA256', 'STILLFAIL_NODE_SHA256', 'STILLFAIL_INSTALL_LANG') { Set-Item -Path "env:$key" -Value $value }
    }
    if (-not $script) { [Console]::Error.WriteLine('stillfail update: no installer to run'); exit 1 }
    $env:STILLFAIL_DATA = $data
    & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script
    exit $LASTEXITCODE
  }
  default { [Console]::Error.WriteLine($usage); exit 2 }
}
