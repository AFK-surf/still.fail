// What the app reads of where it runs comes from the Tester (mbui's @ui.platform, window_inset…), never from the
// machine the tests run on: a Tester playing Android gets Android's app.

///|
/// The wide frame over the fixture's Home, the Tester playing `platform`, the window's buttons in its top row or not.
fn reads_tester(platform? : Int = 0, window_inset? : Bool = false) -> @ui.Tester {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform~, window_inset~)
  t.draw()
  t
}

///|
test "host reads: the shortcuts as the Tester's system writes them (⌘ on macOS, Ctrl+ on Windows)" {
  for p in [(0, "⌘K", "Ctrl+K"), (3, "Ctrl+K", "⌘K")] {
    let (platform, shown, not_shown) = p
    let t = reads_tester(platform~)
    @sfdesk.wide.keys_open.set(true)
    t.draw()
    assert_true(t.find(shown) is Some(_), msg="platform \{platform}: no \{shown}")
    assert_true(t.find(not_shown) is None, msg="platform \{platform}: \{not_shown}")
    @sfdesk.wide.keys_open.set(false)
  }
}

///|
test "host reads: the window's buttons in the app's top row push the sidebar down; full screen, not" {
  let t = reads_tester()
  let (_, y0) = t.find("新建对话").unwrap()
  let t = reads_tester(window_inset=true)
  let (_, y1) = t.find("新建对话").unwrap()
  assert_eq(y1 - y0, 36.0)
  t.set_window_inset(false)
  t.draw()
  let (_, y2) = t.find("新建对话").unwrap()
  assert_eq(y2, y0)
}

///|
test "host reads: Windows caption buttons on the right leave the sidebar at its normal top" {
  let t = reads_tester(platform=3)
  let (_, normal) = t.find("新建对话").unwrap()
  let t = reads_tester(platform=3, window_inset=true)
  let (_, inset) = t.find("新建对话").unwrap()
  assert_eq(inset, normal)
}

///|
test "host reads: an action's keys said only while a keyboard is at hand: a phone's when one is plugged in, at once" {
  // (Android: none until one is plugged in, none again once it is taken away; macOS ⌘, Windows Ctrl+)
  let t = reads_tester(platform=2)
  assert_eq(@sf.shortcut_keys("composer.file"), "")
  t.set_keyboard(true)
  assert_true(@sf.shortcut_keys("composer.file") != "")
  t.set_keyboard(false)
  assert_eq(@sf.shortcut_keys("composer.file"), "")
  let _ = reads_tester(platform=0)
  assert_true(@sf.shortcut_keys("composer.file").contains("⌘"))
  let _ = reads_tester(platform=3)
  assert_true(@sf.shortcut_keys("composer.file").contains("Ctrl"))
}
