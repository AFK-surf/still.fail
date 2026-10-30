// A Mac's window has no title bar of the system's: the app's top row is it (sfdesk's frame.mbt title_row under each
// page and the window, the bars and the sidebar's first row over them: Ctx::window_drag), and the system takes none of
// the app's presses there (mbui's mac host: its canvas opaque to window moves under the system's bar).

///|
/// Whether a press at (x, y) lands on a control: what its semantics say it is, named (a box pressed for itself alone,
/// a page's, a list's, says no name; a panel's edge, dragged, is a Separator named).
fn control_at(t : @ui.Tester, x : Double, y : Double) -> Bool {
  t.semantics().iter().any(fn(s) {
    let (sx, sy, sw, sh) = s.rect
    let control = s.role
      is (Button | Link | Tab | Switch | Checkbox | Radio | TextField | Combobox | MenuItem | Slider | Option | Separator)
    !s.hidden && control && s.label != "" && x >= sx && x < sx + sw && y >= sy && y < sy + sh
  })
}

///|
/// Across the window's top row at `y`, every 8 points: what is not a control drags the window, and so does some of the
/// page's part of it (from `from` on).
fn row_drags(t : @ui.Tester, what : String, from : Double, y? : Double = 22.0) -> Unit raise {
  let mut x = 2.0
  let mut page = false
  while x < t.ctx().width {
    let drags = t.drags_window_at(x, y)
    if !drags && !control_at(t, x, y) {
      fail("\{what}: a press at \{x} is neither a control's nor the window's")
    }
    if drags && x >= from {
      page = true
    }
    x = x + 8.0
  }
  if !page {
    fail("\{what}: nothing of the page's top row drags the window")
  }
}

///|
test "a Mac's window: the top row drags it on every page, with a bar there or not, but for what is pressed there" {
  let calls : Array[Made] = []
  // laid out Large: the page beside the sidebar from 400 on
  let t = wide_tester(calls, window_inset=true)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "新建对话", 400.0)
  let t = wide_tester(calls, mode="chat", window_inset=true)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "a chat", 400.0)
  let t = wide_tester(calls, window_inset=true)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "settings", 400.0)
  for place in ["stations", "profiles", "usage"] {
    let t = wide_tester(calls, window_inset=true)
    app.nav.replace(Place(place))
    t.run_for(@ui.move_most_ms)
    row_drags(t, place, 400.0)
  }
  let t = wide_tester(calls, window_inset=true)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "文件", 400.0)
  // laid out Medium, on the tape: the sidebar in use, then the page's panel brought over
  let t = wide_tester(calls, mode="chat", w=690.0, h=840.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "the tape's sidebar", 0.0)
  t.tap(650.0, 400.0)
  t.run_for(@ui.move_most_ms * 2.0)
  row_drags(t, "the tape's chat", 200.0)
  let t = wide_tester(calls, w=690.0, h=840.0, window_inset=true)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.tap(650.0, 400.0)
  t.run_for(@ui.move_most_ms * 2.0)
  row_drags(t, "the tape's settings page", 200.0)
}

///|
/// The middle of a named control in the window's top row (its 45, from `from` on), where a press is the control's.
fn row_control(t : @ui.Tester, from : Double) -> (Double, Double)? {
  for s in t.semantics() {
    let (x, y, w, h) = s.rect
    let (cx, cy) = (x + w / 2.0, y + h / 2.0)
    if !s.hidden &&
      s.label != "" &&
      (s.role is (Button | Tab | Radio)) &&
      x >= from &&
      y >= 0.0 &&
      y + h <= 45.0 &&
      !t.drags_window_at(cx, cy) {
      return Some((cx, cy))
    }
  }
  None
}

///|
test "a Mac's window: a double click on a button in the top row is the button's twice, on the row's empty part the window's" {
  let calls : Array[Made] = []
  // 文件's bar: its buttons stay where they are pressed
  let t = wide_tester(calls, window_inset=true)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  guard row_control(t, 400.0) is Some((x, y)) else { fail("no button in 文件's bar") }
  t.tap(x, y)
  t.tap(x, y)
  assert_eq(t.window_drags(), 0)
  // the bar's empty part: each press the window's (a drag, then what the system does on a double click)
  let mut empty = 400.0
  while !t.drags_window_at(empty, 22.0) && empty < 1280.0 {
    empty = empty + 8.0
  }
  t.tap(empty, 22.0)
  t.tap(empty, 22.0)
  assert_eq(t.window_drags(), 2)
}

///|
/// Across the window's top row at `y`, every 8 points up to the window's own buttons where the app draws them (Windows':
/// what they take presses in is theirs): each press drags the window (a page with nothing pressed there).
fn row_all_drags(t : @ui.Tester, what : String, y? : Double = 12.0) -> Unit raise {
  let keys = @sf.t("desktop.menu.minimize")
  let end = match t.semantics().iter().find_first(fn(s) { !s.hidden && s.label == keys }) {
    Some(s) => s.rect.0
    None => t.ctx().width
  }
  let mut x = 2.0
  while x < end {
    if !t.drags_window_at(x, y) && !control_at(t, x, y) {
      fail("\{what}: a press at \{x} is neither a control's nor the window's")
    }
    x = x + 8.0
  }
}

///|
test "a window with its buttons in the app's top row: its top drags it before any page, on the splash and signing in" {
  // macOS's and Windows' (their own buttons in the app's top row), small and wide
  for platform in [0, 3] {
    for w in [390.0, 1280.0] {
      let at = "platform \{platform} at \{w}"
      // the splash: the accounts not read yet (a window of its own still starting), past the second it shows the ground
      // alone
      reset()
      let base = fixture("home")
      let src : Source = {
        ..base,
        topic: fn(name, params) {
          if name == "accounts" {
            { value: None, error: None, version: 0 }
          } else {
            (base.topic)(name, params)
          }
        },
      }
      let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=800.0, platform~, window_inset=true)
      t.run_for(splash_label_ms + 100.0)
      assert_true(!frame_bare.get(), msg="\{at}: the splash's mark shown")
      row_all_drags(t, "\{at}: the splash")
      // signed out: the sign-in page
      reset()
      let src = fixture("signin")
      let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=800.0, platform~, window_inset=true)
      t.frame()
      row_all_drags(t, "\{at}: signing in")
    }
  }
}

///|
test "a new chat with its 文件 tab: the empty part of its bar drags the window, the tab open beside it or not" {
  let calls : Array[Made] = []
  // (the page under it takes presses over the window's title row: what drags there is the bar's own)
  for platform in [0, 3] {
    let t = wide_tester(calls, mode="newchat-files", platform~, window_inset=true)
    t.run_for(@ui.move_most_ms)
    assert_true(t.drags_window_at(600.0, 22.0), msg="platform \{platform}: the tab open")
    t.click(Button, label="收起侧栏")
    t.run_for(@ui.move_most_ms)
    assert_true(t.drags_window_at(600.0, 22.0), msg="platform \{platform}: the tab closed")
    assert_true(t.drags_window_at(1000.0, 22.0), msg="platform \{platform}: the tab closed, by 文件")
    let before = t.window_drags()
    t.tap(600.0, 22.0)
    assert_eq(t.window_drags() - before, 1)
  }
}
