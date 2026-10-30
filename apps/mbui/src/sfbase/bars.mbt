// This device's bottom bars (the phone's frame draws them: src/sfapp bar.mbt), as the core keeps them in the prefs and
// as switched here: what the settings' 下方栏 shows and changes, and a place's icon.

///|
/// Every place a bar can hold (the core's BAR_PLACES).
// kept across runs: a table, never written
let bar_places : Array[String] = [
  "chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive",
]

///|
/// The bars before the core has said (BARS_DEFAULT).
fn default_bars() -> (Array[Array[String]], Int) {
  ([["chats", "files", "profiles", "stations"], ["decisions", "usage", "connects", "archive"]], 0)
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
      let prefs = (src.topic)("prefs", {}).value
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
/// A place's icon (Places.kt placeIcon; Station's is the stations' glyph of their state once read, bar_glyph).
pub fn place_icon(place : String) -> String {
  match place {
    "chats" => "chats"
    "decisions" => "zou"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    "archive" => "archive"
    _ => "server"
  }
}
