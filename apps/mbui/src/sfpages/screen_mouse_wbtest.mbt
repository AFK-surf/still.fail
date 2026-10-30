// A station's screen with keyboard and mouse (screen_view.mbt's viewer bar, screen_stage.mbt's screen_mouse), as the
// web's page has it on a computer: the viewer's bar across the window's top and the picture under it, nothing a
// phone's hand needs; the mouse the screen's pointer where it is, the keyboard its own once it is pressed, ⌘V this
// device's clipboard pasted there, 全屏 the window's.

///|
/// The viewer in a computer's window, a moment after it opened (正在连接 said by then, the frame round it still).
fn mouse_rig() -> ScreenRig {
  let r = screen_rig(w=1280.0, h=800.0, platform=0)
  r.t.run_for(@sf.later_ms)
  r
}

///|
/// The test's end with a mouse: the pointer gone from the window (no tip coming over what it rested on, nothing it
/// lit still lit), the frame round the screen at rest.
fn mouse_done(r : ScreenRig) -> Unit {
  r.t.leave()
  r.t.run_for(@kit.tooltip_delay_ms)
  let rest = r.t.rest_of("Anim")
  if rest > r.t.time() {
    r.t.run_for(rest - r.t.time())
  }
  screen_done(r.t)
}

///|
test "with keyboard and mouse: the viewer's bar across the top, the picture under it, nothing a finger needs; back closes it" {
  let r = mouse_rig()
  r.live()
  assert_true(r.t.find("still.fail — Chrome") is Some(_))
  assert_true(r.t.find("控制 · 李雷也在看") is Some(_))
  assert_true(r.labelled(tr("common.back")) is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.stats")) is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.panel")) is Some(_))
  assert_true(r.labelled("控制") is Some(_))
  // none of a phone's: its ×, the keyboard to raise, the trackpad, the paste button, the keys row
  assert_true(r.labelled("关闭") is None)
  assert_true(r.labelled("键盘") is None)
  assert_true(r.labelled("触控板") is None)
  assert_true(r.labelled("粘贴手机剪贴板") is None)
  assert_true(r.labelled("Esc") is None)
  // the picture under the bar, the window's width
  let u = r.ui()
  assert_true(u.stage_y.get() >= @sf.viewer_bar_h)
  assert_eq(u.box_w.get(), 1280.0)
  assert_eq(r.t.squeeze_faults(), [])
  r.tap_label(tr("common.back"))
  nav_rested(r.t)
  assert_true(!(app.nav.top() is Screen(_)))
  r.t.draw()
  mouse_done(r)
}

///|
test "a mouse is the screen's pointer where it is: moved over the picture, clicked there, dragged held, right clicked, its wheel" {
  let r = mouse_rig()
  r.live(others=[])
  // moved over the picture: the screen's pointer goes there, no button held
  let (mx, my) = r.at(0.25, 0.5)
  r.t.move(mx, my)
  let ins = r.inputs()
  assert_eq(ins.length(), 1)
  assert_eq(kind_of_input(ins[0]), "move")
  assert_eq(number(Some(ins[0]), "buttons"), 0.0)
  assert_true(close_to(number(Some(ins[0]), "x"), 0.25))
  assert_true(close_to(number(Some(ins[0]), "y"), 0.5))
  // still: nothing more
  r.t.draw()
  assert_eq(r.inputs().length(), 1)
  // clicked: down and up with the primary button where it was clicked
  r.tap_at(0.75, 0.25)
  let click = r.inputs()[1:].to_array()
  assert_eq(click.length(), 2)
  assert_eq(kind_of_input(click[0]), "down")
  assert_eq(number(Some(click[0]), "buttons"), 1.0)
  assert_true(close_to(number(Some(click[0]), "x"), 0.75))
  assert_true(close_to(number(Some(click[0]), "y"), 0.25))
  assert_eq(kind_of_input(click[1]), "up")
  // the press gave it the keyboard
  assert_true(r.t.key_catching())
  // dragged: down where it began, moves with the button held, up where it was let go
  let from = r.inputs().length()
  let (ax, ay) = r.at(0.2, 0.6)
  let (bx, by) = r.at(0.6, 0.6)
  r.t.drag(ax, ay, bx, by)
  let drag = r.inputs()[from:].to_array()
  assert_eq(kind_of_input(drag[0]), "down")
  assert_true(close_to(number(Some(drag[0]), "x"), 0.2))
  let moves = drag.filter(fn(j) { kind_of_input(j) == "move" })
  assert_true(moves.length() >= 2)
  assert_true(moves.iter().all(fn(j) { number(Some(j), "buttons") == 1.0 }))
  let up = drag[drag.length() - 1]
  assert_eq(kind_of_input(up), "up")
  assert_true(close_to(number(Some(up), "x"), 0.6))
  // right clicked: down and up with the secondary button there
  let from = r.inputs().length()
  let (rx, ry) = r.at(0.4, 0.4)
  r.t.move(rx, ry)
  r.t.right_click(rx, ry)
  let right = r.inputs()[from:].to_array().filter(fn(j) { kind_of_input(j) != "move" })
  assert_eq(right.length(), 2)
  assert_eq(kind_of_input(right[0]), "down")
  assert_eq(number(Some(right[0]), "buttons"), 2.0)
  assert_true(close_to(number(Some(right[0]), "x"), 0.4))
  assert_eq(kind_of_input(right[1]), "up")
  // the wheel where the mouse is, in pixels
  r.t.wheel_with(rx, ry, 0.0, 120.0, 0)
  let wheel = r.inputs().last().unwrap()
  assert_eq(text(Some(wheel), "t"), "wheel")
  assert_eq(number(Some(wheel), "dy"), 120.0)
  assert_true(close_to(number(Some(wheel), "x"), 0.4))
  // a trackpad's pinch zooms nothing there
  let before = r.inputs().length()
  r.t.wheel_with(rx, ry, 0.0, 30.0, @ui.wheel_mod_pinch)
  assert_eq(r.inputs().length(), before)
  mouse_done(r)
}

///|
test "a click with ⇧ or ⌘ held is one there: their keys go down before it and up after it" {
  let r = mouse_rig()
  r.live(others=[])
  r.t.hold_mods(@ui.mod_shift_key)
  r.tap_at(0.5, 0.5)
  r.t.hold_mods(0)
  let ins = r.inputs()
  assert_eq(ins.length(), 4)
  assert_eq(text(Some(ins[0]), "code"), "ShiftLeft")
  assert_eq(kind_of_input(ins[0]), "down")
  assert_eq(kind_of_input(ins[1]), "down")
  assert_eq(text(Some(ins[1]), "t"), "pointer")
  assert_eq(kind_of_input(ins[2]), "up")
  assert_eq(text(Some(ins[3]), "code"), "ShiftLeft")
  assert_eq(kind_of_input(ins[3]), "up")
  mouse_done(r)
}

///|
test "the keyboard types into it once it is pressed; ⌘V pastes this device's clipboard there, ⌘C goes as its keys" {
  let r = mouse_rig()
  driven(r)
  r.tap_at(0.5, 0.5)
  let from = r.inputs().length()
  r.t.type_text("hi 你好")
  let typed = r.inputs()[from:].to_array()
  assert_eq(text(Some(typed[0]), "t"), "text")
  assert_eq(text(Some(typed[0]), "text"), "hi 你好")
  r.t.clipboard_gives("from the Mac")
  let from = r.inputs().length()
  r.t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  r.t.draw()
  let asked = r.told("screen.clipboard")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "text"), "from the Mac")
  assert_eq(field(Some(asked[0]), "paste"), Some(Json::boolean(true)))
  assert_eq(r.inputs().length(), from)
  r.t.key(@ui.key_of_char('c'), mods=@ui.mod_cmd)
  let copy = r.inputs()[from:].to_array()
  assert_eq(copy.length(), 2)
  assert_eq(text(Some(copy[0]), "code"), "KeyC")
  assert_eq(number(Some(copy[0]), "mods"), 4.0)
  mouse_done(r)
}

///|
test "over the picture driving it the mouse is the screen's pointer, in its shape; the station's is drawn again once it leaves" {
  let r = mouse_rig()
  r.live(others=[])
  r.state("live", others=[], more={ "cursor": { "x": 0.5, "y": 0.5, "shape": "text" } })
  assert_true(pointer_now(r.sess(), r.ui()) is Some(_))
  let (mx, my) = r.at(0.3, 0.3)
  r.t.move(mx, my)
  r.t.draw()
  assert_true(pointer_now(r.sess(), r.ui()) is None)
  assert_eq(r.t.cursor(), @ui.Cursor::IBeam)
  // up on the bar: the station's pointer drawn again
  r.t.move(mx, @sf.viewer_bar_h / 2.0)
  r.t.draw()
  assert_true(pointer_now(r.sess(), r.ui()) is Some(_))
  mouse_done(r)
}

///|
test "only looking, the mouse sends nothing and takes no keyboard" {
  let r = mouse_rig()
  r.state("live", control=false, others=[])
  r.config()
  r.frame(1000.0)
  let (mx, my) = r.at(0.5, 0.5)
  r.t.move(mx, my)
  r.tap_at(0.5, 0.5)
  r.t.wheel_with(mx, my, 0.0, 120.0, 0)
  assert_eq(r.inputs().length(), 0)
  assert_true(!r.t.key_catching())
  mouse_done(r)
}

///|
test "全屏 in 控制中心 fills the screen with the window, the bar kept; closing the screen puts it back" {
  let r = mouse_rig()
  r.live(others=[])
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  r.t.tap_text("全屏")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
  assert_true(@ui.full_screen())
  assert_true(!r.ui().full.get())
  assert_true(r.labelled(tr("common.back")) is Some(_))
  r.tap_label(tr("common.back"))
  nav_rested(r.t)
  assert_true(!@ui.full_screen())
  r.t.draw()
  mouse_done(r)
}

///|
test "an agent driving it: who drives and 接管 among the bar's tools; 接管 asks for control" {
  let r = mouse_rig()
  let agent = "Agent「修登录」"
  r.state(
    "live",
    control=false,
    others=[agent],
    controllers=[agent],
    take_over=true,
    line="只看 · \{agent} 正在控制",
  )
  r.config()
  r.frame(1000.0)
  assert_true(r.t.find("\{agent} 正在控制") is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.panel")) is None)
  r.t.tap_text("接管")
  let asked = r.told("screen.control")
  assert_eq(asked.length(), 1)
  assert_eq(field(Some(asked[0]), "control"), Some(Json::boolean(true)))
  mouse_done(r)
}

///|
test "在新窗口打开 in 控制中心 (a desktop's): the screen goes to a window of its own, which shows it alone, and leaves this one" {
  let r = mouse_rig()
  r.t.set_window_opens(true)
  r.live(others=[])
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  r.t.tap_text("在新窗口打开")
  nav_rested(r.t)
  let opened = r.t.windows_opened()
  assert_eq(opened.length(), 1)
  // what the window is started with names this screen, and reads back as it
  assert_true(
    @sfbase.window_page(opened[0]) ==
    Some(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "", until_gone: false })),
  )
  // here it is closed, its view let go of: not open twice
  assert_true(!(app.nav.top() is Screen(_)))
  r.t.draw()
  assert_true(!screens_open.contains(screen_key("ws-1/st-1", "browser:tab-1")))
  mouse_done(r)
}

///|
test "no 在新窗口打开 where the app opens no window of its own (a phone's, the web's), nor in such a window" {
  let r = mouse_rig()
  r.live(others=[])
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find("全屏") is Some(_))
  assert_true(r.t.find("在新窗口打开") is None)
  mouse_done(r)
  // a window of its own already: none from it
  let r = mouse_rig()
  r.t.set_window_opens(true)
  @sfbase.lone_page.val = Some(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "", until_gone: false }))
  r.live(others=[])
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find("全屏") is Some(_))
  assert_true(r.t.find("在新窗口打开") is None)
  assert_eq(r.t.windows_opened(), [])
  @sfbase.lone_page.val = None
  mouse_done(r)
}

///|
test "what a window of its own is started with: a station's screen and its title, read back; nothing else names a page" {
  let at : @sfbase.Page = Screen({ station: "ws-1/st-1", screen: "desktop", title: "Studio 的屏幕", until_gone: false })
  let text = @sfbase.window_text(at).unwrap()
  assert_true(@sfbase.window_page(text) == Some(at))
  assert_eq(@sfbase.window_text(Files), None)
  assert_true(@sfbase.window_page("") is None)
  assert_true(@sfbase.window_page("{\"screen\":{\"station\":\"\",\"screen\":\"desktop\"}}") is None)
  assert_true(@sfbase.window_page("{\"drive\":{}}") is None)
}
