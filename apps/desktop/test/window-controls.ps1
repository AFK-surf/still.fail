# Called by window-controls.cjs: inspect and exercise the real child HWND without moving the user's mouse.
param([Parameter(Mandatory)] [long] $ParentWindow, [string] $Action = "inspect")
$ErrorActionPreference = "Stop"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SnapTest {
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int x, y; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr h, string key);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect rect);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref Point p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public static IntPtr Pair(int x, int y) { return (IntPtr)((y & 65535) << 16 | (x & 65535)); }
}
'@
[void] [SnapTest]::SetThreadDpiAwarenessContext([IntPtr] (-4))
$parentHandle = [IntPtr] $ParentWindow
$child = [SnapTest]::GetProp($parentHandle, "StillfailSnapTarget")
if ($child -eq [IntPtr]::Zero) { throw "no native maximize target" }
$rect = New-Object SnapTest+Rect
[void] [SnapTest]::GetWindowRect($child, [ref] $rect)
$point = New-Object SnapTest+Point
$point.x = $rect.left
$point.y = $rect.top
[void] [SnapTest]::ScreenToClient($parentHandle, [ref] $point)
$screen = [SnapTest]::Pair($rect.left + 5, $rect.top + 5)
if ($Action -eq "click" -or $Action -eq "cancel") {
  [void] [SnapTest]::SendMessage($child, 0xA1, [IntPtr] 9, $screen)
  $release = if ($Action -eq "click") { [SnapTest]::Pair(5, 5) } else { [SnapTest]::Pair(-10, -10) }
  [void] [SnapTest]::SendMessage($child, 0x200, [IntPtr] 1, $release)
  [void] [SnapTest]::SendMessage($child, 0x202, [IntPtr]::Zero, $release)
}
if ($Action -eq "hover") { [void] [SnapTest]::SendMessage($child, 0xA0, [IntPtr] 9, $screen) }
if ($Action -eq "leave") { [void] [SnapTest]::SendMessage($child, 0x2A2, [IntPtr]::Zero, [IntPtr]::Zero) }
@{ x=$point.x; y=$point.y; width=$rect.right-$rect.left; height=$rect.bottom-$rect.top;
   visible=[SnapTest]::IsWindowVisible($child); hit=[SnapTest]::SendMessage($child, 0x84, [IntPtr]::Zero, $screen).ToInt64() } | ConvertTo-Json -Compress
