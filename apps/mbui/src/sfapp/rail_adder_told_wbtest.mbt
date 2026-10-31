// The rail changed on 大屏 (自定义侧边条 from the rail's menu: what can be added beside it, sfdesk's rail_adder) ended
// by the hand as its popover is dismissed: Escape, wherever the pointer is; a press outside it and the rail, as it goes
// down. Each at that input's moment, no frame after it; the frame after ending nothing more.

///|
/// 大屏, a mouse's: 自定义侧边条 from the rail's menu (the rail's 文件 right-clicked), the pointer then on the rail at
/// `at` (its 文件, where none is given).
fn rail_changed(at? : (Double, Double)) -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.right_click(rx + rw / 2.0, ry + rh / 2.0)
  t.frame()
  let (mx, my) = t.find("自定义侧边条").unwrap()
  t.tap(mx, my)
  t.frame()
  let (px, py) = match at {
    Some(p) => p
    None => (rx + rw / 2.0, ry + rh / 2.0)
  }
  t.move(px, py)
  t.frame()
  t
}

///|
test "大屏: the rail changed, Escape with the pointer on the rail: the change ended as the key is taken; the frame after ending nothing more" {
  let t = rail_changed()
  let seen = [@sfdesk.wide.editing.get()]
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(@sfdesk.wide.editing.get())
  t.draw()
  seen.push(@sfdesk.wide.editing.get())
  assert_eq(seen, [true, false, false])
}

///|
test "大屏: the rail changed, a press on the page (outside the adder and the rail): the change ended as it goes down; the frame after ending nothing more" {
  let t = rail_changed(at=(640.0, 400.0))
  let seen = [@sfdesk.wide.editing.get()]
  t.touch_at(0, 640.0, 400.0, t.time())
  seen.push(@sfdesk.wide.editing.get())
  t.touch_at(2, 640.0, 400.0, t.time())
  t.draw()
  seen.push(@sfdesk.wide.editing.get())
  assert_eq(seen, [true, false, false])
}

///|
test "大屏: the rail changed, a press on the rail: the change goes on (its places moved and taken out there)" {
  let t = rail_changed()
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.touch_at(0, rx + rw / 2.0, ry + rh / 2.0, t.time())
  t.touch_at(2, rx + rw / 2.0, ry + rh / 2.0, t.time())
  t.draw()
  assert_true(@sfdesk.wide.editing.get())
}

///|
/// 大屏, a mouse's: the rail's menu open (its 文件 right-clicked), dismissed by `how` (as the host hands it on, no frame
/// after it): whether it is open then, once a frame is drawn, as it is opened again the same way and a frame after.
fn rail_menu_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.right_click(rx + rw / 2.0, ry + rh / 2.0)
  t.frame()
  let seen = [@sfdesk.wide.rail_menu.get() is Some(_)]
  how(t)
  seen.push(@sfdesk.wide.rail_menu.get() is Some(_))
  t.draw()
  seen.push(@sfdesk.wide.rail_menu.get() is Some(_))
  t.right_click(rx + rw / 2.0, ry + rh / 2.0)
  t.frame()
  seen.push(@sfdesk.wide.rail_menu.get() is Some(_))
  t.draw()
  seen.push(@sfdesk.wide.rail_menu.get() is Some(_))
  seen
}

///|
test "大屏: the rail's menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(rail_menu_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: the rail's menu dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = rail_menu_dismissed(fn(t) {
    t.touch_at(0, 640.0, 400.0, t.time())
    down.push(@sfdesk.wide.rail_menu.get() is Some(_))
    t.touch_at(2, 640.0, 400.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
/// The rail changed, 文件 on it pressed and let go (as the host hands each on), a frame drawn after where `frames`,
/// then `how`: whether the change goes on as 文件 is let go, as `how` is taken, and once a frame is drawn after; and
/// the page under it then (its stack's depth and top), a frame or none before `how` alike.
fn rail_pressed_then(how : (@ui.Tester) -> Unit, frames? : Bool = false) -> (Array[Bool], (Int, Page)) {
  let t = rail_changed()
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.touch_at(0, rx + rw / 2.0, ry + rh / 2.0, t.time())
  t.touch_at(2, rx + rw / 2.0, ry + rh / 2.0, t.time())
  let seen = [@sfdesk.wide.editing.get()]
  if frames {
    t.frame()
  }
  how(t)
  seen.push(@sfdesk.wide.editing.get())
  t.draw()
  seen.push(@sfdesk.wide.editing.get())
  (seen, (app.nav.depth(), app.nav.top()))
}

///|
/// Whether rail_pressed_then's `how` leaves the change and the page under it the same, a frame before it or none.
fn rail_pressed_alike(how : (@ui.Tester) -> Unit) -> Unit raise {
  let (none, page) = rail_pressed_then(how)
  let (framed, framed_page) = rail_pressed_then(how, frames=true)
  assert_eq((none, framed), ([true, false, false], [true, false, false]))
  // (文件 pressed while the rail was changed: the change's, whatever ends the change after it)
  assert_true(page == framed_page, msg="the page under it alike: \{page.0} against \{framed_page.0}")
}

///|
test "大屏: the rail changed, 文件 on it pressed, then Escape at once: the change still its own as 文件 is let go, ended by the Escape as it is taken (the adder's, none of the page's)" {
  rail_pressed_alike(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) })
}

///|
test "大屏: the rail changed, 文件 on it pressed, then back at once: the change still its own as 文件 is let go, ended by the back as it is taken (the adder's, none of the page's)" {
  rail_pressed_alike(fn(t) { t.back_raw(2, 0.0, t.time()) })
}

///|
test "大屏: the rail changed, a press on the sidebar's edge (a node of the window's tree, out of the adder and the rail): the change ended as it goes down" {
  let t = rail_changed()
  guard t.semantics().iter().find_first(fn(s) { s.label == "调整侧边栏宽度 · 收起侧边栏" }) is Some(s) else {
    fail("no edge")
  }
  let (ex, ey, ew, eh) = s.rect
  let (x, y) = (ex + ew / 2.0, 790.0)
  assert_true(y >= ey && y < ey + eh, msg="on the edge as read out: \{s.rect}")
  t.touch_at(0, x, y, t.time())
  let down = @sfdesk.wide.editing.get()
  // (the edge's node took it: held as it goes down)
  assert_true(@sfdesk.wide.edge_held.get(), msg="the edge took it")
  t.touch_at(2, x, y, t.time())
  t.draw()
  assert_eq((down, @sfdesk.wide.editing.get()), (false, false))
}


///|
/// 大屏, a mouse's, from Home: 文件 on the rail pressed and let go twice (as the host hands each on), a frame drawn
/// between where `frames`: the page then (its stack's depth, whether its top is 文件's), the sidebar folded, shown a while,
/// as the second is let go (no frame after it) and once a frame is drawn.
fn files_twice(frames : Bool) -> ((Bool, Bool), (Int, Bool, Bool, Bool)) {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  t.move(x, y)
  t.frame()
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  if frames {
    t.frame()
  }
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  let at_up = (@sfdesk.wide.folded.get(), @sfdesk.wide.peeking.get())
  t.draw()
  (at_up, (app.nav.depth(), app.nav.top() == Files, @sfdesk.wide.folded.get(), @sfdesk.wide.peeking.get()))
}

///|
test "大屏: 文件 on the rail pressed twice from Home: gone to 文件, then, lit, its sidebar folded and shown a while, a frame between the presses or none" {
  let none = files_twice(false)
  let framed = files_twice(true)
  assert_eq((none, framed), (framed, ((true, true), (framed.1.0, true, true, true))), msg="no frame \{none}, a frame \{framed}")
}

///|
test "大屏: 文件 on the rail held with ⌘ and moved down past the slop, let go on it with no frame since it moved: a drag of it, not a press (the page as it was)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.host_says_finger(Some(false))
  t.draw()
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  // (near its top, let go 10 lower: past the slop, still on it, where a press of it is let go)
  let (x, y) = (rx + rw / 2.0, ry + 4.0)
  assert_true(y + 10.0 < ry + rh, msg="let go on it: \{rh}")
  t.move(x, y)
  t.frame()
  let before = (app.nav.depth(), app.nav.top())
  t.hold_mods(@ui.mod_cmd)
  t.touch_at(0, x, y, t.time())
  // (the drag begun as the frame after it is built: Rail.tsx drag, with ⌘ held as it was pressed)
  t.frame()
  assert_true(@sfdesk.wide.rail_drag.get() is Some(_), msg="its drag begun")
  t.touch_at(1, x, y + 10.0, t.time())
  t.touch_at(2, x, y + 10.0, t.time())
  t.hold_mods(0)
  t.draw()
  let top = match app.nav.top() {
    Home => "Home"
    Files => "Files"
    Place(p) => p
    _ => "another"
  }
  assert_true((app.nav.depth(), app.nav.top()) == before, msg="a drag, not a press: \{top}, depth \{app.nav.depth()}, rails kept \{named(calls, "prefs.set").length()}")
}
