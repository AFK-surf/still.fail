// The rail's right-click menu stays by what opened it, including as it closes and near the window's edges.

///|
test "the rail's menu keeps its contents and place while it closes" {
  for outside in [false, true] {
    let t = wide_tester([])
    t.host_says_finger(Some(false))
    let (x, y, w, h) = t.query(Button, label="文件").unwrap().rect
    t.right_click(x + w / 2.0, y + h / 2.0)
    t.run_for(@kit.pop_ms)
    let before = t.rect_of("自定义侧边条").unwrap()
    if outside {
      t.touch_at(0, 640.0, 400.0, t.time())
      t.touch_at(2, 640.0, 400.0, t.time())
    } else {
      t.key_told(@ui.key_escape, 0, t.time())
    }
    for _ in 0..<3 {
      t.run_for(@kit.pop_out_ms / 4.0)
      guard t.rect_of("自定义侧边条") is Some(during) else { fail("the menu's words disappeared while it closed") }
      assert_true(
        (during.0 - before.0).abs() < 2.0 && (during.1 - before.1).abs() < 2.0,
        msg="the menu moved while closing: \{Repr(before)} to \{Repr(during)}",
      )
      assert_true(t.query(MenuItem, label="自定义侧边条") is None, msg="the closing menu cannot be chosen")
    }
    t.run_for(@kit.pop_out_ms)
    assert_true(t.rect_of("自定义侧边条") is None, msg="the menu is gone after its exit")
  }
}

///|
test "right clicking a workspace opens the rail's menu beside it and inside the window" {
  for size in [(1280.0, 800.0), (1280.0, 500.0), (1280.0, 320.0), (1280.0, 220.0), (720.0, 800.0)] {
    for name in ["星火工作室", "个人"] {
      let t = wide_tester([])
      t.host_says_finger(Some(false))
      t.resize(size.0, size.1)
      t.frame()
      let held = t.audit()
      let (x, y, w, h) = t.query(Button, label=name).unwrap().rect
      t.right_click(x + w / 2.0, y + h / 2.0)
      t.run_for(@kit.pop_ms)
      let (mx, my, mw, mh) = t.query(Menu).unwrap().rect
      assert_true(mx >= x + w && my <= y + h && my + mh >= y, msg="\{name} \{Repr(size)}: workspace \{Repr((x, y, w, h))}, menu \{Repr((mx, my, mw, mh))}")
      assert_true(mx >= 0.0 && my >= 0.0 && mx + mw <= size.0 && my + mh <= size.1, msg="\{name} \{Repr(size)}: menu outside window \{Repr((mx, my, mw, mh))}")
      assert_true(t.query(MenuItem, label="自定义侧边条") is Some(_), msg="the menu is reachable")
      assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [], msg="\{name} \{Repr(size)}")
    }
  }
}

///|
test "a workspace's menu in a short window scrolls to its last action" {
  let t = wide_tester([], h=220.0)
  t.host_says_finger(Some(false))
  let (x, y, w, h) = t.query(Button, label="个人").unwrap().rect
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.pop_ms)
  let (mx, my, mw, mh) = t.query(Menu).unwrap().rect
  for _ in 0..<5 {
    t.wheel(mx + mw / 2.0, my + mh / 2.0, 120.0)
    t.run_for(@ui.move_most_ms)
  }
  let (ix, iy, iw, ih) = t.query(MenuItem, label="自定义侧边条").unwrap().rect
  assert_true(iy >= my && iy + ih <= my + mh, msg="last action \{Repr((ix, iy, iw, ih))}, menu \{Repr((mx, my, mw, mh))}")
  t.tap(ix + iw / 2.0, iy + ih / 2.0)
  assert_true(@sfdesk.wide.editing.get(), msg="the last action can be chosen")
}

///|
test "the rail's menu can reopen beside another workspace while its previous exit is playing" {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  let (x, y, w, h) = t.query(Button, label="文件").unwrap().rect
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.pop_ms)
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  let (wx, wy, ww, wh) = t.query(Button, label="个人").unwrap().rect
  t.right_click(wx + ww / 2.0, wy + wh / 2.0)
  t.run_for(@kit.pop_ms)
  let (mx, my, _, mh) = t.query(Menu).unwrap().rect
  assert_true(mx >= wx + ww && my <= wy + wh && my + mh >= wy, msg="workspace \{Repr((wx, wy, ww, wh))}, menu \{Repr((mx, my, mh))}")
  assert_true(t.query(MenuItem, label="从侧边条移除文件") is None)
  assert_true(t.query(MenuItem, label="自定义侧边条") is Some(_))
}

///|
test "choosing a rail action keeps the menu's old contents in place during its exit" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.host_says_finger(Some(false))
  let (x, y, w, h) = t.query(Button, label="文件").unwrap().rect
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.pop_ms)
  let before = t.rect_of("从侧边条移除文件").unwrap()
  t.tap_text("从侧边条移除文件")
  t.run_for(@kit.pop_out_ms / 2.0)
  guard t.rect_of("从侧边条移除文件") is Some(during) else { fail("the chosen row disappeared while its menu closed") }
  assert_true((during.0 - before.0).abs() < 2.0 && (during.1 - before.1).abs() < 2.0)
  assert_eq(named(calls, "prefs.set").length(), 1)
}

///|
test "customizing the rail replaces its menu immediately, leaving the new panel reachable" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.host_says_finger(Some(false))
  let (x, y, w, h) = t.query(Button, label="文件").unwrap().rect
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.pop_ms)
  t.tap_text("自定义侧边条")
  assert_true(t.rect_of("从侧边条移除文件") is None, msg="the old menu is not over the new panel")
  t.frame()
  t.tap_text("我参与的")
  assert_true(named(calls, "prefs.set").length() > 0, msg="the panel takes the press")
}
