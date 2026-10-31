// The window's zoom is reachable while a field has focus, and changes the room laid out for the same window.

///|
test "window zoom: command minus, plus and zero change and restore the whole window" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let width = t.ctx().window_size().0
  t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.ctx().window_size().0 > width)
  assert_eq(field(Some(named(calls, "prefs.set").last().unwrap().params), "windowZoom"), Some(Json::string("90")))
  t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
  t.frame()
  assert_true((t.ctx().window_size().0 - width).abs() < 0.01)
  t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.ctx().window_size().0 < width)
  t.key(@ui.key_of_char('0'), mods=@ui.mod_cmd)
  t.frame()
  assert_true((t.ctx().window_size().0 - width).abs() < 0.01)
}

///|
test "window zoom: the chat remains usable at both limits" {
  // The largest scale also crosses into the narrow layout in a smaller window.
  for (zoom, key, kept, width) in [(0.5, '-', "50", 1280.0), (2.0, '=', "200", 600.0)] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat", w=width, h=800.0, window_corner=16.0, window_inset=true)
    for _ in 0..<5 {
      t.key(@ui.key_of_char(key), mods=@ui.mod_cmd)
    }
    t.run_for(@ui.move_most_ms)
    assert_eq(@ui.window_zoom(), zoom)
    assert_eq(field(Some(named(calls, "prefs.set").last().unwrap().params), "windowZoom"), Some(Json::string(kept)))
    let saved = named(calls, "prefs.set").length()
    t.key(@ui.key_of_char(key), mods=@ui.mod_cmd)
    assert_eq(@ui.window_zoom(), zoom, msg="the shortcut stops at \{zoom}")
    assert_eq(named(calls, "prefs.set").length(), saved, msg="the limit does not save again")
    // At a narrow layout the chat peeks beside the list until it is brought over.
    if @sfdesk.wide.tape && @sfdesk.wide.tape_at.get() != @sfdesk.TapePane::Page {
      let (w, h) = t.ctx().window_size()
      t.tap(w - 20.0, h / 2.0)
      t.run_for(@ui.move_most_ms)
      assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
    }
    let faults = t.corner_faults()
    assert_true(faults.is_empty(), msg="zoom \{zoom}: \{faults}")
    guard t.boxes().iter().find_first(fn(b) { b.kind == "editor" }) is Some(editor) else { fail("no chat editor at zoom \{zoom}") }
    let (w, h) = t.ctx().window_size()
    let (x, y) = (editor.x + editor.w / 2.0, editor.y + editor.h / 2.0)
    assert_true(x >= 0.0 && x < w && y >= 0.0 && y < h, msg="the chat editor is outside the window at zoom \{zoom}")
    t.tap(x, y)
    t.type_text("第一行")
    assert_eq(t.ime().1, "第一行", msg="typing at zoom \{zoom}")
    t.key(@ui.key_of_char('0'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    assert_eq(@ui.window_zoom(), 1.0)
    assert_eq(t.ime().1, "第一行", msg="the draft survives returning to normal size")
  }
}

///|
test "window zoom: shortcuts work with search open" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let width = t.ctx().window_size().0
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfdesk.switcher_open())
  t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.ctx().window_size().0 > width)
  assert_true(@sfdesk.switcher_open())
}

///|
test "window zoom: command minus works before signing in" {
  new_run()
  let src = fixture("signin")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let width = t.ctx().window_size().0
  t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.ctx().window_size().0 > width)
}

///|
test "window zoom: the window menu changes the size" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let width = t.ctx().window_size().0
  @settings.ask_action("zoom.in")
  t.frame()
  t.frame()
  assert_true(t.ctx().window_size().0 < width)
}

///|
test "window zoom: the appearance picker changes and restores the window" {
  let t = settings_tester("appearance")
  let width = t.ctx().window_size().0
  t.tap_text("100%")
  t.tap_text("125%")
  t.frame()
  assert_true(t.ctx().window_size().0 < width)
  // At a later moment the sheet has gone; enlarging puts the setting below this window's visible part.
  t.frame_at(t.time() + @ui.move_most_ms)
  let (w, h) = t.ctx().window_size()
  t.move(w / 2.0, h / 2.0)
  for _ in 0..<10 {
    match t.find("125%") {
      Some((_, y)) if y > 90.0 && y < h - 80.0 => break
      Some((_, y)) if y <= 90.0 => t.wheel(w / 2.0, h / 2.0, -300.0)
      _ => t.wheel(w / 2.0, h / 2.0, 300.0)
    }
  }
  let (_, y) = t.find("125%").unwrap()
  assert_true(y > 90.0 && y < h - 80.0, msg="zoom choice is not visible: \{y} in \{h}")
  t.tap_text("125%")
  t.tap_text("100%")
  t.frame()
  assert_true((t.ctx().window_size().0 - width).abs() < 0.01, msg="requested \{@ui.window_zoom()}, width \{t.ctx().window_size().0}, expected \{width}")
}

///|
test "window zoom: control minus and plus work with a focused field on Windows" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", platform=3)
  let width = t.ctx().window_size().0
  t.key(@ui.key_of_char('-'), mods=@ui.mod_ctrl)
  t.frame()
  assert_true(t.ctx().window_size().0 > width)
  t.key(@ui.key_of_char('='), mods=@ui.mod_ctrl | @ui.mod_shift_key)
  t.frame()
  assert_true((t.ctx().window_size().0 - width).abs() < 0.01)
}

///|
test "window zoom: command plus works while recording a different shortcut only after recording ends" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let width = t.ctx().window_size().0
  @settings.keys_recording.val = "chat.new"
  t.key(@ui.key_of_char('+'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.frame()
  assert_true((t.ctx().window_size().0 - width).abs() < 0.01)
  @settings.keys_recording.val = ""
  t.key(@ui.key_of_char('+'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.frame()
  assert_true(t.ctx().window_size().0 < width)
}

///|
test "window zoom: the system's window buttons keep their space at the smallest size" {
  for width in [390.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat", w=width, window_inset=true)
    for _ in 0..<5 {
      t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd)
    }
    t.frame()
    let z = @ui.window_zoom()
    assert_true((z - 0.5).abs() < 0.001)
    let sem = t.semantics()
    for i, s in sem {
      let control = s.role is (Button | Link | Tab | Switch | Checkbox | Radio | TextField | Combobox | MenuItem | Slider | Option | Separator)
      // A scrolling list can itself take presses and be inferred as a button around its own buttons. Its bounds do
      // not describe a visible control; check its actual child controls rather than the container.
      let has_controls = sem.iter().any(fn(child) {
        child.parent == i && child.role is (Button | Link | Tab | Switch | Checkbox | Radio | TextField | Combobox | MenuItem | Slider | Option | Separator)
      })
      if !s.hidden && control && s.label != "" && !has_controls {
        let (x, y, w, h) = s.rect
        // AppKit's controls sit 16 points from the left, centred in a 44-point top row.
        let overlaps = x * z < 76.0 && (x + w) * z > 16.0 && y * z < 29.0 && (y + h) * z > 15.0
        assert_false(overlaps, msg="\{width}: \{s.label} at \{x * z},\{y * z} \{w * z}x\{h * z} is under the system's window buttons")
      }
    }
  }
}

///|
test "window zoom: window corners stay consistent at every size" {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(
    fn(c) { view(c, src) },
    tree=app_tree(src),
    w=1280.0,
    h=800.0,
    platform=0,
    window_corner=16.0,
    window_inset=true,
    corners_held=false,
  )
  open_setting("appearance")
  t.draw()
  t.frame_at(t.time() + @ui.move_most_ms)
  let faults : Array[String] = []
  for _ in 0..<5 {
    t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd)
    t.frame_at(t.time() + @ui.move_most_ms)
    for f in t.corner_faults() { faults.push("\{@ui.window_zoom()}: \{f}") }
  }
  for _ in 0..<10 {
    t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
    t.frame_at(t.time() + @ui.move_most_ms)
    for f in t.corner_faults() { faults.push("\{@ui.window_zoom()}: \{f}") }
  }
  assert_true(faults.is_empty(), msg=faults.join("\n"))
}

///|
test "window zoom: the panel at the window edge keeps following its corner when enlarged" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, window_corner=16.0, window_inset=true)
  for _ in 0..<4 { t.key(@ui.key_of_char('='), mods=@ui.mod_cmd) }
  for _ in 0..<2 {
    t.run_for(@ui.move_most_ms)
    let zoom = @ui.window_zoom()
    assert_true(@sfdesk.wide.tape, msg="\{zoom}: expected the panel layout")
    guard composer_and_panel(t) is Some((_, page)) else { fail("\{zoom}: no chat panel") }
    let edge = @ui.concentric(16.0 / zoom, @sf.window_in)
    assert_true(
      (page.radii.1 - edge).abs() < 0.01 && (page.radii.2 - edge).abs() < 0.01,
      msg="\{zoom}: the panel's right corners \{page.radii} should follow the window at \{edge}",
    )
    t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
  }
}

///|
test "window zoom: sharing controls stay clear of the window's corners" {
  let t = screen_in("chat-publish", ("zoom", 600.0, 800.0, 0, ""), "zh")
  t.set_window_inset(true)
  let faults : Array[String] = []
  for _ in 0..<2 {
    t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    for f in t.corner_faults() { faults.push("\{@ui.window_zoom()}: \{f}") }
  }
  assert_true(faults.is_empty(), msg=faults.join("\n"))
}

///|
test "sharing controls keep clear of each different bottom corner" {
  let src : Ref[Source?] = Ref(None)
  let made = fn() {
    match src.val {
      Some(s) => s
      None => {
        let s = fixture_app("chat-publish")
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(
    fn(c) { view(c, made()) },
    tree=fn(root) { app_tree(made())(root) },
    w=390.0,
    h=844.0,
    platform=1,
    window_corners=FixedArray::from_array([0.0, 0.0, 8.0, 59.0]),
    env=[("MBUI_LOCALE", "zh"), ("MBUI_REDUCE_MOTION", "1")],
    corners_held=false,
  )
  t.run_for(squeeze_opening)
  guard t.query(Button, label="取消") is Some(cancel) else { fail("no cancel button") }
  guard t.query(Button, label="保存到相册") is Some(save) else { fail("no save button") }
  let (left, _, _, _) = cancel.rect
  let (right, _, width, _) = save.rect
  assert_true(left >= 63.0, msg="cancel is beside the larger corner at \{left}")
  assert_true((390.0 - (right + width) - 16.0).abs() < 0.5, msg="save moved away from the smaller corner")
}

///|
test "window zoom: the chat's bar stays clear of the window corner when its controls shrink" {
  let t = screen_in("chat", ("zoom", 1280.0, 800.0, 0, ""), "zh")
  t.set_window_inset(true)
  for _ in 0..<5 { t.key(@ui.key_of_char('-'), mods=@ui.mod_cmd) }
  t.run_for(@ui.move_most_ms)
  assert_true((@ui.window_zoom() - 0.5).abs() < 0.001)
  // The button's ground appears under the pointer; check that drawn shape, not only its idle icon.
  guard t.query(Button, label="打开侧栏") is Some(key) else { fail("no sidebar button") }
  let (x, y, w, h) = key.rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(t.corner_faults(), [])
}

///|
test "window zoom: a short rail keeps settings visible and scrolls its places" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, window_corner=16.0, window_inset=true)
  for _ in 0..<4 { t.key(@ui.key_of_char('='), mods=@ui.mod_cmd) }
  t.frame_at(t.time() + @ui.move_most_ms)
  assert_true((@ui.window_zoom() - 1.75).abs() < 0.001)
  let gear = t.query(Button, label=@sf.t("web-pages.settings.title")).unwrap().rect
  let (_, height) = t.ctx().window_size()
  assert_true(gear.1 >= 0.0 && gear.1 + gear.3 <= height, msg="settings is outside the window: \{gear}")
  let before = t.query(Button, label="文件").unwrap().rect
  t.wheel(before.0 + before.2 / 2.0, before.1 + before.3 / 2.0, 300.0)
  t.frame_at(t.time() + @ui.move_most_ms)
  let after = t.query(Button, label="文件").unwrap().rect
  assert_true(after.1 < before.1, msg="places did not scroll: \{before} → \{after}")
  assert_eq(t.query(Button, label=@sf.t("web-pages.settings.title")).unwrap().rect, gear)
}
