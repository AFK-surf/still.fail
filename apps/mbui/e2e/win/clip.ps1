# The clipboard as e2e/win.sh's files_do asks: `-Files a,b` Explorer's copied files (CF_HDROP), `-Picture` a bitmap
# alone (CF_DIB, as a screenshot puts it there: no PNG beside it). Says what it put there.
param([string[]]$Files, [switch]$Picture)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if ($Files) {
  $list = New-Object System.Collections.Specialized.StringCollection
  foreach ($f in $Files) { [void]$list.Add($f) }
  [System.Windows.Forms.Clipboard]::SetFileDropList($list)
  "files: $($Files -join ', ')"
}
if ($Picture) {
  $b = New-Object System.Drawing.Bitmap 240, 160
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.Clear([System.Drawing.Color]::FromArgb(255, 91, 79, 214))
  $g.FillEllipse([System.Drawing.Brushes]::White, 80, 40, 80, 80)
  $g.Dispose()
  [System.Windows.Forms.Clipboard]::SetImage($b)
  "picture: 240x160"
}
