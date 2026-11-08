// Retained settings pages shared by the three shells. The shell owns the workspace,
// navigation lifetime, frame and bars; this package chooses the page's content.

///|
pub fn settings_node_key(route : @settings.Route) -> String? {
  match route {
    About => Some("about")
    Changelog => Some("changelog")
    Memories => Some("memories")
    Memory(address) => Some("memory/" + address)
    Archiving => Some("archiving")
    StationArchiving(st) => Some("station-archiving/" + st)
    AutoDecisions => Some("auto-decisions")
    Usage => Some("usage")
    UsagePrices(days) => Some("usage-prices/" + days.to_string())
    Shortcuts => Some("shortcuts")
    Notifications => Some("notifications")
    AutoCompletion => Some("auto-completion")
    _ => None
  }
}

///|
/// Build a route accepted by settings_node_key, with the frame's own bindings.
pub fn settings_node(
  route : @settings.Route,
  v : @view.View,
  core : @settings.Core,
  here : () -> @settings.Here,
  frame~ : () -> @sf.PageFrame,
  stint~ : () -> Int,
  active~ : () -> Bool,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  bar_actions? : ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
) -> Unit {
  match route {
    About =>
      about_node(v, core, on_back=core.pop, frame~, said?, width?)
    Changelog =>
      changelog_node(v, core, on_back=core.pop, frame~, said?, width?)
    Memories =>
      memories_node(v, core, here, on_back=core.pop, frame~, said?, width?)
    Memory(address) =>
      memory_node(v, core, here, address, on_back=core.pop, frame~, said?, width?, tips?)
    Archiving =>
      archiving_node(v, core, here, on_back=core.pop, frame~, said?, width?, stint~)
    StationArchiving(st) =>
      station_archiving_node(v, core, here, st, on_back=core.pop, frame~, said?, width?)
    AutoDecisions =>
      decisions_node(v, core, here, on_back=core.pop, frame~, said?, width?, tips?)
    Usage =>
      usage_node(v, core, here, on_back=core.pop, frame~, said?, width?, tips?, bar_actions?)
    UsagePrices(days) =>
      usage_prices_node(v, core, here, days, on_back=core.pop, frame~, said?, width?)
    Shortcuts =>
      shortcuts_node(v, core, on_back=core.pop, frame~, said?, width?, active~)
    Notifications =>
      notify_node(v, core, here, on_back=core.pop, frame~, said?, width?, stint~)
    AutoCompletion =>
      completion_node(v, core, here, on_back=core.pop, frame~, said?, width?, tips?, bar_actions?)
    _ => ()
  }
}
