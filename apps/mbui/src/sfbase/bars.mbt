// This device's bottom bars (the phone's frame draws them: src/sfapp bar.mbt), as the core keeps them in the prefs and
// as switched here: what the settings' 下方栏 shows and changes, and a place's icon.

///|
/// Every place a bar can hold (the core's BAR_PLACES).
// kept across runs: a table, never written
let bar_places : Array[String] = [
  "chats", "files", "stations", "profiles", "connects", "usage", "archive", "vault",
]

///|
/// The bars before the core has said (BARS_DEFAULT).
fn default_bars() -> (Array[Array[String]], Int) {
  ([["chats", "files", "profiles", "stations"], ["archive", "usage", "connects", "vault"]], 0)
}

///|
/// The bars whole, as the core keeps them (prefs.ts barsOf): each one to four known places, none twice; empty ones
/// dropped; none left, the default ones; the one in view one of them.
fn bars_of(v : Json?) -> (Array[Array[String]], Int) {
  let sets : Array[Array[String]] = []
  for s in items(v, "sets") {
    let kept : Array[String] = []
    match s {
      Array(a) =>
        for p in a {
          match p {
            String(k) if bar_places.contains(k) && !kept.contains(k) && kept.length() < 4 =>
              kept.push(k)
            _ => ()
          }
        }
      _ => ()
    }
    if kept.length() > 0 {
      sets.push(kept)
    }
  }
  if sets.length() == 0 {
    return default_bars()
  }
  let cur = number(v, "current").to_int()
  (sets, if cur < 0 { 0 } else if cur >= sets.length() { sets.length() - 1 } else { cur })
}

///|
/// Whether this window has a bottom bar: the frame of one page at a time has (Small's: sfapp's app.mbt draws it there),
/// the panes side by side of a wider screen have none, their rail holding the places. What the settings' row of the
/// bars asks (sfpages' settings_list.mbt): nothing of a bar to set where none is shown.
pub fn bars_shown(c : @ui.Ctx) -> Bool {
  @sf.layout(c.window_size().0) is Small
}

///|
/// The bars as switched here, before the prefs say it.
pub let bars_picked : @signals.Signal[(Array[Array[String]], Int)?] = @signals.signal(None)

///|
/// The bars of workspace `ws`: switched here, else its own as the prefs keep them (`barsBy`), else everyone's (`bars`).
pub fn bars_in(src : Source, ws : String) -> (Array[Array[String]], Int) {
  match bars_picked.get() {
    Some(b) => b
    None => {
      let prefs = src.topic("prefs", {}).get().value
      match field(field(prefs, "barsBy"), ws) {
        Some(Object(_)) as b => bars_of(b)
        _ =>
          match field(prefs, "bars") {
            Some(Object(_)) as b => bars_of(b)
            _ => default_bars()
          }
      }
    }
  }
}

///|
/// Another bar in view (AppState.setBars): shown at once, kept whole as the workspace's (`prefs.set {barsBy}`).
pub fn set_bars(src : Source, ws : String, sets : Array[Array[String]], cur : Int) -> Unit {
  bars_picked.set(Some((sets, cur)))
  let whole = Json::object({
    "sets": Json::array(sets.map(fn(s) { Json::array(s.map(fn(p) { Json::string(p) })) })),
    "current": Json::number(cur.to_double()),
  })
  let by : Map[String, Json] = Map([])
  by[ws] = whole
  (src.call)("prefs.set", Json::object({ "barsBy": Json::object(by) }), fn(_) {  })
}

///|
/// A place's icon (Station's is the stations' glyph of their state once read, bar_glyph).
pub fn place_icon(place : String) -> String {
  match place {
    "chats" => "chats"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    "archive" => "archive"
    "vault" => "key"
    _ => "server"
  }
}

///|
/// What place `place` opens on of the core's that the device holds (the lists `lasting` keeps), for workspace `ws`:
/// 文件's stations with their drives, Station's with how each one up is reached (once they are known), Profile's,
/// 连接's, 密钥's. 用量's and 已归档's only once a finger is on their tab (`shown`): theirs a station is asked for as
/// they are shown (the core's rule 4), so never before.
fn place_reads(src : Source, ws : String, scope : String, place : String, shown : Bool) -> Array[(String, Map[String, Json])] {
  let of = Json::string(ws)
  let stations : Map[String, Json] = { "scope": of }
  match place {
    "files" => [("workspace", { "workspace": of }), ("stations", { "scope": of, "drive": Json::boolean(true) })]
    "stations" => {
      let reads : Array[(String, Map[String, Json])] = [("stations", stations)]
      if hold(src, scope, "stations", stations).get().value is Some(Array(all)) {
        for s in all {
          if field(Some(s), "online") == Some(Json::boolean(true)) && field(Some(s), "station") is Some(String(address)) {
            reads.push(("stationNet", { "station": Json::string(address) }))
          }
        }
      }
      reads
    }
    "profiles" => [("profiles", { "scope": of })]
    "connects" => [("stations", stations), ("connects", { "scope": of, "mine": Json::boolean(false) })]
    "vault" => [("vaults", { "workspace": of })]
    // (as their pages ask them with nothing chosen in them: usage_args' seven days, the archive's first page)
    "usage" if shown => [("usage", { "scope": of, "days": Json::number(7.0) })]
    "archive" if shown => [("archive", { "scope": of, "limit": Json::number(60.0) })]
    _ => []
  }
}

///|
/// Places read ahead: which (their workspace and names: "" none yet), under what name they are held (`hold`'s scope,
/// "" none), and whether their answers are still on their way.
priv struct Ahead {
  mut of : String
  mut scope : String
  mut open : Bool
}

///|
/// Those of the bar in view, and the one a finger went down on.
// kept across runs: put back as a run begins (ahead_reset)
let ahead_bar : Ahead = { of: "", scope: "", open: false }

///|
// kept across runs: put back as a run begins (ahead_reset)
let ahead_press : Ahead = { of: "", scope: "", open: false }

///|
/// The place whose tab a finger went down on last ("" none yet): what it opens on is asked from then, so its tap, a
/// moment later, finds it answered (as a chat's row asks for its chat as it is pressed: sfpages' chat_row_node).
// kept across runs: put back as a run begins (ahead_reset)
let place_pressed_now : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// A finger went down on place `place`'s tab.
pub fn place_pressed(place : String) -> Unit {
  place_pressed_now.set(place)
}

///|
/// `places` of workspace `ws` asked ahead as `ahead` (place_reads), once for each `ws` and `places`: held under
/// `scope` until all are answered, then let go of.
fn Ahead::read(self : Ahead, src : Source, ws : String, scope : String, places : Array[String], shown : Bool) -> Unit {
  let of = ws + " " + places.join(",")
  if self.of != of {
    if self.open {
      let_go(src, self.scope)
    }
    self.of = of
    self.scope = scope
    self.open = places.length() > 0
  }
  if !self.open {
    return
  }
  let mut waits = false
  for place in places {
    for read in place_reads(src, ws, scope, place, shown) {
      let said = hold(src, scope, read.0, read.1).get()
      if said.value is None && said.error is None {
        waits = true
      }
    }
  }
  if !waits {
    let_go(src, scope)
    self.open = false
  }
}

///|
/// What the places of the bar in view open on (place_reads) asked of the core once, ahead of them, and again as another
/// bar or workspace comes into view; what a place opens on asked as a finger goes down on its tab; each let go of as
/// soon as it is answered. What the core said is kept (`lasting`), so a place shown the first time since the app
/// started shows it at once, not its bones until the core answers (slowest as the app starts, the core busy catching
/// up). Asked as a frame is built with the workspace in view, once its first page has shown.
pub fn places_ahead(src : Source, ws : String) -> Unit {
  if !(src.reads_ahead)() {
    return
  }
  let (sets, cur) = bars_in(src, ws)
  ahead_bar.read(src, ws, "ahead/" + ws, if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }, false)
  let pressed = place_pressed_now.get()
  ahead_press.read(src, ws, "ahead-press/" + ws, if pressed == "" { [] } else { [pressed] }, true)
}

///|
/// Whether what the places open on is still being read ahead (places_ahead): held till then, let go of after.
pub fn places_ahead_open() -> Bool {
  ahead_bar.open || ahead_press.open
}

///|
fn ahead_reset() -> Unit {
  for a in [ahead_bar, ahead_press] {
    a.of = ""
    a.scope = ""
    a.open = false
  }
  place_pressed_now.set("")
}
