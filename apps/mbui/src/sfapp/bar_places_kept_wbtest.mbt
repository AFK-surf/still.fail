// A place of the bottom bar on 小屏 switched away from is kept (its nodes put by at rest: sfbase's nav_root_kept,
// mbui's View::each `keeps`) and taken back as it is switched to again. Held here: it comes back as it was left, its
// list scrolled where it was (the owner, 2026-11-12: 「三样都记得」; 连接's 我的: bar_places_today); one left at its top with
// nothing chosen draws what a page made anew draws at the same moment, with the same data (go_place_by not `kept`: the
// page let go and made again, as every switch was till 2026-11-12), also where what it shows changed as it rested, and
// as it is switched back within its way in (place_comes_in: where the clock has it, at any rate of frames); and nothing
// of it takes input as it rests: not pressed, focused or read out, its field given no focus as a layer elsewhere closes.

///|
/// The bar the switches are made on (home_again's): 对话, 额度 (an old view's), 连接, 用量.
let kept_bar : Array[String] = ["chats", "profiles", "connects", "usage"]

///|
/// The place `place` gone to at an event now, as the bar's switch goes (go_place_by: kept or made anew).
fn kept_go(t : @ui.Tester, place : String, kept : Bool) -> Unit {
  @ui.view_tree().unwrap().event(t.time(), fn() { go_place_by(t.time(), place, [kept_bar], 0, kept) })
}

///|
/// What is drawn now: the words (each where and how opaque) and the plain rectangles.
fn kept_drawn(
  t : @ui.Tester,
) -> (Array[(String, Double, Double, Double, Double, Double)], Array[(Double, Double, Double, Double, Int64)]) {
  (t.words(), t.drawn_rects())
}

///|
/// On the workspace of real size in the phone's window (home_again_open), place `place` opened (from Home), left for 额度
/// and switched to again, each switch kept or made anew (`kept`); with `changed`, a change of the real workspace to a
/// topic the page reads taken as it rests (its first cause's messages, real_size_changed's). What is drawn `soon` ms
/// after the switch back (its way in under way) and once it is at rest; and the topic changed ("" none).
fn kept_walk(
  place : String,
  kept : Bool,
  changed : String,
  soon : Double,
) -> (
  (Array[(String, Double, Double, Double, Double, Double)], Array[(Double, Double, Double, Double, Int64)]),
  (Array[(String, Double, Double, Double, Double, Double)], Array[(Double, Double, Double, Double, Int64)]),
  String,
) {
  let (t, c, _) = home_again_open("kept \{place} \{kept}", @ui.frame_period_default)
  bars_picked.set(Some(([kept_bar], 0)))
  t.run_for(kept_switch_over_ms)
  if place != "chats" {
    kept_go(t, place, kept)
    t.run_for(kept_switch_over_ms)
  }
  kept_go(t, "profiles", kept)
  t.run_for(kept_switch_over_ms)
  let mut told = ""
  if changed != "" {
    for i, way in c.ways() {
      if way.0 == changed && told == "" {
        match c.changed(i).get(0) {
          Some((cause, messages)) => {
            for m in messages {
              c.put(i, m)
            }
            told = changed + " " + cause
          }
          None => ()
        }
      }
    }
    t.run_for(kept_few_frames_ms)
  }
  kept_go(t, place, kept)
  t.run_for(soon)
  let early = kept_drawn(t)
  t.run_for(kept_switch_over_ms)
  let late = kept_drawn(t)
  (early, late, told)
}

///|
test "bar places kept: each place taken back draws what the page made anew draws at the same moment, its way in under way and at rest" {
  // (each left at its top with nothing chosen: a page made anew is so too. What a kept place remembers, its scroll and
  // 连接's 我的, a page made anew has not: that is held by "comes back as it was left" below)
  for place in ["chats", "connects", "usage"] {
    let (k_early, k_late, _) = kept_walk(place, true, "", 60.0)
    let (n_early, n_late, _) = kept_walk(place, false, "", 60.0)
    assert_eq(k_early, n_early, msg="\{place}: 60 ms into its way in")
    assert_eq(k_late, n_late, msg="\{place}: at rest")
    // (its way in under way then: something of it drawn neither gone nor whole)
    assert_true(k_early.0.iter().any(fn(w) { w.5 > 0.0 && w.5 < 1.0 }), msg="\{place}: its way in under way at 60 ms")
  }
}

///|
test "bar places kept: a place taken back after what it shows changed as it rested draws what the page made anew draws" {
  // (left at its top with nothing chosen, as one made anew would be: what it remembers is none of what differs)
  for pt in [("chats", "chats"), ("connects", "connects"), ("usage", "usage")] {
    let (place, topic) = pt
    let (k_early, k_late, k_told) = kept_walk(place, true, topic, 60.0)
    let (n_early, n_late, n_told) = kept_walk(place, false, topic, 60.0)
    println("bar-kept \{place}: changed as it rested: \{k_told} (made anew: \{n_told})")
    assert_eq(k_told, n_told)
    assert_eq(k_early, n_early, msg="\{place} changed: 60 ms into its way in")
    assert_eq(k_late, n_late, msg="\{place} changed: at rest")
  }
}

///|
/// The first word drawn in the middle of the page (between 200 and 600 down, the bar's and the top bar's words not among
/// them) and where each drawn of the same words is: how far the page is scrolled, by its words.
fn kept_mark(t : @ui.Tester) -> (String, Array[Double]) {
  match t.words().iter().find_first(fn(w) { w.1 >= 0.0 && w.1 < 360.0 && w.2 >= 200.0 && w.2 <= 600.0 && w.0.length() > 1 }) {
    Some(m) => (m.0, kept_mark_at(t, m.0))
    None => ("", [])
  }
}

///|
/// Where each drawn of words `words` is, down the window.
fn kept_mark_at(t : @ui.Tester, words : String) -> Array[Double] {
  t.words().filter(fn(w) { w.0 == words && w.1 >= 0.0 && w.1 < 360.0 }).map(fn(w) { w.2 })
}

///|
/// Home left for 连接 `away` ms after it was switched to from 连接 (its way in under way), and switched to again `back`
/// ms after that, each switch kept or made anew: what is drawn `then` ms after the last switch.
fn kept_within(
  kept : Bool,
  away : Double,
  back : Double,
  then : Double,
) -> (Array[(String, Double, Double, Double, Double, Double)], Array[(Double, Double, Double, Double, Int64)]) {
  let (t, _, _) = home_again_open("kept within \{kept}", @ui.frame_period_default)
  bars_picked.set(Some(([kept_bar], 0)))
  t.run_for(kept_switch_over_ms)
  kept_go(t, "connects", kept)
  t.run_for(kept_switch_over_ms)
  kept_go(t, "chats", kept)
  t.run_for(away)
  kept_go(t, "connects", kept)
  t.run_for(back)
  kept_go(t, "chats", kept)
  t.run_for(then)
  kept_drawn(t)
}

///|
test "bar places kept: Home switched away from and back within its way in shows that way where the clock has it, at every rate of frames" {
  // (the rate the run's frames are drawn at is MBUI_TEST_FPS's: the same at 60, 120, 24 and 7 a second)
  let kept = kept_within(true, 50.0, 40.0, 70.0)
  let anew = kept_within(false, 50.0, 40.0, 70.0)
  assert_eq(kept, anew)
  assert_true(kept.0.iter().any(fn(w) { w.5 > 0.0 && w.5 < 1.0 }), msg="its way in under way")
}

///|
/// What a screen reader is told now (Tester::a11y_dump), and the labels of what takes the keyboard's focus as Tab goes
/// round (`tabs` presses), each once, with the node of the window's tree that had it (the first, by label).
fn kept_reachable(t : @ui.Tester, tabs : Int) -> (String, Array[String], Map[String, @view.NodeId]) {
  let focused : Array[String] = []
  let nodes : Map[String, @view.NodeId] = Map([])
  for _ in 0..<tabs {
    t.tab()
    t.run_for(kept_tab_gap_ms)
    match t.focused() {
      Some(s) =>
        if !focused.contains(s.label) {
          focused.push(s.label)
          match @ui.view_tree().unwrap().focused_now().0 {
            Some(id) => nodes[s.label] = id
            None => ()
          }
        }
      None => ()
    }
  }
  (t.a11y_dump(), focused, nodes)
}

///|
test "bar places kept: Home at rest on the shelf is not pressed, focused or read out, and its search field takes no focus back as a layer elsewhere closes" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_a11y(true)
  bars_picked.set(Some(([kept_bar], 0)))
  t.run_for(kept_switch_over_ms)
  let w = @signals.untracked(fn() { workspace_in_view(src).0.unwrap() })
  // (Home's own: its filter's label, a row's title, read out and reached by Tab)
  let (home_said, home_tabs, home_nodes) = kept_reachable(t, 12)
  let filter_label = home_tabs.iter().find_first(fn(l) { l.contains("筛选会话") })
  assert_true(filter_label is Some(_), msg="Home's filter reached by Tab: \{Repr(home_tabs)}")
  assert_true(home_said.contains("给设置页加一个深色模式开关"), msg="Home's row read out")
  // (its search field come up and typed in, then the place switched with no finger: 连接)
  t.drag(195.0, 300.0, 195.0, 420.0, steps=20)
  t.run_for(kept_glide_over_ms)
  match t.words().iter().find_first(fn(x) { x.0.contains("搜索") && x.2 > 60.0 }) {
    Some(f) => {
      t.tap(f.1 + 4.0, f.2 + 4.0)
      t.run_for(kept_switch_over_ms)
      t.type_text("abcq")
      t.run_for(kept_switch_over_ms)
    }
    None => ()
  }
  assert_eq(t.focused().map(fn(s) { s.value }), Some("abcq"))
  kept_go(t, "connects", true)
  t.run_for(kept_switch_over_ms)
  // (on 连接, Home on the shelf: none of it read out, reached by Tab or pressed where it was)
  let (said, tabs, _) = kept_reachable(t, 12)
  // (what of Home took the focus there takes none on the shelf: Tree::takes_keys, what Tab and what gives focus ask)
  for e in home_nodes {
    assert_false(@ui.view_tree().unwrap().takes_keys(e.1), msg="\{e.0} takes no keys on the shelf")
  }
  assert_false(said.contains("给设置页加一个深色模式开关"), msg="Home's row not read out")
  assert_false(tabs.iter().any(fn(l) { l.contains("筛选会话") || l.contains("搜索") }), msg="nothing of Home's reached by Tab: \{Repr(tabs)}")
  let filter = filter_of(src, w.id)
  t.tap(40.0, 120.0)
  t.run_for(kept_switch_over_ms)
  assert_eq(filter_of(src, w.id), filter)
  // (a layer opened on 连接 and closed: what had the focus before it, nothing of Home's)
  @ui.view_tree()
  .unwrap()
  .event(t.time(), fn() { @sfpages.filter_menu(@sf.Beside::At(20.0, 60.0, 34.0, 34.0), filter_of(src, w.id), fn(_) {  }) })
  t.run_for(kept_switch_over_ms)
  assert_true(@sf.presenting())
  t.back()
  t.run_for(kept_switch_over_ms)
  assert_false(@sf.presenting())
  assert_false(t.focused().map(fn(s) { s.value }) == Some("abcq"), msg="Home's field took no focus back")
  // (back on Home: its words as they were typed, its field not focused till it is pressed, as any switch leaves it)
  kept_go(t, "chats", true)
  t.run_for(kept_switch_over_ms)
  assert_true(t.words().iter().any(fn(x) { x.0.contains("abcq") }) || @sfpages.search_bar_away(), msg="its search as it was left")
  assert_true(t.a11y_dump().contains("给设置页加一个深色模式开关") || @sfpages.search_bar_away(), msg="read out again")
}

///|
test "bar places kept: on 大屏 a place switched to from the rail is put in place as before, the one left let go, nothing kept" {
  let t = wide_tester([])
  t.run_for(kept_switch_over_ms)
  let first = app.nav.top_stay().0
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.go_place("connects") |> ignore })
  t.run_for(kept_switch_over_ms)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.go_place("chats") |> ignore })
  t.run_for(kept_switch_over_ms)
  // (Home made anew in its place: another entry, none on the shelf)
  println("bar-kept wide: \{Repr(app.nav.pages().map(place_of))}")
  assert_true(app.nav.pages()[0] == Home)
  assert_true(app.nav.top_stay().0 != first)
  assert_eq(app.nav.shelved(Home), None)
  assert_eq(app.nav.shelved(Place("connects")), None)
}

///|
test "bar places kept: a place switched away from while its way in goes, and not come back to: the app at rest once the bar's own ways end" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  bars_picked.set(Some(([kept_bar], 0)))
  t.run_for(kept_switch_over_ms)
  kept_go(t, "connects", true)
  t.run_for(kept_switch_over_ms)
  // (Home again, then 连接 again within Home's way in: Home put by with its way in going)
  kept_go(t, "chats", true)
  t.run_for(kept_tab_gap_ms)
  kept_go(t, "connects", true)
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  t.assert_idle()
  assert_eq(t.idle_said(), None)
}

///|
/// Place `place` opened on the workspace of real size in the phone's window (home_again_open), `choose` done on it,
/// then a finger up the page and left at rest, switched to 额度 and back, each switch kept: the words in the middle at
/// its top, as it was left and where those are once it is come back to, and where the top's are as it is left.
fn kept_remember(place : String, choose : (@ui.Tester) -> Unit) -> ((String, Array[Double]), (String, Array[Double]), Array[Double], Array[Double]) {
  let (t, _, _) = home_again_open("remember \{place}", @ui.frame_period_default)
  bars_picked.set(Some(([kept_bar], 0)))
  t.run_for(kept_switch_over_ms)
  kept_go(t, place, true)
  t.run_for(kept_switch_over_ms)
  choose(t)
  let top = kept_mark(t)
  t.drag(180.0, 560.0, 180.0, 260.0, steps=20)
  t.run_for(kept_glide_over_ms)
  let left = kept_mark(t)
  let top_now = kept_mark_at(t, top.0)
  kept_go(t, "profiles", true)
  t.run_for(kept_switch_over_ms)
  kept_go(t, place, true)
  t.run_for(kept_switch_over_ms)
  let back = kept_mark_at(t, left.0)
  println("bar-kept remember \{place}: at its top \{Repr(top)}, left \{Repr(left)} (the top's words then at \{Repr(top_now)}), come back \{Repr(back)}")
  (top, left, top_now, back)
}

///|
/// Scrolled before it was left: what was in the middle at its top is drawn higher by most of the finger's way, or gone.
fn kept_scrolled(top : (String, Array[Double]), left : (String, Array[Double]), top_now : Array[Double]) -> Bool {
  top.1.length() > 0 && left.1.length() > 0 && (top_now.length() == 0 || top_now[0] < top.1[0] - 100.0)
}

///|
test "bar places kept: 用量 comes back scrolled where it was left" {
  // (on the workspace of real size: its activity, its people and their chats, longer than the phone's window; the owner,
  // 2026-11-12: 「三样都记得」. 连接 is not walked so here yet: 我的 picked on it there, the connects that go leave by
  // sf's keyed_rows_node, whose row reads the clock in a binding (its `going()`, made at parts_node.mbt:36), which the
  // Tester stops on (clock_read.mbt). 连接's 我的 kept is held by bar_places_today, on the fixture's two connects)
  let (top, left, top_now, back) = kept_remember("usage", fn(_) {  })
  assert_true(kept_scrolled(top, left, top_now), msg="用量 scrolled before it was left")
  assert_eq(back, left.1, msg="用量 scrolled where it was left")
}

///|
/// Each change of the real workspace's chats' lists taken (by every cause, real_size_changed's), or with `back` each
/// put back as it was first; whether any was.
fn kept_chats_changed(c : @sfrealsize.RealSizeChanging, back : Bool) -> Bool {
  let mut any = false
  for i, way in c.ways() {
    if way.0 == "chats" {
      if back {
        c.put_back(i)
        any = true
      } else {
        for change in c.changed(i) {
          for m in change.1 {
            c.put(i, m)
            any = true
          }
        }
      }
    }
  }
  any
}

///|
test "bar places kept: Home's rows changed as it rested are there at once as it is taken back, as on Home made anew; changed after, they move" {
  // (the owner's phone, 2026-11-12: back to 对话 from Station, the rows under 今天 drawn only as they came in, over
  // row_size_ms, as were each new to the list)
  for kept in [true, false] {
    let (t, c, _) = home_again_open("kept rows \{kept}", @ui.frame_period_default)
    bars_picked.set(Some(([kept_bar], 0)))
    t.run_for(kept_switch_over_ms)
    kept_go(t, "connects", kept)
    t.run_for(kept_switch_over_ms)
    assert_true(kept_chats_changed(c, false))
    t.run_for(kept_few_frames_ms)
    kept_go(t, "chats", kept)
    t.run_for(@ui.frame_period_default)
    assert_true(@sfpages.rows_rest() <= t.time(), msg="kept \{kept}: no row coming or going as Home is switched back to")
    // (changed again while it is the page shown: its rows make their way as ever)
    t.run_for(kept_switch_over_ms)
    assert_true(kept_chats_changed(c, true))
    t.run_for(@ui.frame_period_default)
    assert_true(@sfpages.rows_rest() > t.time(), msg="kept \{kept}: rows moving as the list changes in view")
  }
}
