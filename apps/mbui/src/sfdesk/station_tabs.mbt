// Station destinations beside the current chat. The shell chooses this placement;
// menus and pages still ask to open the same Screen, Drive and Station pages.

///|
fn station_tab_key(kind : String, station : String, screen? : String) -> String {
  let parts = [Json::string(station)]
  match screen { Some(s) => parts.push(Json::string(s)); None => () }
  kind + ":" + Json::array(parts).stringify()
}

///|
fn station_tab(tab : String) -> (String, String, String)? {
  for kind in ["screen", "drive", "station"] {
    let prefix = kind + ":"
    if tab.has_prefix(prefix) {
      let value = @json.parse(tab.substring(start=prefix.length())) catch { _ => return None }
      guard value is Array(xs) else { return None }
      guard xs.length() == (if kind == "screen" { 2 } else { 1 }) else { return None }
      guard xs[0] is String(station) && station != "" else { return None }
      if kind == "screen" {
        guard xs[1] is String(screen) else { return None }
        return Some((kind, station, screen))
      }
      return Some((kind, station, ""))
    }
  }
  None
}

///|
fn station_files_scope(r : ChatRef, station : String) -> String {
  tabs_key(r) + "/" + station_tab_key("drive", station)
}

///|
pub fn station_page_beside(src : Source, r : ChatRef, p : Page) -> Bool {
  let tab = match p {
    Screen(at) => {
      let tab = station_tab_key("screen", at.station, screen=at.screen)
      panel_screen_pages[tabs_key(r) + "/" + tab] = at
      tab
    }
    Drive(at) => {
      tab_place_set(station_files_scope(r, at.station), Some(at))
      station_tab_key("drive", at.station)
    }
    Setting(Station(station)) => station_tab_key("station", station)
    _ => return false
  }
  side_change(src, r, "open", Some(tab))
  true
}

///|
fn station_tab_name(src : Source, tab : String) -> String? {
  guard station_tab(tab) is Some((kind, station, screen)) else { return None }
  if kind == "screen" {
    let card = (src.topic)("screenCard", { "station": Json::string(station), "screen": Json::string(screen) }).value
    let name = text(card, "title")
    return Some(if name == "" { @sf.t("web-pages.screen.section") } else { name })
  }
  let scope = station.split("/").next().unwrap_or("").to_string()
  let stations = (src.topic)("stations", { "scope": Json::string(scope) }).value
  let mut name = station
  match stations {
    Some(Array(xs)) => for s in xs {
      if text(Some(s), "station") == station { name = text(Some(s), "name") }
    }
    _ => ()
  }
  Some(name + " · " + @sf.t(if kind == "drive" { "web-pages.drive.title" } else { "android-chat.station.details" }))
}

///|
/// Keep the opening intent per chat: login browsers close their tab when gone.
let panel_screen_pages : Map[String, @sfbase.ScreenAt] = {}

///|
let panel_screens : Map[String, (String, String, Int)] = {}

///|
fn station_tab_pane(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, tab : String) -> Bool {
  guard station_tab(tab) is Some((kind, station, screen)) else { return false }
  let frame : PageFrame = { back: None, top: 0.0, foot: 0.0, named: false }
  match kind {
    "screen" => {
      panel_screens[tab] = (station, screen, c.frame_number())
      let at = panel_screen_pages.get(tabs_key(r) + "/" + tab).unwrap_or({ station, screen, title: "", until_gone: false })
      @sfpages.screen_page(c, src, at, frame,
        on_close=fn() { side_change(src, r, "close", Some(tab)) })
    }
    "drive" => files_tab(c, src, w.id, tabs_key(r), station, only_station=true, scope=station_files_scope(r, station))
    _ => setting_route(c, src, w, Station(station), frame) |> ignore
  }
  true
}

///|
/// Stop streams when their tab is hidden, closed or its chat left.
pub fn station_tabs_sweep(c : @ui.Ctx, src : Source) -> Unit {
  let gone : Array[String] = []
  for tab, (station, screen, frame) in panel_screens {
    if frame != c.frame_number() {
      match app.nav.top() {
        Screen(at) if at.station == station && at.screen == screen => ()
        _ => @sfpages.screen_left(src, station, screen)
      }
      gone.push(tab)
    }
  }
  for tab in gone { panel_screens.remove(tab) }
}
