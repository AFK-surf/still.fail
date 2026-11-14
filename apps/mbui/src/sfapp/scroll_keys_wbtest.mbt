// A page's list made of nodes answers the keys an old view's list did (@view's scroll_keys.mbt; ui's Ctx::list_key):
// with the pointer over it, Page Down and Page Up by what shows less a line, ↓ and ↑ by a line, End and Home to its
// ends, each at once; none of it while a field has the focus. The settings' list and the chats' list in a desktop's
// window with keyboard and mouse, Home in a phone's with a finger.

///|
/// How far what shows of the list under `x0`..`x1` moved up between `before` and now: the shift other than none its
/// words share most (those in both, each once on screen: what stays over the list, its bars, shifts none), 0 where none
/// moved.
fn list_shift(t : @ui.Tester, before : Array[(String, Double, Double, Double, Double, Double)], x0 : Double, x1 : Double) -> Double {
  let once = fn(ws : Array[(String, Double, Double, Double, Double, Double)]) {
    let m : Map[String, Double] = Map([])
    let twice : Map[String, Bool] = Map([])
    for w in ws {
      if w.1 >= x0 && w.1 < x1 {
        if m.contains(w.0) {
          twice[w.0] = true
        }
        m[w.0] = w.2
      }
    }
    for k, _ in twice {
      m.remove(k)
    }
    m
  }
  let was = once(before)
  let now = once(t.words())
  let counts : Map[Double, Int] = Map([])
  for k, y in was {
    match now.get(k) {
      Some(y2) if y != y2 => counts[y - y2] = counts.get(y - y2).unwrap_or(0) + 1
      _ => ()
    }
  }
  let mut best = 0.0
  let mut most = 0
  for d, n in counts {
    if n > most || (n == most && d.abs() < best.abs()) {
      best = d
      most = n
    }
  }
  best
}

///|
/// Key `code` pressed with the pointer where it is, at once: how far the list under `x0`..`x1` moved up by it, as the
/// frame after it draws it.
fn key_shift(t : @ui.Tester, code : Int, x0 : Double, x1 : Double) -> Double {
  let before = t.words()
  t.key(code)
  t.frame()
  list_shift(t, before, x0, x1)
}

///|
test "the settings' list scrolls by the keys under the pointer, a desktop's window, keyboard and mouse" {
  let t = wide_tester([], mode="settings", h=430.0, platform=0)
  t.click(Button, label=@sf.t("web-pages.settings.title"))
  t.run_for(@ui.move_most_ms)
  let (x, y, w, _) = t.rect_of("Station").unwrap()
  t.move_to(x + w / 2.0, y)
  let line = @view.scroll_key_line
  let down = key_shift(t, @ui.key_code_down, 0.0, x + 300.0)
  let up = key_shift(t, @ui.key_code_up, 0.0, x + 300.0)
  let page = key_shift(t, @ui.key_code_page_down, 0.0, x + 300.0)
  let page_up = key_shift(t, @ui.key_code_page_up, 0.0, x + 300.0)
  t.key(@ui.key_code_end)
  t.frame()
  let foot = t.shown_of("关于")
  t.key(@ui.key_code_home)
  t.frame()
  let (_, home_y, _, _) = t.rect_of("Station").unwrap()
  assert_eq((down, up, page > line, page_up, foot is Some(_), home_y), (line, -line, true, -page, true, y))
}

///|
test "the settings' list keeps still under the keys while a field has the focus" {
  let t = wide_tester([], mode="settings", h=430.0, platform=0)
  t.click(Button, label=@sf.t("web-pages.settings.title"))
  t.run_for(@ui.move_most_ms)
  let (sx, sy) = t.find("搜索设置").unwrap()
  t.tap(sx, sy)
  t.frame()
  let (x, y, w, _) = t.rect_of("Station").unwrap()
  t.move_to(x + w / 2.0, y)
  let moved = [
    key_shift(t, @ui.key_code_page_down, 0.0, x + 300.0),
    key_shift(t, @ui.key_code_end, 0.0, x + 300.0),
    key_shift(t, @ui.key_code_down, 0.0, x + 300.0),
  ]
  assert_eq(moved, [0.0, 0.0, 0.0])
}

///|
test "the chats' list keeps still under the keys while the composer has the focus, a desktop's window" {
  let t = wide_tester([], h=300.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.move_to(150.0, 200.0)
  // (a desktop's window opens with the composer's field focused: the keys its, as they were)
  let focused = t.focused().map(fn(n) { n.role })
  let moved = [
    key_shift(t, @ui.key_code_page_down, 0.0, 300.0),
    key_shift(t, @ui.key_code_end, 0.0, 300.0),
  ]
  assert_eq((focused, moved), (Some(@view.TextField), [0.0, 0.0]))
}

///|
test "Home's list scrolls by the keys under the pointer, a window narrowed with keyboard and mouse" {
  let t = wide_tester([], w=390.0, h=300.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // (over its rows, clear of what floats over the list's foot)
  t.move_to(100.0, 130.0)
  let line = @view.scroll_key_line
  let down = key_shift(t, @ui.key_code_down, 0.0, 390.0)
  let page = key_shift(t, @ui.key_code_page_down, 0.0, 390.0)
  let page_up = key_shift(t, @ui.key_code_page_up, 0.0, 390.0)
  let up = key_shift(t, @ui.key_code_up, 0.0, 390.0)
  assert_eq((t.focused().map(fn(n) { n.role }), down, page > line, page_up, up), (None, line, true, -page, -line))
}

///|
test "the settings' list scrolls by the keys where the finger last was, a phone's window" {
  let t = wide_tester([], mode="settings", w=390.0, h=500.0, platform=2)
  t.click(Button, label=@sf.t("web-pages.settings.title"))
  t.run_for(@ui.move_most_ms)
  let (x, y, w, _) = t.rect_of("Station").unwrap()
  t.move_to(x + w / 2.0, y)
  let line = @view.scroll_key_line
  let down = key_shift(t, @ui.key_code_down, 0.0, 390.0)
  let up = key_shift(t, @ui.key_code_up, 0.0, 390.0)
  assert_eq((down, up), (line, -line))
}
