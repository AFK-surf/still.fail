# The accessibility's contract on Windows (scripts/host_contract.sh windows a11y): kitdemo's MBUI_A11YCHECK run asked
# for its widgets by UI Automation's client, as a reader asks: found by their names once the app tells them (its
# window's tree said changed: UI Automation's event, no time guessed), each said; the checkbox's state read, words put
# in the field, the button invoked; then the app's own end, which the invoke brings. Says what it found ("A11YCHECK ..."); exit 1 if one is not.
# All of it within one deadline ($Seconds from its start, well inside the job's five minutes), each step said as it
# starts with the seconds gone ("A11YCHECK at 1.2s ..."): a run that waits says where, its log kept (host_contract.sh
# bounds the client as well, for a UI Automation call that never returns).
param([int]$AppId, [int]$Seconds = 40)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase -TypeDefinition @'
using System;
using System.Threading;
using System.Windows.Automation;
public static class A11yCheck {
  public static DateTime Start = DateTime.Now;
  public static void At(string step) {
    Console.WriteLine("A11YCHECK at " + (DateTime.Now - Start).TotalSeconds.ToString("0.0") + "s " + step);
  }
  public static int Run(IntPtr hwnd, DateTime deadline) {
    At("window " + hwnd);
    var root = AutomationElement.FromHandle(hwnd);
    var changed = new AutoResetEvent(false);
    StructureChangedEventHandler told = (s, e) => changed.Set();
    Automation.AddStructureChangedEventHandler(root, TreeScope.Subtree, told);
    At("waiting for the button to be told");
    var named = new PropertyCondition(AutomationElement.NameProperty, "A11YCHECK press");
    AutomationElement button;
    while ((button = root.FindFirst(TreeScope.Descendants, named)) == null) {
      var left = deadline - DateTime.Now;
      if (left <= TimeSpan.Zero || !changed.WaitOne(left)) { Console.WriteLine("A11YCHECK no button told"); return 1; }
    }
    At("reading the tree");
    foreach (AutomationElement e in root.FindAll(TreeScope.Descendants, Condition.TrueCondition))
      Console.WriteLine("A11YCHECK node " + e.Current.ControlType.ProgrammaticName + " " + e.Current.Name);
    Console.WriteLine("A11YCHECK button " + button.Current.ControlType.ProgrammaticName);
    var check = root.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, "A11YCHECK check"));
    if (check == null) { Console.WriteLine("A11YCHECK no checkbox"); return 1; }
    var toggle = (TogglePattern)check.GetCurrentPattern(TogglePattern.Pattern);
    Console.WriteLine("A11YCHECK check " + check.Current.ControlType.ProgrammaticName + " " + toggle.Current.ToggleState);
    var field = root.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, "A11YCHECK field"));
    if (field == null) { Console.WriteLine("A11YCHECK no field"); return 1; }
    var value = (ValuePattern)field.GetCurrentPattern(ValuePattern.Pattern);
    Console.WriteLine("A11YCHECK field " + field.Current.ControlType.ProgrammaticName + " read-only " + value.Current.IsReadOnly);
    At("writing in the field");
    value.SetValue("written by a reader");
    At("invoking the button");
    ((InvokePattern)button.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    Console.WriteLine("A11YCHECK invoked");
    return 0;
  }
}
'@
$deadline = [A11yCheck]::Start.AddSeconds($Seconds)
function Left { [int][Math]::Max(0, ($deadline - [DateTime]::Now).TotalMilliseconds) }
[A11yCheck]::At("waiting for app $AppId to be idle")
$p = Get-Process -Id $AppId
if (-not $p.WaitForInputIdle((Left))) { [A11yCheck]::At("app not idle by the deadline") }
$p.Refresh()
$code = [A11yCheck]::Run($p.MainWindowHandle, $deadline)
[A11yCheck]::At("waiting for the app's end")
if (-not $p.WaitForExit((Left))) { "A11YCHECK the app went on"; Stop-Process -Id $AppId -Force; $code = 1 }
[A11yCheck]::At("done, $code")
exit $code
