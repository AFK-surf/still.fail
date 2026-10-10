# still.fail's command line on Windows (bin/stillfail is Unix's; stillfail.cmd beside this runs it), from a clone or from
# an installed release (~\.stillfail\app, see cloud/src/install.ts's install.ps1):
#   stillfail start [--port N]                    runs the station in this window (the installed one runs at logon)
#   stillfail status                              where the station is: its workspace and cloud, whether it is online
#   stillfail update [--beta|--stable]            updates this station to its cloud's latest release, on its channel
#   stillfail station enroll <cloud-origin> <token> [--provider comma]
#   stillfail station id
# The data is in $env:STILLFAIL_DATA (else $env:EMBER_DATA), default ~\.stillfail.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$data = if ($env:STILLFAIL_DATA) { $env:STILLFAIL_DATA } elseif ($env:EMBER_DATA) { $env:EMBER_DATA } else { Join-Path $env:USERPROFILE '.stillfail' }
$station = if ($env:STILLFAIL_STATION_BIN) { $env:STILLFAIL_STATION_BIN } else { Join-Path $here 'mesh\target\release\stillfail-station.exe' }
$usage = 'usage: stillfail start [--port N] | stillfail status | stillfail update [--beta|--stable] | stillfail station enroll <cloud-origin> <token> [--provider comma] | stillfail station id'
$a = @($args)

function Run([string[]] $more) {
  & $station @more
  exit $LASTEXITCODE
}

switch ("$($a[0]) $($a[1])".Trim()) {
  { $a[0] -eq 'start' } { Run (@('run', '--app', $here, '--data', $data) + $a[1..($a.Count)]) }
  { $a[0] -eq 'status' -or $_ -eq 'station status' } { Run @('status', '--data', $data) }
  'station id' { Run @('id', '--data', $data) }
  { $_ -like 'station enroll*' } { Run (@('enroll') + $a[2..($a.Count)] + @('--data', $data)) }
  { $a[0] -eq 'update' } {
    # From the cloud the station is in (its installer, without a token, updates).
    $cloud = Join-Path $data 'mesh\cloud.json'
    $said = try { Get-Content $cloud -Raw | ConvertFrom-Json } catch { $null }
    if (-not $said -or -not $said.origin) { [Console]::Error.WriteLine('这台 station 还没有加入 workspace，无从更新'); exit 1 }
    $origin = $said.origin
    # Comma keeps its station releases and installer under /stations.
    if ($said.provider -eq 'comma') { $origin = "$origin/stations" }
    $asked = switch ($a[1]) { '--beta' { @('beta') } '--stable' { @('stable') } $null { @() } default { [Console]::Error.WriteLine('usage: stillfail update [--beta|--stable]'); exit 2 } }
    $channel = (& $station channel @asked --app $here --data $data 2>$null | Select-Object -Last 1)
    if ($channel -notin 'stable', 'beta') {
      if ($asked.Count -gt 0) { [Console]::Error.WriteLine("没能把 station 设成 $($asked[0]) 渠道"); exit 1 }
      $channel = 'stable'
    }
    $env:STILLFAIL_CHANNEL = $channel
    Invoke-Expression (Invoke-RestMethod "$origin/install.ps1")
    exit $LASTEXITCODE
  }
  default { [Console]::Error.WriteLine($usage); exit 2 }
}
