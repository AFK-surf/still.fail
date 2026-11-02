// A place entered on the bar for the first time, and entered again.

///|
test "each place comes in the same way the first time and again" {
  for place in ["files", "profiles", "stations", "usage", "connects", "archive"] {
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
/// The hosted page islands' positions during a transition, including a page rising from the foot.
fn first_open_islands() -> Array[(Double, Double, Double, Double)] {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.y, d.w, d.h) })
}

///|
test "the pages of the stack come in the same way the first time and again" {
  for mode in [
    "chat", "history", "files", "archived", "drive", "reader", "player-video", "service", "newchat", "screen-full",
    "direct-preview", "direct-words", "direct-profile-account", "direct-kept-chat", "direct-station-archiving",
    "settings-home", "settings-appearance", "settings-fonts", "settings-me", "settings-workspace", "settings-security",
    "settings-security-open", "settings-vault", "settings-vault-items", "settings-vault-item", "settings-stations", "settings-station",
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
      "direct-words" => Words("完整内容", "一段短的粘贴文字，来自剪贴板 082947")
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
    assert_true(first.iter().any(fn(p) { p.0.abs() > 1.0 || p.1.abs() > 1.0 }), msg="\{mode}: no page moving: \{first}")
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
      topic: fn(name, params) {
        if name == "stations" && !ready.get() {
          { value: if empty { Some([]) } else { None }, error: None, version: 0 }
        } else {
          (base.topic)(name, params)
        }
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    let (xs, y) = bar_places_at()
    t.tap_once(xs[3], y)
    t.run_for(@ui.move_most_ms)
    t.frame()
    assert_true(app.nav.top() == Place("stations"))
    assert_true(t.find("Studio") is None)
    ready.set(true)
    t.frame()
    let first = (t.drawn_of("Studio").unwrap(), t.drawn_of("MBA").unwrap())
    assert_true(first.1.1 > first.0.1, msg="the stations overlap when their first list comes: \{first}")
    t.run_for(@ui.row_size_ms)
    assert_eq((t.drawn_of("Studio").unwrap(), t.drawn_of("MBA").unwrap()), first)
  }
}

///|
test "stations: a station added to a list already shown opens its place" {
  new_run()
  let added = @signals.signal(false)
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let answer = (base.topic)(name, params)
      if name == "stations" && added.get() {
        match answer.value {
          Some(Array(rows)) => {
            let rows = rows.copy()
            rows.insert(0, { "station": "ws1/new", "name": "Mini1", "online": false })
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
  let (_, before) = t.drawn_of("Studio").unwrap()
  added.set(true)
  t.frame()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, halfway) = t.drawn_of("Studio").unwrap()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, after) = t.drawn_of("Studio").unwrap()
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
    topic: fn(name, params) {
      if name == "adbShare" && !ready.get() {
        { value: None, error: None, version: 0 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_setting("adb:")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(t.find("共享给的 station") is None)
  ready.set(true)
  t.frame()
  let first = t.drawn_of("共享给的 station").unwrap()
  t.run_for(@ui.row_size_ms)
  let after = t.drawn_of("共享给的 station").unwrap()
  assert_eq(first, after)
}
