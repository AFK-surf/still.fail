# The app's window, found by its class (mbui's src/host/win_life.h window_class), closed as its close button closes it,
# then looked at until it is put away: hidden (to its icon in the notification area), or minimized where there is no
# notification area. Says which, or why not (and fails), for e2e/win.sh's life_do.
param([string]$Class)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
  // (the title an IntPtr: PowerShell hands $null to a string as "", a window titled so)
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, IntPtr t);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
"@
$h = [Win]::FindWindow($Class, [IntPtr]::Zero)
if ($h -eq [IntPtr]::Zero) { "no window of class $Class"; exit 1 }
# WM_CLOSE
[void][Win]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
  if (-not [Win]::IsWindowVisible($h)) { "hidden"; exit 0 }
  if ([Win]::IsIconic($h)) { "minimized"; exit 0 }
  Start-Sleep -Milliseconds 100
}
"still shown 20 s after it was closed"
exit 1
