// 中屏 (a touch window 600 wide, a tablet's 840) with a chat open, its workspace switched: Home's new chat comes back
// with its preset picked, the preset's capsule over the composer starting with its folders' marks, and every frame at
// rest after it holds the corner rule (the Tester's own, corners_held). Till 2026-11-14 the capsule stood its first
// mark 12 in from its start and 8 from its top, the mark's corner 7 in the capsule's 15: not concentric, on every such
// Home, and no sweep had a medium window open on it (the real-size sweep opens a phone's and a wide one; the corner
// sweep's fixture picks no preset with marks).

///|
fn medium_switch_walk(w : Double) -> Unit raise {
  new_run()
  let src = sd_source(25.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=2)
  t.draw()
  t.run_for(sd_opening_ms)
  // (a chat of the list opened, as a hand opens it)
  let titles : Array[String] = []
  match @signals.untracked(fn() { @sfbase.chats_of(src, "ws1", "all").0 }) {
    Some(view) =>
      for d in view.days {
        for i in d.items {
          titles.push(i.title)
        }
      }
    None => ()
  }
  guard titles.iter().find_first(fn(s) { t.words().iter().any(fn(x) { x.0 == s }) }) is Some(title) else {
    fail("no chat of the list shown")
  }
  guard t.words().iter().find_first(fn(x) { x.0 == title }) is Some(at) else {
    fail("no \{title}")
  }
  t.tap(at.1 + 4.0, at.2 + 4.0)
  t.run_for(@ui.move_most_ms * 2.0)
  // (its workspace switched from the rail's list, the chat open: Home comes, its new chat with the preset picked)
  @ui.view_tree().unwrap().event(t.time(), fn() {
    @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0), compact=true)
  })
  t.run_for(sd_sheet_up_ms)
  let (x, y) = sd_in_sheet(t, "个人")
  t.tap(x + 4.0, y + 4.0)
  t.run_for(@sfbase.switch_wait_ms + @ui.move_most_ms * 3.0)
  // (the preset's capsule is there: what the rule was broken on)
  assert_true(t.words().iter().any(fn(x) { x.0.contains("still.fail App") }), msg="the preset's capsule not shown")
}

///|
test "medium switch: the touch window's Home after a workspace switch holds the corner rule" {
  medium_switch_walk(600.0)
}

///|
test "medium switch: the tablet's Home after a workspace switch holds the corner rule" {
  medium_switch_walk(840.0)
}
