# The accessibility's contract on Windows (scripts/host_contract.sh windows a11y): kitdemo's MBUI_A11YCHECK run asked
# for its widgets by UI Automation's client, as a reader asks: found by their names once the app tells them (its
# window's tree said changed: UI Automation's event, no time guessed), each said; the checkbox's state read, the button
# invoked; then the app's own end, which the invoke brings. Says what it found ("A11YCHECK ..."); exit 1 if one is not.
param([int]$AppId, [int]$Seconds = 60)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase -TypeDefinition @'
using System;
using System.Threading;
using System.Windows.Automation;
public static class A11yCheck {
  public static int Run(IntPtr hwnd, int seconds) {
    var root = AutomationElement.FromHandle(hwnd);
    var changed = new AutoResetEvent(false);
    StructureChangedEventHandler told = (s, e) => changed.Set();
    Automation.AddStructureChangedEventHandler(root, TreeScope.Subtree, told);
    var deadline = DateTime.Now.AddSeconds(seconds);
    var named = new PropertyCondition(AutomationElement.NameProperty, "A11YCHECK press");
    AutomationElement button;
    while ((button = root.FindFirst(TreeScope.Descendants, named)) == null) {
      var left = deadline - DateTime.Now;
      if (left <= TimeSpan.Zero || !changed.WaitOne(left)) { Console.WriteLine("A11YCHECK no button told"); return 1; }
    }
    foreach (AutomationElement e in root.FindAll(TreeScope.Descendants, Condition.TrueCondition))
      Console.WriteLine("A11YCHECK node " + e.Current.ControlType.ProgrammaticName + " " + e.Current.Name);
    Console.WriteLine("A11YCHECK button " + button.Current.ControlType.ProgrammaticName);
    var check = root.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, "A11YCHECK check"));
    if (check == null) { Console.WriteLine("A11YCHECK no checkbox"); return 1; }
    var toggle = (TogglePattern)check.GetCurrentPattern(TogglePattern.Pattern);
    Console.WriteLine("A11YCHECK check " + check.Current.ControlType.ProgrammaticName + " " + toggle.Current.ToggleState);
    ((InvokePattern)button.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    Console.WriteLine("A11YCHECK invoked");
    return 0;
  }
}
'@
$p = Get-Process -Id $AppId
[void]$p.WaitForInputIdle($Seconds * 1000)
$p.Refresh()
$code = [A11yCheck]::Run($p.MainWindowHandle, $Seconds)
if (-not $p.WaitForExit($Seconds * 1000)) { "A11YCHECK the app went on"; Stop-Process -Id $AppId -Force; $code = 1 }
exit $code
