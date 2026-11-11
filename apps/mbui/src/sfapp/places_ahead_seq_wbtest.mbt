// What the places of the bar open on is asked of the core ahead of them at causes' moments, whatever frames are drawn
// (sfbase's places_ahead_node): what the app subscribes to and lets go of, in order, is the same at every rate frames
// are drawn at (the flows' tests run again at 60, 120, 24 and 7: this order said once, each must come out as it). What
// only the device's own data answers held from the bar's coming to its page gone from view under another; what a
// station is asked for or sampled (Station's ways reached, 用量, 已归档) only from a finger down on its tab, till the
// finger leaves it or the place switched to has come in.

///|
/// A phone signed in over a core answering `ms` late, every subscription the app's client sent its core and every
/// letting go of one said in `said` in order (`sub <topic>`, `unsub <topic>`, with the subscription's params beside it
/// where they say more than its workspace or station): the client's messages out, what a run's trace keeps.
fn ahead_phone(ms : Double, said : Array[String]) -> @ui.Tester {
  new_run()
  let names : Map[Int, String] = Map([])
  let heard = fn(h : String) {
    guard h.has_prefix("out ") else { return }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => return }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { return }
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(sub)), _) =>
        if sub.get("topic") is Some(String(topic)) {
          let rest = sub
            .to_array()
            .filter(fn(kv) { kv.0 != "topic" && kv.0 != "workspace" && kv.0 != "station" && kv.0 != "scope" })
          let name = if rest.is_empty() {
            topic
          } else {
            topic + " " + Json::object(Map::from_array(rest)).stringify()
          }
          names[n.to_int()] = name
          said.push("sub " + name)
        }
      (_, Some(True)) => said.push("unsub " + names.get(n.to_int()).unwrap_or("?"))
      _ => ()
    }
  }
  let src = { ..round_trip_again(fixture("home"), ms, heard~), reads_ahead: fn() { true } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  t.draw()
  t.run_for(ms * 8.0)
  t
}

///|
/// Of what was said, what is of the places read ahead (place_reads' topics, and what Station's ways reached are).
fn ahead_said(said : Array[String]) -> Array[String] {
  let topics = ["workspace", "stations", "stationNet", "profiles", "connects", "vaults", "usage", "archive"]
  said.filter(fn(s) {
    topics.iter().any(fn(t) { s == "sub " + t || s == "unsub " + t || s.has_prefix("sub " + t + " ") || s.has_prefix("unsub " + t + " ") })
  })
}

///|
/// Where what a screen reader would name `label` (or begins so: Station's says its stations after its name) is, shown.
fn tab_named_at(t : @ui.Tester, label : String) -> (Double, Double, Double, Double) {
  for s in t.semantics() {
    if !s.hidden && (s.label == label || s.label.has_prefix(label)) {
      return s.rect
    }
  }
  @halt.saying("nothing named \{label}")
}

///|
/// Home, then its 设置 pressed and come in, then back: what the client sent of the places read ahead, after what Home's
/// coming sent, over a core answering `ms` late.
fn home_settings_back(ms : Double) -> (Array[String], Array[String], Array[String]) {
  let said : Array[String] = []
  let t = ahead_phone(ms, said)
  let start = ahead_said(said)
  let (x, y, w, h) = tab_named_at(t, "设置")
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(ms * 4.0)
  let pushed = ahead_said(said)[start.length():].to_owned()
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(ms * 4.0)
  let back = ahead_said(said)[start.length() + pushed.length():].to_owned()
  (start, pushed, back)
}

///|
test "Home, then 设置 pressed and come in, then back: the bar's places held as Home came, let go of once Home is gone from view (once, as the slide is over), taken again as it comes back; the same however late the core answers, at every rate" {
  let soon = home_settings_back(place_core_soon_ms)
  let late = home_settings_back(place_core_late_ms)
  assert_eq(
    soon,
    (
      // (Home's bar: 文件's, Profile's, Station's, the stations' rows asked once for both; nothing a station is asked
      // for or sampled)
      ["sub workspace", "sub stations", "sub profiles"],
      // (设置's own; what the bar held 设置 reads as well, none let go of)
      ["sub connects {\"mine\":false}", "sub vaults"],
      // (the bar back with Home, then 设置's gone)
      ["unsub vaults", "unsub connects {\"mine\":false}"],
    ),
  )
  assert_eq(late, soon)
  assert_eq(@sfbase.places_ahead_in_build(), 0)
}

///|
test "Home under 设置, then a page pushed over 设置 (安全) and back off it: nothing of the bar's places subscribed or let go of meanwhile (a slide not over Home is no cause of the bar's); then back to Home: nothing asked again at that back (设置 held all the bar holds)" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_soon_ms, said)
  let (x, y, w, h) = tab_named_at(t, "设置")
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  let under = ahead_said(said).length()
  t.tap_text("安全")
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  let over = ahead_said(said)[under:].to_owned()
  let before_back = said.length()
  t.back()
  // (at the back itself, Home beside the page going: no frame of the slide run yet)
  let at_back = ahead_said(said[before_back:].to_owned())
  t.run_for(@ui.move_most_ms)
  // (设置 reads all the bar's places read, the stations' rows one ask for all: nothing to subscribe again at the back)
  assert_eq((over, at_back), ([], []))
}

///|
test "Home kept in view a while: nothing a station is asked for or sampled read ahead of its places (stationNet, usage, archive), however late the core answers" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_late_ms, said)
  t.run_for(place_core_late_ms * 16.0)
  let asked = said.filter(fn(s) { s.contains("stationNet") || s.contains("usage") || s.contains("archive") })
  assert_eq(asked, [])
}

///|
/// A finger down on the tab of the bar's place labelled `label`, and up `ms` later where it went down (`off`: moved
/// off the bar first, the tap called off).
fn tab_press(t : @ui.Tester, label : String, ms : Double, off : Bool) -> Unit {
  let (x, y, w, h) = tab_named_at(t, label)
  let (px, py) = (x + w / 2.0, y + h / 2.0)
  t.touch(0, px, py)
  t.draw()
  t.run_for(ms)
  if off {
    t.touch(1, px, py - 300.0)
    t.draw()
    t.touch(2, px, py - 300.0)
  } else {
    t.touch(2, px, py)
  }
  t.draw()
}

///|
test "Station's tab pressed and let go there: Station's ways reached subscribed from the finger going down, and its page, first built before the press lets go, holding them on: nothing let go of or asked again" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_soon_ms, said)
  let before = said.length()
  tab_press(t, "Station", place_tap_ms, false)
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  assert_true(app.nav.top() == @sfbase.place_page("stations"))
  assert_eq(ahead_said(said[before:].to_owned()), ["sub stationNet"])
  assert_eq(@sfbase.places_ahead_in_build(), 0)
}

///|
test "Station's tab pressed, the finger moved off the bar: Station's ways reached subscribed from the finger going down, let go of as it is called off, nothing switched to" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_soon_ms, said)
  let before = said.length()
  let top = app.nav.top()
  tab_press(t, "Station", place_tap_ms, true)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == top)
  assert_eq(ahead_said(said[before:].to_owned()), ["sub stationNet", "unsub stationNet"])
}

///|
test "用量's tab pressed, the finger moved off the bar: 用量 read from the finger going down, let go of as it is called off, nothing switched to" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_soon_ms, said)
  @sfbase.bars_picked.set(Some(([["chats", "files", "profiles", "stations"], ["archive", "usage", "connects", "vault"]], 1)))
  t.draw()
  t.run_for(place_core_soon_ms * 4.0)
  let before = said.length()
  let top = app.nav.top()
  tab_press(t, "用量", place_tap_ms, true)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == top)
  assert_eq(ahead_said(said[before:].to_owned()), ["sub usage {\"days\":7}", "unsub usage {\"days\":7}"])
}

///|
test "the other bar brought into view once: its places' own subscribed, what only the first held let go of, and what both read (the stations) neither let go of nor asked again" {
  let said : Array[String] = []
  let t = ahead_phone(place_core_soon_ms, said)
  let before = said.length()
  @sfbase.bars_picked.set(Some(([["chats", "files", "profiles", "stations"], ["archive", "usage", "connects", "vault"]], 1)))
  t.draw()
  t.run_for(place_core_soon_ms * 4.0)
  let now = ahead_said(said[before:].to_owned())
  assert_false(now.contains("unsub stations") || now.contains("sub stations"), msg="\{Repr(now)}")
  assert_eq(now, ["sub connects {\"mine\":false}", "sub vaults", "unsub workspace", "unsub profiles"])
}
