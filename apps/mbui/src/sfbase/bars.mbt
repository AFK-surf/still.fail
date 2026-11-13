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
  (src.call)("prefs.set", Json::object({ "barsBy": Json::object(by) }), answer_unread)
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
/// 文件's stations with their drives, Station's, Profile's, 连接's, 密钥's: what only the device's own data answers (the
/// core's rule 4: no request of a station for it). 用量's and 已归档's, and how each station up is reached (Station's),
/// only once a finger is on their tab (`shown`): theirs a station is asked for, or sampled, as they are shown (the
/// core's rules 2 and 4), so never before.
fn place_reads(src : Source, ws : String, scope : String, place : String, shown : Bool) -> Array[(String, Map[String, Json])] {
  let of = Json::string(ws)
  // (the stations' rows, as every list asks them: one subscription for every place that opens on them)
  let stations = stations_asked(ws)
  match place {
    "files" => [("workspace", { "workspace": of }), ("stations", stations)]
    "stations" => {
      let reads : Array[(String, Map[String, Json])] = [("stations", stations)]
      // (each station up as it is reached: sampled while shown, the core's rule 2, so only with a finger on the tab)
      if shown && hold(src, scope, "stations", stations).get().value is Some(Array(all)) {
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
    // (as their pages ask them with nothing chosen in them: sfpages usage_ask's seven days, the archive's first page)
    "usage" if shown => [("usage", { "scope": of, "days": Json::number(7.0) })]
    "archive" if shown => [("archive", { "scope": of, "limit": Json::number(60.0) })]
    _ => []
  }
}

///|
/// Places read ahead: which (their workspace and names: "" none), under what name they are held (`hold`'s scope, ""
/// none).
priv struct Ahead {
  mut of : String
  mut scope : String
}

///|
/// Those of the bar in view, and the one a finger went down on.
// kept across runs: put back as a run begins (ahead_reset)
let ahead_bar : Ahead = { of: "", scope: "" }

///|
// kept across runs: put back as a run begins (ahead_reset)
let ahead_press : Ahead = { of: "", scope: "" }

///|
/// The place whose tab a finger went down on last ("" none, or let go of): what it opens on is asked from then, so its
/// tap, a moment later, finds it answered (as a chat's row asks for its chat as it is pressed: sfpages' chat_row_node).
// kept across runs: put back as a run begins (ahead_reset)
let place_pressed_now : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// When what the press asked is let go of (places_ahead_node): the moment the finger left the tab, or, where it switched
/// to the place, the moment that place has come in (go_place's motion over); -1 while the finger is down.
// kept across runs: put back as a run begins (ahead_reset)
let place_press_ends : @signals.Signal[Double] = @signals.signal(-1.0, same=fn(a, b) { a == b })

///|
/// A finger went down on place `place`'s tab.
pub fn place_pressed(place : String) -> Unit {
  place_press_ends.set(-1.0)
  place_pressed_now.set(place)
}

///|
/// The finger on the bar let go at `at` (lifted, moved off, called off): what its press asked let go of then, or, where
/// a place was switched to as it did (place_switched), once that place has come in.
pub fn place_press_lifted(at : Double) -> Unit {
  if place_pressed_now.untracked() != "" && place_press_ends.untracked() < at {
    place_press_ends.set(at)
  }
}

///|
/// A place switched to, as a finger on the bar did it: come in by `until` (its motion's end, go_place's), what the
/// press asked held till then, as the page it opens on is first built before.
pub fn place_switched(until : Double) -> Unit {
  if place_pressed_now.untracked() != "" && place_press_ends.untracked() < until {
    place_press_ends.set(until)
  }
}

///|
/// `places` of workspace `ws` held under `scope` (place_reads; `shown`: a finger is on that place's tab), what was
/// held before for others let go of first.
fn Ahead::hold_places(self : Ahead, src : Source, ws : String, scope : String, places : Array[String], shown : Bool) -> Unit {
  ahead_outside_build()
  let of = ws + " " + places.join(",")
  // (others now: held under a name of their own first, then what was held let go of, so what both read stays read,
  // never let go of and asked again between)
  let was = if self.of != of { self.scope } else { "" }
  if self.of != of {
    ahead_count.val += 1
    self.of = of
    self.scope = scope + "#" + ahead_count.val.to_string()
  }
  // (owned by none of what asked: what is held lives till let go of, not till the reaction that asked runs again)
  let owner = @signals.set_owner(None)
  for place in places {
    for read in place_reads(src, ws, self.scope, place, shown) {
      hold(src, self.scope, read.0, read.1) |> ignore
    }
  }
  @signals.set_owner(owner) |> ignore
  if was != "" {
    let_go(src, was)
  }
}

///|
/// What is held ahead is held and let go of at causes' moments (places_ahead_node's reactions, its timeline), never as
/// a build runs: held.mbt's let_go defers what a build going on still reads, which would keep what was read ahead past
/// its moment. Each time it was, counted (places_ahead_in_build), for the tests to hold at none.
fn ahead_outside_build() -> Unit {
  if held_building.val {
    ahead_in_build.val += 1
  }
}

///|
// kept across runs: only counted on
let ahead_in_build : Ref[Int] = Ref(0)

///|
/// How many times what is read ahead was held or let go of as a build ran (ahead_outside_build): none, ever.
pub fn places_ahead_in_build() -> Int {
  ahead_in_build.val
}

///|
/// How many sets of places have been held ahead: each its own name to be held under (Ahead::hold_places).
// kept across runs: only counted on
let ahead_count : Ref[Int] = Ref(0)

///|
/// What is held let go of.
fn Ahead::release(self : Ahead, src : Source) -> Unit {
  ahead_outside_build()
  if self.scope != "" {
    let_go(src, self.scope)
  }
  self.of = ""
  self.scope = ""
}

///|
/// What the places of the bar open on (place_reads) asked of the core ahead of them, for as long as the bar is there:
/// from the moment `bar` says it is (the workspace whose bar shows: it came in, its page came back), held till it says
/// none (its page gone from view under another, the stack at rest: Nav::root_shows), what changes of it meanwhile coming
/// as what changed, not whole again; another bar or workspace in view, its places in their place. And what a place
/// opens on that a station is asked for as it shows (用量, 已归档; Station's ways reached, sampled while shown: the
/// core's rules 2 and 4), asked as a finger goes down on its tab and held till it leaves the tab, or, where it switched
/// to it, till that place has come in (place_switched): never while the place is not to be shown. Both at their
/// causes' moments, whatever frames are drawn: the page a place opens on is first built before either lets go, so it
/// takes over what is held. What the core said is kept (`lasting`), so a place shows it at once, not its bones.
pub fn places_ahead_node(v : @view.View, src : Source, bar : () -> String?) -> Unit {
  v.reacts(
    fn() {
      guard @signals.untracked(fn() { (src.reads_ahead)() }) else { return None }
      match bar() {
        Some(ws) => {
          let (sets, cur) = bars_in(src, ws)
          Some((ws, if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }))
        }
        None => None
      }
    },
    fn(want) {
      match want {
        Some((ws, places)) => ahead_bar.hold_places(src, ws, "ahead/" + ws, places, false)
        None => ahead_bar.release(src)
      }
    },
  )
  // (the pressed place's, while the finger is on it, till it lets go)
  let off : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(
    fn() {
      guard @signals.untracked(fn() { (src.reads_ahead)() }) else { return None }
      let pressed = place_pressed_now.get()
      let ends = place_press_ends.get()
      match bar() {
        Some(ws) if pressed != "" => {
          // (Station's: each station up reached, as the stations come to be known)
          if pressed == "stations" {
            station_rows(src, ws) |> ignore
          }
          Some((ws, pressed, ends))
        }
        _ => None
      }
    },
    fn(want) {
      (off.val)()
      off.val = fn() {  }
      match want {
        Some((ws, pressed, ends)) => {
          ahead_press.hold_places(src, ws, "ahead-press/" + ws, [pressed], true)
          if ends >= 0.0 {
            off.val = v.at_moment(ends, fn() {
              ahead_press.release(src)
              place_pressed_now.set("")
            })
          }
        }
        None => ahead_press.release(src)
      }
    },
  )
}

///|
/// Whether what the places open on is held ahead of them now (places_ahead_node).
pub fn places_ahead_open() -> Bool {
  ahead_bar.scope != "" || ahead_press.scope != ""
}

///|
fn ahead_reset() -> Unit {
  for a in [ahead_bar, ahead_press] {
    a.of = ""
    a.scope = ""
  }
  place_pressed_now.set("")
  place_press_ends.set(-1.0)
}
