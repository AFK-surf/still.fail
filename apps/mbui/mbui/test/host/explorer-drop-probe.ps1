# Scratch experiment: a real Explorer file dragged into the actual retained-node probe on a Windows runner.
param([string]$Executable, [string]$FilePath, [string]$LogPath, [string]$ShotPath, [int]$Seconds = 60)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase, System.Drawing
Add-Type -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase, System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;

public static class ExplorerDropProbe {
  [StructLayout(LayoutKind.Sequential)] struct Point { public int x; public int y; }
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hgt, uint flags);
  [DllImport("user32.dll", SetLastError=true)] static extern bool ClientToScreen(IntPtr h, ref Point p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint process);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int obj, int child, uint thread, uint time);
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWinEventHook(uint first, uint last, IntPtr module, WinEventProc callback, uint process, uint thread, uint flags);
  [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
  [StructLayout(LayoutKind.Sequential)] struct Message { public IntPtr hwnd; public uint message; public UIntPtr wparam; public IntPtr lparam; public uint time; public Point point; public uint reserved; }
  [DllImport("user32.dll")] static extern int GetMessage(out Message message, IntPtr hwnd, uint first, uint last);
  [DllImport("user32.dll")] static extern bool PeekMessage(out Message message, IntPtr hwnd, uint first, uint last, uint remove);
  [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wparam, IntPtr lparam);
  const uint MouseDown = 0x0002, MouseUp = 0x0004, Show = 0x0040, NoZOrder = 0x0004;

  sealed class DragEvents : IDisposable {
    public readonly AutoResetEvent Capture = new AutoResetEvent(false);
    public readonly AutoResetEvent Drag = new AutoResetEvent(false);
    readonly AutoResetEvent ready = new AutoResetEvent(false);
    readonly Thread pump;
    readonly WinEventProc callback;
    uint threadId;
    IntPtr hook;
    public DragEvents() {
      callback = (h, ev, window, obj, child, thread, time) => {
        uint process;
        GetWindowThreadProcessId(window, out process);
        Console.WriteLine("EXPLORER system event 0x{0:X} window={1} process={2} thread={3}", ev, window, process, thread);
        if (ev == 0x0008) Capture.Set();
        if (ev == 0x000E) Drag.Set();
      };
      pump = new Thread(() => {
        threadId = GetCurrentThreadId();
        Message msg;
        PeekMessage(out msg, IntPtr.Zero, 0, 0, 0);
        hook = SetWinEventHook(0x0008, 0x000E, IntPtr.Zero, callback, 0, 0, 0);
        ready.Set();
        if (hook != IntPtr.Zero) {
          while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {}
          UnhookWinEvent(hook);
        }
      });
      pump.IsBackground = true;
      pump.Start();
      if (!ready.WaitOne(TimeSpan.FromSeconds(10)) || hook == IntPtr.Zero) throw new Exception("cannot install system event hook");
    }
    public void Dispose() {
      PostThreadMessage(threadId, 0x0012, UIntPtr.Zero, IntPtr.Zero);
      pump.Join();
      ready.Dispose(); Capture.Dispose(); Drag.Dispose();
    }
  }

  static string Log(string path) {
    using (var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
    using (var r = new StreamReader(f)) return r.ReadToEnd();
  }
  static void WaitLog(string path, string text, DateTime deadline) {
    using (var changed = new AutoResetEvent(false))
    using (var watcher = new FileSystemWatcher(Path.GetDirectoryName(path), Path.GetFileName(path))) {
      watcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size;
      FileSystemEventHandler told = (s, e) => changed.Set();
      watcher.Changed += told;
      watcher.EnableRaisingEvents = true;
      while (!Log(path).Contains(text)) {
        TimeSpan left = deadline - DateTime.UtcNow;
        if (left <= TimeSpan.Zero || !changed.WaitOne(left)) throw new Exception("log did not say " + text + "\n" + Log(path));
      }
    }
  }
  static void Shot(string path) {
    int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
    using (var b = new Bitmap(w, h))
    using (var g = Graphics.FromImage(b)) { g.CopyFromScreen(0, 0, 0, 0, b.Size); b.Save(path); }
  }
  public static int Run(int appId, string file, string log, string shot, int seconds) {
    DateTime deadline = DateTime.UtcNow.AddSeconds(seconds);
    AutomationElement explorer = null;
    bool held = false;
    var app = Process.GetProcessById(appId);
    try {
      SetProcessDPIAware();
      if (!app.WaitForInputIdle(seconds * 1000)) throw new Exception("probe window did not become ready");
      app.Refresh();
      IntPtr appWindow = app.MainWindowHandle;
      if (appWindow == IntPtr.Zero) throw new Exception("probe has no main window");
      int sw = GetSystemMetrics(0), sh = GetSystemMetrics(1);
      if (sw < 900 || sh < 500) throw new Exception("desktop too small: " + sw + "x" + sh);
      if (!SetWindowPos(appWindow, IntPtr.Zero, sw / 2 - 50, 15, sw / 2 + 40, sh - 45, NoZOrder | Show))
        throw new Exception("cannot place probe window");

      var desktop = AutomationElement.RootElement;
      using (var changed = new AutoResetEvent(false)) {
        StructureChangedEventHandler told = (s, e) => changed.Set();
        Automation.AddStructureChangedEventHandler(desktop, TreeScope.Subtree, told);
        try {
          Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + file + "\"") { UseShellExecute = true });
          var itemName = new PropertyCondition(AutomationElement.NameProperty, Path.GetFileName(file));
          AutomationElement item = null;
          System.Windows.Point source = new System.Windows.Point();
          while (item == null) {
            var windows = desktop.FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ClassNameProperty, "CabinetWClass"));
            foreach (AutomationElement window in windows) {
              foreach (AutomationElement candidate in window.FindAll(TreeScope.Descendants, itemName)) {
                if (candidate.TryGetClickablePoint(out source)) { explorer = window; item = candidate; break; }
              }
              if (item != null) break;
            }
            if (item != null) break;
            TimeSpan left = deadline - DateTime.UtcNow;
            if (left <= TimeSpan.Zero || !changed.WaitOne(left)) throw new Exception("Explorer did not expose the file");
          }
          IntPtr explorerWindow = new IntPtr(explorer.Current.NativeWindowHandle);
          if (!SetWindowPos(explorerWindow, IntPtr.Zero, 0, 15, sw / 2 - 55, sh - 45, NoZOrder | Show))
            throw new Exception("cannot place Explorer");
          uint explorerProcess;
          GetWindowThreadProcessId(explorerWindow, out explorerProcess);
          Console.WriteLine("EXPLORER window process={0}, probe process={1}", explorerProcess, appId);
          if (!SetForegroundWindow(explorerWindow)) throw new Exception("cannot foreground Explorer");
          item.SetFocus();
          if (!item.TryGetClickablePoint(out source)) throw new Exception("Explorer file is not visible");
          var target = new Point { x = 250, y = 150 };
          if (!ClientToScreen(appWindow, ref target)) throw new Exception("cannot locate the drop target");
          deadline = DateTime.UtcNow.AddSeconds(seconds);
          Console.WriteLine("EXPLORER file {0},{1}; target {2},{3}; screen {4}x{5}", source.X, source.Y, target.x, target.y, sw, sh);
          using (var events = new DragEvents()) {
            if (!SetCursorPos((int)source.X, (int)source.Y)) throw new Exception("cannot move to Explorer file");
            mouse_event(MouseDown, 0, 0, 0, UIntPtr.Zero);
            held = true;
            bool capture = events.Capture.WaitOne(TimeSpan.FromSeconds(10));
            Console.WriteLine("EXPLORER mouse capture={0}, left button down={1}", capture, (GetAsyncKeyState(1) & 0x8000) != 0);
            if (!capture) throw new Exception("mouse down did not produce a system capture event");
            if (!SetCursorPos((int)source.X + 30, (int)source.Y)) throw new Exception("cannot start the drag");
            bool drag = events.Drag.WaitOne(TimeSpan.FromSeconds(5));
            Console.WriteLine("EXPLORER drag-start event={0}", drag);
            if (!SetCursorPos(target.x, target.y)) throw new Exception("cannot drag to the probe");
            WaitLog(log, "HOVER folder", deadline);
          }
          Shot(shot);
          mouse_event(MouseUp, 0, 0, 0, UIntPtr.Zero);
          held = false;
          WaitLog(log, "READ folder " + Path.GetFileName(file), deadline);
          string contents = Log(log);
          int dropCount = contents.Split(new [] {"DROP folder"}, StringSplitOptions.None).Length - 1;
          int readCount = contents.Split(new [] {"READ folder " + Path.GetFileName(file)}, StringSplitOptions.None).Length - 1;
          if (dropCount != 1 || readCount != 1) throw new Exception("expected one drop and one read\n" + contents);
          Console.WriteLine("EXPLORER real drag: folder hovered, one drop, one asynchronous file read");
          return 0;
        } finally { Automation.RemoveStructureChangedEventHandler(desktop, told); }
      }
    } catch (Exception e) {
      Console.WriteLine("EXPLORER failed: " + e);
      try { Shot(shot); } catch {}
      return 1;
    } finally {
      if (held) mouse_event(MouseUp, 0, 0, 0, UIntPtr.Zero);
      if (explorer != null) try { ((WindowPattern)explorer.GetCurrentPattern(WindowPattern.Pattern)).Close(); } catch {}
      if (!app.HasExited) app.Kill();
    }
  }
}
'@
$env:MBUI_BENCH = '-1'
$env:MBUI_WIN = '560x400'
$probe = Start-Process -FilePath $Executable -PassThru -RedirectStandardOutput $LogPath -RedirectStandardError ($LogPath + '.err')
Write-Output "EXPLORER probe PID $($probe.Id), executable $Executable"
exit [ExplorerDropProbe]::Run($probe.Id, $FilePath, $LogPath, $ShotPath, $Seconds)
