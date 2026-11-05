// A login's step's ⋯ (其他方式) pressed by a mouse on a wide window: its menu beside the ⋯ where it is on screen as it is
// pressed, as main's (step_button_of: from=Of(mid)), not at the window's corner.

///|
test "大屏 by mouse: a login's 其他方式 opens its menu beside the ⋯ pressed" {
  let calls : Array[Made] = []
  let t = login_core(
    calls,
    login_of([
      ("step", "loopback"),
      ("url", "https://accounts.google.com/o/oauth2/auth"),
      ("browser", true),
      ("browserText", "在 Willow 的浏览器中打开"),
    ]),
    w=1280.0,
    pointing=Mouse,
  )
  for _ in 0..<6 {
    if said_at(t, "其他方式") is Some(_) {
      break
    }
    t.wheel(700.0, 400.0, -300.0)
  }
  guard said_at(t, "其他方式") is Some((bx, by, bw, bh)) else { fail("no 其他方式") }
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  guard t.find("在 Willow 的浏览器中打开") is Some((ix, iy)) else { fail("its menu not open") }
  // (beside it: within a menu's reach of the ⋯, not at the window's top left)
  assert_true((iy - (by + bh / 2.0)).abs() < 160.0 && (ix - (bx + bw / 2.0)).abs() < 320.0, msg="item at \{ix},\{iy}; the ⋯ at \{bx},\{by}")
}
