// A place entered on the bar for the first time, and entered again.

///|
test "each place comes in the same way the first time and again" {
  for place in ["files", "profiles", "stations", "usage", "connects", "archive", "vault"] {
    let t = tester("home")
    bars_picked.set(Some(([["chats", place]], 0)))
    t.frame()
    to_bar_rest(t)
    let tap_place = fn(index : Int) {
      let xs = bar_centres(390.0 - 44.0, bar.k.x, 2)
      t.tap_once(xs[index] + 22.0, 844.0 - 22.0 - 28.0)
    }
    let sample = fn() {
      t.words().filter(fn(w) { w.0 == place_label(place) })
    }
    tap_place(1)
    let at = t.time()
    let duration = @ui.move_ms(switch_slide)
    let first0 = sample()
    t.frame_at(at + duration / 4.0)
    let first_quarter = sample()
    t.frame_at(at + duration * 3.0 / 4.0)
    let first_three_quarters = sample()
    t.run_for(@ui.move_most_ms)
    tap_place(0)
    t.run_for(@ui.move_most_ms)
    to_bar_rest(t)
    tap_place(1)
    let at2 = t.time()
    let again0 = sample()
    t.frame_at(at2 + duration / 4.0)
    let again_quarter = sample()
    t.frame_at(at2 + duration * 3.0 / 4.0)
    let again_three_quarters = sample()
    assert_true(!first0.is_empty(), msg=place)
    assert_eq((first0, first_quarter, first_three_quarters), (again0, again_quarter, again_three_quarters), msg=place)
    assert_true(first0[0].5 < first_quarter[0].5 && first_quarter[0].5 < first_three_quarters[0].5, msg=place)
  }
}

///|
/// The pages' positions during a transition, including a page rising from the foot: what is drawn as wide as the window
/// (a page, whether an old view hosts it or it is made as nodes).
fn first_open_islands() -> Array[(Double, Double, Double, Double)] {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted || d.w >= 389.0 }).map(fn(d) { (d.x, d.y, d.w, d.h) })
}

///|
test "the pages of the stack come in the same way the first time and again" {
  for mode in [
    "chat", "history", "files", "archived", "drive", "reader", "player-video", "service", "newchat", "screen-full",
    "direct-preview", "direct-profile-account", "direct-kept-chat", "direct-station-archiving",
    "settings-home", "settings-appearance", "settings-fonts", "settings-me", "settings-workspace", "settings-security",
    "settings-security-pending", "settings-security-open", "settings-vault", "settings-vault-items", "settings-vault-item", "settings-stations", "settings-station",
    "settings-profiles", "settings-profile", "settings-new-profile", "settings-connects", "settings-connect",
    "settings-memories", "settings-memory", "settings-memory-doc", "settings-usage", "settings-archive", "settings-kept",
    "settings-adb-chats", "settings-decisions", "settings-completion", "settings-policy", "settings-bars", "settings-run",
    "settings-about", "settings-changelog", "settings-prices", "settings-notify", "settings-notify-off", "settings-permissions",
    "settings-archiving", "settings-shortcuts", "settings-local-station",
  ] {
    new_run()
    let src = fixture_app(if mode.has_prefix("direct-") { "settings" } else { mode })
    let page : Page = match mode {
      "direct-preview" => PreviewFile("ws1/st1", "s-c1", "work/s-c1/release.html", "release.html")
      "direct-profile-account" => Setting(@settings.Route::ProfileAccount("cc"))
      "direct-kept-chat" => Setting(@settings.Route::KeptChat("ws1/st1", 7))
      "direct-station-archiving" => Setting(@settings.Route::StationArchiving("ws1/st1"))
      _ => app.nav.top()
    }
    assert_true(page != Home, msg="\{mode}: fixture must open a page")
    while app.nav.depth() > 1 {
      app.nav.pop() |> ignore
    }
    app.nav.replace(Home)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.run_for(first_page_ms + @ui.move_most_ms)
    let tree = @ui.view_tree().unwrap()
    let start = t.time()
    tree.event(start, fn() { @sfbase.stack_open(page) })
    t.frame_at(start + @ui.move_most_ms / 4.0)
    let first = first_open_islands()
    assert_true(first.iter().any(fn(p) { p.0.abs() > 1.0 || p.1.abs() > 1.0 }), msg="\{mode}: no page moving: \{Repr(first)}")
    t.run_for(@ui.move_most_ms)
    tree.event(t.time(), fn() { app.nav.pop() |> ignore })
    t.run_for(@ui.move_most_ms)
    let again_at = t.time()
    tree.event(again_at, fn() { @sfbase.stack_open(page) })
    t.frame_at(again_at + @ui.move_most_ms / 4.0)
    assert_eq(first_open_islands(), first, msg=mode)
  }
}

///|
test "stations: the first list after a wait or an empty list appears in place" {
  for empty in [false, true] {
    new_run()
    let ready = @signals.signal(false)
    let base = fixture("settings")
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        if name == "stations" && !ready.get() {
          { value: if empty { Some([]) } else { None }, error: None, version: 0 }
        } else {
          base.topic(name, params).get().snapshot()
        }
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    let (xs, y) = bar_places_at()
    t.tap_once(xs[3], y)
    t.run_for(@ui.move_most_ms)
    t.frame()
    assert_true(app.nav.top() == Place("stations"))
    assert_true(t.find("Willow") is None)
    ready.set(true)
    t.frame()
    let first = (t.drawn_of("Willow").unwrap(), t.drawn_of("Maple").unwrap())
    assert_true(first.1.1 > first.0.1, msg="the stations overlap when their first list comes: \{Repr(first)}")
    t.run_for(@ui.row_size_ms)
    assert_eq((t.drawn_of("Willow").unwrap(), t.drawn_of("Maple").unwrap()), first)
  }
}

///|
test "stations: a station added to a list already shown opens its place" {
  new_run()
  let added = @signals.signal(false)
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let answer = base.topic(name, params).get().snapshot()
      if name == "stations" && added.get() {
        match answer.value {
          Some(Array(rows)) => {
            let rows = rows.copy()
            rows.insert(0, { "station": "ws1/new", "name": "Cedar", "online": false })
            { ..answer, value: Some(Json::array(rows)), version: answer.version + 1 }
          }
          _ => answer
        }
      } else {
        answer
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let (xs, y) = bar_places_at()
  t.tap_once(xs[3], y)
  t.run_for(@ui.move_most_ms)
  t.frame()
  let (_, before) = t.drawn_of("Willow").unwrap()
  added.set(true)
  t.frame()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, halfway) = t.drawn_of("Willow").unwrap()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, after) = t.drawn_of("Willow").unwrap()
  assert_true(before < halfway && halfway < after, msg="\{before}, \{halfway}, \{after}")
}

///|
test "shared debugging: its first read shows its sections in place" {
  new_run()
  @settings.fixture_page("settings-adb-chats") |> ignore
  let ready = @signals.signal(false)
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "adbShare" && !ready.get() {
        { value: None, error: None, version: 0 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_setting("adb:")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(t.find("打开配对窗口") is None)
  ready.set(true)
  t.frame()
  let first = t.drawn_of("打开配对窗口").unwrap()
  t.run_for(@ui.row_size_ms)
  let after = t.drawn_of("打开配对窗口").unwrap()
  assert_eq(first, after)
}

///|
/// 用量 switched to on the bar (the second of a bar of the chats and it), its name as drawn then (x, opacity) while it
/// comes in; `rebuilt` at a quarter of the way in: made anew there (the window to the tape's width and back).
fn usage_coming_in(rebuilt : Bool) -> Array[(Double, Double)] {
  let t = tester("home")
  bars_picked.set(Some(([["chats", "usage"]], 0)))
  t.frame()
  to_bar_rest(t)
  let xs = bar_centres(390.0 - 44.0, bar.k.x, 2)
  t.tap_once(xs[1] + 22.0, 844.0 - 22.0 - 28.0)
  let at = t.time()
  let duration = @ui.move_ms(switch_slide)
  let name = fn() {
    match t.words().filter(fn(w) { w.0 == place_label("usage") }) {
      [w] => (w.1, w.5)
      _ => (-1.0, -1.0)
    }
  }
  t.frame_at(at + duration / 4.0)
  let quarter = name()
  if rebuilt {
    t.resize(800.0, 844.0)
    t.frame()
    t.resize(390.0, 844.0)
  }
  t.frame_at(at + duration / 2.0)
  [quarter, name()]
}

///|
test "a place made once made anew while it comes in goes on coming in from where it was: not again from its side, not there at once" {
  let kept = usage_coming_in(false)
  let rebuilt = usage_coming_in(true)
  assert_eq(rebuilt, kept)
  assert_true(kept[0].1 < kept[1].1 && kept[1].1 < 1.0, msg="\{Repr(kept)}")
}

///|
test "a place made once, its place tapped again on the bar (no switch), then made anew: there as it was, not coming in again" {
  let t = tester("home")
  bars_picked.set(Some(([["chats", "usage"]], 0)))
  t.frame()
  to_bar_rest(t)
  let xs = bar_centres(390.0 - 44.0, bar.k.x, 2)
  t.tap_once(xs[1] + 22.0, 844.0 - 22.0 - 28.0)
  t.run_for(@ui.move_most_ms)
  to_bar_rest(t)
  t.tap_once(xs[1] + 22.0, 844.0 - 22.0 - 28.0)
  t.run_for(@ui.move_most_ms)
  t.resize(800.0, 844.0)
  t.frame()
  t.resize(390.0, 844.0)
  t.frame()
  let name = t.words().filter(fn(w) { w.0 == place_label("usage") })
  assert_true(name.length() == 1 && name[0].1 == 16.0 && name[0].5 == 1.0, msg="\{Repr(name)}")
}

// A place of the bar shows what the device holds the frame it is switched to, never its bones first: the first time
// since the app started (what it opens on asked ahead: sfbase's places_ahead) and each time after (what the core last
// said of it kept: sfbase's `lasting`), over a core that answers late and is asked anew for what was let go of.

///|
/// How late the core's first value of a topic is here (round_trip_again): longer than a place takes to come in.
let place_core_late_ms : Double = 600.0

///|
/// A phone signed in over a core answering `ms` late, Home shown and the core gone quiet.
fn late_phone(ms : Double) -> @ui.Tester raise {
  new_run()
  let src = { ..round_trip_again(fixture("home"), ms), reads_ahead: fn() { true } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  t.draw()
  // (the accounts, the workspaces, the workspace's, Home's, then what the places open on: one after another)
  t.run_for(ms * 8.0)
  // (all of it answered, and held while the bar is there: sfbase's places_ahead_node)
  assert_true(@sfbase.places_ahead_open())
  t
}

///|
/// Place `place` switched to: the most bones any frame draws as it comes in (the frame of the switch, the three after
/// it, the one it is in by).
fn bones_at(t : @ui.Tester, place : String) -> Int {
  go_place(t.ctx().moment(), place, [], -1)
  t.draw()
  let mut most = t.bones_drawn()
  for _ in 0..<3 {
    t.run_for(@ui.frame_period_default)
    most = @cmp.maximum(most, t.bones_drawn())
  }
  t.run_for(@ui.move_most_ms)
  @cmp.maximum(most, t.bones_drawn())
}

///|
test "a place of the bar in view shows what the device holds the first time it is switched to, and each time after" {
  let t = late_phone(place_core_late_ms)
  let bars = [["chats", "files", "profiles", "stations"], ["archive", "usage", "connects", "vault"]]
  for bar in 0..<bars.length() {
    // (the other bar brought into view: its places asked ahead in turn)
    if bar > 0 {
      @sfbase.bars_picked.set(Some((bars, bar)))
      t.draw()
      t.run_for(place_core_late_ms * 3.0)
      assert_true(@sfbase.places_ahead_open())
    }
    for round in 0..<2 {
      for place in bars[bar] {
        if place == "chats" || place == "usage" || place == "archive" {
          continue
        }
        // (Station's ways reached, asked only from its tab (bars.mbt place_reads): the first time this run, its network
        // line alone in its bones, stayed on till the core answered; after, what it said then, at once)
        let first_station = place == "stations" && round == 0
        assert_eq(bones_at(t, place), if first_station { station_net_bones } else { 0 }, msg="\{place}, time \{round + 1}")
        if first_station {
          t.run_for(place_core_late_ms * 2.0)
        }
        // (left long enough for the core to have let go of it)
        assert_eq(bones_at(t, "chats"), 0, msg="chats after \{place}")
        t.run_for(place_core_late_ms)
      }
    }
  }
}

///|
/// What Station draws in its bones when all but how each station up is reached is held (stationNet, asked only from its
/// tab: bars.mbt place_reads): the network line of each online station of the fixture's, its bars, nothing else.
let station_net_bones : Int = 16

///|
test "Station left before the core said how its stations are reached: come back to, its network line still alone in its bones (nothing said to keep), the rest as the device holds it" {
  let t = late_phone(place_core_late_ms)
  // (left at once: switched to and away within a slide, the core answering later)
  assert_eq(bones_at(t, "stations"), station_net_bones, msg="first")
  assert_eq(bones_at(t, "chats"), 0)
  t.run_for(place_core_late_ms)
  assert_eq(bones_at(t, "stations"), station_net_bones, msg="second")
}

///|
/// How long a finger is on a tab here, tapping it: less than takes the ball (bar_hold_ms).
let place_tap_ms : Double = 120.0

///|
/// How late the core answers in the test below: within a tap.
let place_core_soon_ms : Double = 40.0

///|
test "用量 and 已归档, asked only as they are shown: from the finger going down on their tab, and what they last had after" {
  let late = place_core_soon_ms
  let t = late_phone(late)
  @sfbase.bars_picked.set(Some(([["chats", "files", "profiles", "stations"], ["archive", "usage", "connects", "vault"]], 1)))
  t.draw()
  t.run_for(late * 4.0)
  assert_true(@sfbase.places_ahead_open())
  for label in ["用量", "已归档"] {
    // a finger down on the tab, up a tap later: the core has answered meanwhile
    let (x, y, w, h) = said_at(t, label).unwrap()
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.draw()
    t.run_for(place_tap_ms)
    assert_true(@sfbase.places_ahead_open(), msg=label)
    t.touch(2, x + w / 2.0, y + h / 2.0)
    t.draw()
    let mut most = t.bones_drawn()
    for _ in 0..<3 {
      t.run_for(@ui.frame_period_default)
      most = @cmp.maximum(most, t.bones_drawn())
    }
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == @sfbase.place_page(if label == "用量" { "usage" } else { "archive" }), msg=label)
    assert_eq(@cmp.maximum(most, t.bones_drawn()), 0, msg="\{label} first")
    assert_eq(bones_at(t, "connects"), 0, msg="连接 after \{label}")
    t.run_for(late * 2.0)
  }
  for place in ["usage", "archive"] {
    assert_eq(bones_at(t, place), 0, msg="\{place} again")
    assert_eq(bones_at(t, "connects"), 0, msg="连接 after \{place}")
    t.run_for(late * 2.0)
  }
}
