// A Windows window has no title bar of the system's either, nor its buttons: the app draws them (@sf.window_keys) at
// the top row's right, as still.fail's desktop app did, the maximize one's place told the host (Windows' Snap Layouts
// open from it), and what a top row holds at the window's right stands before them.

///|
/// A named button on screen by its name: where it is.
fn named_at(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? raise {
  let all = t.semantics().filter(fn(s) { !s.hidden && s.label == label && s.role is Button }).map(fn(s) { s.rect })
  if all.length() > 1 {
    fail("\{all.length()} buttons named \{label}: \{all}")
  }
  all.get(0)
}

///|
/// The window's own buttons' names, minimize, maximize or back, close (the menu bar's and the desktop app's words).
let window_key_names : Array[String] = ["最小化", "最大化", "还原", "关闭窗口"]

///|
/// Whether a key of a bar in the window's top row (a named button 32 across, its first 45 high; not a bar itself, a
/// button across it), other than the window's own buttons, reaches past `x`: under them, or between them and the rule
/// before them.
fn past_rule(t : @ui.Tester, x : Double) -> String? {
  for s in t.semantics() {
    let (sx, sy, sw, sh) = s.rect
    if !s.hidden &&
      s.label != "" &&
      !window_key_names.contains(s.label) &&
      (s.role is (Button | Link | Tab)) &&
      sw <= 32.0 &&
      sy >= 0.0 &&
      sy + sh <= 60.0 &&
      sx + sw > x {
      return Some(s.label)
    }
  }
  None
}

///|
test "a Windows window laid out Large: its own buttons at the top row's right, 12 in and on the bars' line, the page's keys before their rule" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  // the last as a bar's last key stands at a corner it cannot follow (Windows 11's 8), 2 apart, 6 under the top
  guard named_at(t, "关闭窗口") is Some((cx, cy, cw, ch)) else { fail("no close button") }
  assert_eq((cx + cw, cy, cw, ch), (1268.0, 6.0, 32.0, 32.0))
  guard named_at(t, "最大化") is Some((zx, zy, _, _)) else { fail("no maximize button") }
  assert_eq((zx, zy), (cx - 34.0, 6.0))
  guard named_at(t, "最小化") is Some((mx, _, _, _)) else { fail("no minimize button") }
  assert_eq(mx, zx - 34.0)
  // the maximize one's place, the host's (the pointer there is its)
  assert_eq(t.window_snap_rect(), (zx, zy, 32.0, 32.0))
  // the chat's bar's keys before their rule (8 before it, 1 across, 6 and 2 to the first)
  assert_eq(past_rule(t, mx - 17.0), None)
  // its top row drags the window but for what is pressed there, the buttons among it
  assert_true(t.drags_window_at(700.0, 22.0))
  assert_false(t.drags_window_at(cx + 16.0, 22.0))
}

///|
test "a Windows window laid out Large: a new chat's Station 文件 before the window's buttons' rule, its panel open or closed" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="newchat-files", platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == NewChat)
  guard named_at(t, "最小化") is Some((mx, _, _, _)) else { fail("no minimize button") }
  // kept open: the panel's bar's switch before them
  assert_eq(past_rule(t, mx - 17.0), None)
  // closed: 文件 at the page's end before their rule, as a chat's bar's last is (it stood under close)
  t.click(Button, label="收起侧栏")
  t.run_for(@ui.move_most_ms)
  guard named_at(t, "Station 文件") is Some((fx, _, fw, _)) else { fail("no Station 文件") }
  assert_eq(fx + fw, mx - 17.0 - 12.0)
  assert_eq(past_rule(t, mx - 17.0), None)
}

///|
test "a Windows window's buttons: minimize and close do what the window's do; maximize as the host says the pointer stands on it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  guard named_at(t, "最小化") is Some((mx, my, mw, mh)) else { fail("no minimize button") }
  t.tap(mx + mw / 2.0, my + mh / 2.0)
  guard named_at(t, "关闭窗口") is Some((cx, cy, cw, ch)) else { fail("no close button") }
  t.tap(cx + cw / 2.0, cy + ch / 2.0)
  assert_eq(t.window_acts(), [1, 3])
  // the pointer on maximize, then pressing it, as the host says: lit, then held down (its press the host's)
  t.set_window_snap(1)
  t.run_for(@sf.dur_ms)
  t.set_window_snap(2)
  t.run_for(@sf.dur_ms)
  t.set_window_snap(0)
  // maximized, its button the one bringing it back
  t.set_window_zoomed(true)
  t.frame()
  assert_true(named_at(t, "还原") is Some(_))
  assert_true(named_at(t, "最大化") is None)
}

///|
test "a Windows window laid out Small: its buttons in the band over the page; on the tape, on its line, the strip at the right holding them" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  guard named_at(t, "关闭窗口") is Some((cx, cy, cw, _)) else { fail("no close button") }
  assert_eq((cx + cw, cy), (378.0, 6.0))
  // nothing of the page's in the band (44) under them
  for s in t.semantics() {
    let (_, sy, _, sh) = s.rect
    if !s.hidden && s.label != "" && !window_key_names.contains(s.label) && sy + sh > 0.0 && sy < 44.0 {
      fail("\{s.label} in the band of the window's buttons")
    }
  }
  // laid out Medium: on the tape's line, concentric with the top right corner of the panel at the window's edge (its
  // 28, 6 in: 18), the sidebar in use and the page's strip at the right as wide as holds them (the rule's 8 before
  // them on it, its edge 6 past that)
  let t = wide_tester(calls, mode="chat", w=690.0, h=840.0, platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  guard named_at(t, "关闭窗口") is Some((cx, cy, cw, _)) else { fail("no close button") }
  let line = @sf.window_in + @sf.tape_line
  assert_eq((cx + cw, cy), (690.0 - line, line))
  guard named_at(t, "最小化") is Some((mx, _, _, _)) else { fail("no minimize button") }
  assert_true((@sfdesk.tape_shows_right() - (690.0 - (mx - 17.0) + 6.0)).abs() < 1.0e-9)
  // the page's panel brought over: where they are the same, its bar's keys before them
  t.tap(650.0, 400.0)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_eq(named_at(t, "关闭窗口").map(fn(r) { (r.0 + r.2, r.1) }), Some((690.0 - line, line)))
  assert_eq(past_rule(t, mx - 17.0), None)
}

///|
test "a Windows window: the top row drags it on every page but for what is pressed there, its own buttons among that" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "新建对话", 400.0)
  let t = wide_tester(calls, mode="chat", platform=3, window_corner=8.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "a chat", 400.0)
  let t = wide_tester(calls, platform=3, window_corner=8.0, window_inset=true)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "文件", 400.0)
  let t = wide_tester(calls, platform=3, window_corner=8.0, window_inset=true)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  row_drags(t, "settings", 400.0)
}
