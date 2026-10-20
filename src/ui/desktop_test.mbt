///|
test "desktop: a right click is the row's and the button's under it, and presses nothing" {
  let menus : Array[String] = []
  let clicks : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let row = c.id("row")
      let button = c.id("button")
      if c.right_clicked(row) is Some(_) {
        menus.push("row")
      }
      if c.right_clicked(button) is Some((x, _)) {
        menus.push("button at \{x.to_int()}")
      }
      if c.clicked(row) || c.clicked(button) {
        clicks.push("click")
      }
      c.box(id=row, w=Px(300.0), h=Px(40.0), dir=Row, fn() {
        c.spacer()
        c.box(id=button, w=Px(40.0), h=Px(40.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.right_click(280.0, 20.0)
  assert_eq(menus, ["row", "button at 280"])
  assert_eq(clicks, [])
  menus.clear()
  t.right_click(20.0, 20.0)
  assert_eq(menus, ["row"])
  t.tap(20.0, 20.0)
  assert_eq(clicks, ["click"])
}

///|
test "desktop: the pointer's shape follows what is under it, and the arrow once it leaves" {
  let t = @ui.Tester::new(
    fn(c) {
      let link = c.id("link")
      c.cursor(link, Hand)
      c.column(w=Fill(1.0), fn() {
        c.box(id=link, w=Px(100.0), h=Px(30.0), fn() {  }) |> ignore
        c.editor("field", placeholder="words") |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.move(10.0, 10.0)
  assert_eq(t.cursor(), Hand)
  let (fx, fy) = t.find("words").unwrap()
  t.move(fx, fy)
  assert_eq(t.cursor(), IBeam)
  t.leave()
  assert_eq(t.cursor(), Arrow)
}

///|
test "desktop: what moves under a resting pointer is what it hovers" {
  let shift = Ref(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      let a = c.id("a")
      c.cursor(a, Hand)
      c.box(pt=shift.val, fn() { c.box(id=a, w=Px(50.0), h=Px(20.0), fn() {  }) |> ignore })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.move(10.0, 50.0)
  assert_eq(t.cursor(), Arrow)
  shift.val = 40.0
  t.frame()
  t.frame()
  assert_eq(t.cursor(), Hand)
}

///|
test "desktop: keys with the command key are shortcuts; Escape reaches the app with a field focused" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      if c.shortcut('k') {
        seen.push("cmd-k")
      }
      if c.key_pressed(@ui.key_escape) {
        seen.push("esc")
      }
      if c.key_pressed(@ui.key_code_enter) {
        seen.push("enter")
      }
      c.editor("field", placeholder="words") |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  // Ctrl+K is not macOS's shortcut
  t.key(@ui.key_of_char('k'), mods=@ui.mod_ctrl)
  let (fx, fy) = t.find("words").unwrap()
  t.tap(fx, fy)
  t.key(@ui.key_escape)
  // the field's Enter is the field's
  t.key(@ui.key_code_enter)
  assert_eq(seen, ["cmd-k", "esc"])
}

///|
test "desktop: a press on the app's own title row drags the window and presses nothing there" {
  let clicks = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      let top = c.id("top")
      c.window_drag(top)
      if c.clicked(top) {
        clicks.val = clicks.val + 1
      }
      c.box(id=top, w=Fill(1.0), h=Px(44.0), fn() {  }) |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.tap(100.0, 20.0)
  assert_eq(t.window_drags(), 1)
  assert_eq(clicks.val, 0)
}

///|
test "desktop: a wheel's notch is eased in, a trackpad's at once; the mouse drags no list when told" {
  let drags = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(drags.val)
      c.list("l", 100, 40.0, fn(i) {
        c.box(h=Px(40.0), fn() { c.text("row \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.wheel_phase(150.0, 200.0, 120.0, 4)
  // a moment into its ease
  t.run_for(@ui.wheel_ease_ms)
  let first = t.list_offset()
  assert_true(first > 0.0 && first < 120.0)
  t.settle() |> ignore
  assert_eq(t.list_offset(), 120.0)
  t.wheel_phase(150.0, 200.0, 40.0, 0)
  t.settle() |> ignore
  assert_eq(t.list_offset(), 160.0)
  drags.val = false
  t.frame()
  t.drag(150.0, 300.0, 150.0, 100.0)
  t.settle() |> ignore
  assert_eq(t.list_offset(), 160.0)
}

///|
test "desktop: a pane's rows are built for the pane's size" {
  let widths : Array[Double] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.sized(300.0, 200.0, fn() {
        c.list("l", 1, 40.0, fn(_) {
          widths.push(c.width)
          c.box(h=Px(40.0), fn() {  }) |> ignore
        })
        |> ignore
      })
    },
    w=800.0,
    h=600.0,
  )
  ignore(t)
  assert_true(widths.length() > 0)
  assert_true(widths.iter().all(fn(w) { w == 300.0 }))
}

///|
test "desktop: a script hovers, right clicks, presses keys and resizes the window" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let row = c.id("row")
      c.cursor(row, Hand)
      if c.right_clicked(row) is Some(_) {
        seen.push("menu")
      }
      if c.shortcut('k') {
        seen.push("cmd-k")
      }
      if c.key_pressed(@ui.key_code_down, mods=@ui.mod_alt) {
        seen.push("alt-down")
      }
      seen.push("w \{c.width.to_int()}")
      c.box(id=row, fn() { c.text("a row", wrap=false) |> ignore }) |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  seen.clear()
  let logs = t.drive("hover a row\nrightclick a row\nkey cmd+k\nkey alt+down\nresize 900 700\nwait 50\nexit")
  assert_true(logs.iter().any(fn(l) { l.contains("DRIVE PASS") }))
  assert_eq(t.cursor(), Hand)
  assert_true(seen.contains("menu"))
  assert_true(seen.contains("cmd-k"))
  assert_true(seen.contains("alt-down"))
  assert_true(seen.contains("w 900"))
}

///|
test "desktop: words of a selectable paragraph are picked by a drag and copied; a press elsewhere lets them go" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), fn() {
        c.selectable(fn() { c.rich([@ui.plain("hello wide world")], size=15.0) |> ignore })
        c.box(h=Px(40.0), fn() {  }) |> ignore
        c.rich([@ui.plain("not this one")], size=15.0) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (_, y, _, h) = t.rect_of("hello wide world").unwrap()
  t.move(2.0, y + h / 2.0)
  assert_eq(t.cursor(), IBeam)
  t.drag(1.0, y + h / 2.0, 200.0, y + h / 2.0)
  assert_eq(t.ctx().selected_text(), "hello wide world")
  t.key(13, mods=8)
  assert_eq(t.clipboard(), "hello wide world")
  let (_, y2, _, h2) = t.rect_of("not this one").unwrap()
  t.tap(10.0, y2 + h2 / 2.0)
  assert_eq(t.ctx().selected_text(), "")
}

///|
/// A list eased in by a wheel's notch of 120 at its start (desktop: the mouse's wheel).
fn notched(rest? : Ref[Double] = Ref(0.0)) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      c.list("l", 100, 40.0, fn(i) {
        c.box(h=Px(40.0), fn() { c.text("row \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
      rest.val = c.list_rest("l")
    },
    w=300.0,
    h=400.0,
  )
  t.wheel_phase(150.0, 200.0, 120.0, 4)
  t
}

///|
test "a wheel's ease is solved for the time: in frames of 16 ms, of 8, or at once, the same to the bit" {
  // a moment into its ease, and two frame lengths to go there by
  let at = @ui.wheel_ease_ms * 1.5
  let long_frame = @ui.drag_step_ms
  let short_frame = @ui.drag_step_ms / 2.0
  let sixteen = notched()
  let eight = notched()
  let rest = Ref(0.0)
  let once = notched(rest~)
  let start = sixteen.time()
  while sixteen.time() + long_frame <= start + at {
    sixteen.frame(ms=long_frame)
  }
  sixteen.frame(ms=start + at - sixteen.time())
  while eight.time() + short_frame <= start + at {
    eight.frame(ms=short_frame)
  }
  eight.frame(ms=start + at - eight.time())
  once.frame(ms=at)
  assert_true(once.list_offset() > 0.0 && once.list_offset() < 120.0)
  assert_eq(sixteen.list_offset(), once.list_offset())
  assert_eq(eight.list_offset(), once.list_offset())
  // its scroll bar shows while it moves and after, then fades: what moves until it is gone (the list's own rest), then
  // nothing
  // (its end goes on while the ease scrolls it: run to it until it is where it is)
  while rest.val > once.time() {
    once.run_for(rest.val - once.time())
  }
  once.assert_idle()
}
