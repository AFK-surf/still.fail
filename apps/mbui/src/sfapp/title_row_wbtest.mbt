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
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "新建对话", 400.0)
  let t = wide_tester(calls, mode="chat", window_inset=true)
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "a chat", 400.0)
  let t = wide_tester(calls, window_inset=true)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "settings", 400.0)
  let t = wide_tester(calls, mode="decisions", window_inset=true)
  open_decisions()
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "奏", 400.0)
  for place in ["stations", "profiles", "usage"] {
    let t = wide_tester(calls, window_inset=true)
    app.nav.replace(Place(place))
    t.run_for(@sfdesk.side_move_ms)
    row_drags(t, place, 400.0)
  }
  let t = wide_tester(calls, window_inset=true)
  app.nav.replace(Files)
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "文件", 400.0)
  // laid out Medium, on the tape: the sidebar in use, then the page's panel brought over
  let t = wide_tester(calls, mode="chat", w=690.0, h=840.0, window_inset=true)
  t.run_for(@ui.nav_push_ms)
  row_drags(t, "the tape's sidebar", 0.0)
  t.tap(650.0, 400.0)
  t.run_for(@sfdesk.side_move_ms * 2.0)
  row_drags(t, "the tape's chat", 200.0)
  let t = wide_tester(calls, w=690.0, h=840.0, window_inset=true)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.nav_push_ms)
  t.tap(650.0, 400.0)
  t.run_for(@sfdesk.side_move_ms * 2.0)
  row_drags(t, "the tape's settings page", 200.0)
  let t = wide_tester(calls, mode="decisions", w=690.0, h=840.0, window_inset=true)
  open_decisions()
  t.run_for(@ui.nav_push_ms)
  t.tap(650.0, 400.0)
  t.run_for(@sfdesk.side_move_ms * 2.0)
  row_drags(t, "the tape's 奏", 200.0)
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
  t.run_for(@ui.nav_push_ms)
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
