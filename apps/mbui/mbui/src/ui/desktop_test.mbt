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
      c.clicked(link) |> ignore
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
test "desktop: what takes presses is a hand by itself; not what is off, a ground, what only watches or looks pressed" {
  let t = @ui.Tester::new(
    fn(c) {
      let button = c.id("button")
      let slider = c.id("slider")
      let off = c.id("off")
      let tipped = c.id("tipped")
      let ground = c.id("ground")
      let look = c.id("look")
      c.clicked(button) |> ignore
      c.takes_presses(slider)
      c.pressed(slider) |> ignore
      c.interact(off, disabled=true) |> ignore
      c.watch_press(tipped) |> ignore
      c.clicked(ground) |> ignore
      c.cursor(ground, Arrow)
      c.pressed(look) |> ignore
      c.column(w=Fill(1.0), fn() {
        for id in [button, slider, off, tipped, ground, look] {
          c.box(id~, w=Px(100.0), h=Px(30.0), fn() {  }) |> ignore
        }
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let seen = [15.0, 45.0, 75.0, 105.0, 135.0, 165.0].map(fn(y) {
    t.move(10.0, y)
    t.cursor()
  })
  assert_eq(seen, [Hand, Hand, Arrow, Arrow, Arrow, Arrow])
}

///|
test "desktop: a link in words picked with the pointer is a hand, the words round it the I-beam" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), fn() {
        c.selectable(fn() {
          c.rich([@ui.link("open", "https://example.com"), @ui.plain(" and the words after it")], size=15.0)
          |> ignore
        })
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (x, y, w, h) = t.rect_of("open and the words after it").unwrap()
  t.move(x + 3.0, y + h / 2.0)
  assert_eq(t.cursor(), Hand)
  t.move(x + w - 3.0, y + h / 2.0)
  assert_eq(t.cursor(), IBeam)
}

///|
test "desktop: a ground that takes presses keeps the I-beam over its words picked with the pointer" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      let ground = c.id("ground")
      c.clicked(ground) |> ignore
      c.cursor(ground, Arrow)
      c.box(id=ground, w=Fill(1.0), pad=40.0, fn() {
        c.selectable(fn() { c.rich([@ui.plain("words on a ground")], size=15.0) |> ignore })
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (x, y, _, h) = t.rect_of("words on a ground").unwrap()
  t.move(x + 3.0, y + h / 2.0)
  assert_eq(t.cursor(), IBeam)
  t.move(10.0, 10.0)
  assert_eq(t.cursor(), Arrow)
}

///|
test "desktop: what moves under a resting pointer is what it hovers" {
  let shift = Ref(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      let a = c.id("a")
      c.clicked(a) |> ignore
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
  let rest = Ref(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(drags.val)
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
  // a moment into its ease
  t.run_for(@ui.wheel_ease_ms)
  let first = t.list_offset()
  assert_true(first > 0.0 && first < 120.0)
  // to the list's rest: its ease come (and its scroll bar gone)
  t.run_for(rest.val - t.time())
  assert_eq(t.list_offset(), 120.0)
  // a trackpad's: there as it is taken
  t.wheel_phase(150.0, 200.0, 40.0, 0)
  assert_eq(t.list_offset(), 160.0)
  drags.val = false
  t.draw()
  t.drag(150.0, 300.0, 150.0, 100.0)
  assert_eq(t.list_offset(), 160.0)
  t.run_for(rest.val - t.time())
  t.assert_idle()
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
      c.clicked(row) |> ignore
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
test "desktop: with a field focused, words picked with the pointer are what ⌘C copies; picking them lets go of the field's" {
  let f = @ui.Field::new(text="draft words")
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), fn() {
        c.editor("e", field=f, font_size=10.0) |> ignore
        c.box(h=Px(40.0), fn() {  }) |> ignore
        // (in a row of its own, as a chat's message is: a press on it is the row's, which leaves the field its focus)
        c.selectable(fn() {
          c.box(id=c.id("row"), fn() { c.rich([@ui.plain("hello wide world")], size=15.0) |> ignore }) |> ignore
        })
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  t.tap(14.0, 14.0)
  t.key(@ui.key_code_select_all, mods=@ui.mod_cmd)
  assert_eq(f.selection(), (0, 11))
  let (_, y, _, h) = t.rect_of("hello wide world").unwrap()
  t.drag(1.0, y + h / 2.0, 200.0, y + h / 2.0)
  // the field keeps the focus, what it had picked let go of
  assert_true(t.ctx().editor_focused("e"))
  assert_eq(f.selection(), (11, 11))
  assert_eq(t.ctx().selected_text(), "hello wide world")
  assert_true((t.edit_can() & @hostapi.text_menu_copy) != 0)
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  assert_eq(t.clipboard(), "hello wide world")
  // words picked in the field again: theirs
  t.key(@ui.key_code_select_all, mods=@ui.mod_cmd)
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  assert_eq(t.clipboard(), "draft words")
}

///|
test "desktop: a press on what keeps the words picked (a quote of them) leaves them picked; a press elsewhere lets them go" {
  let pressed = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), fn() {
        c.selectable(fn() {
          c.rich([@ui.plain("hello wide world")], size=15.0) |> ignore
          let id = c.id("quote")
          if c.clicked(id) {
            pressed.val += 1
          }
          c.keeps_selection(id)
          c.box(w=Px(60.0), h=Px(30.0), id~, fn() { c.text("quote", wrap=false) |> ignore }) |> ignore
        })
        c.box(h=Px(40.0), fn() {  }) |> ignore
        c.rich([@ui.plain("not this one")], size=15.0) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (_, y, _, h) = t.rect_of("hello wide world").unwrap()
  t.drag(1.0, y + h / 2.0, 200.0, y + h / 2.0)
  assert_eq(t.ctx().selected_text(), "hello wide world")
  let (qx, qy, qw, qh) = t.rect_of("quote").unwrap()
  t.tap(qx + qw / 2.0, qy + qh / 2.0)
  t.draw()
  assert_eq(pressed.val, 1)
  assert_eq(t.ctx().selected_text(), "hello wide world")
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

///|
test "desktop: two clicks on the same thing within double_click_ms are a double click; slower, two clicks" {
  let clicks : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let id = c.id("thing")
      c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
      if c.clicked(id) {
        clicks.push("click")
      }
      if c.double_clicked(id) {
        clicks.push("double")
      }
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.tap(20.0, 20.0)
  t.tap(20.0, 20.0)
  assert_eq(clicks, ["click", "click", "double"])
  clicks.clear()
  t.run_for(@ui.double_click_ms + 100.0)
  t.tap(20.0, 20.0)
  t.run_for(@ui.double_click_ms + 100.0)
  t.tap(20.0, 20.0)
  assert_eq(clicks, ["click", "click"])
}

///|
test "desktop: what the person points with is the system's: a finger on a phone's or a tablet's, at any width" {
  let view = fn(c : @ui.Ctx) { c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }
  for p in [(0, @ui.Mouse), (3, @ui.Mouse), (1, @ui.Finger), (2, @ui.Finger)] {
    let (platform, hand) = p
    for w in [390.0, 1400.0] {
      let _ = @ui.Tester::new(view, w~, platform~)
      assert_eq(@ui.pointing(), hand)
    }
  }
}

///|
test "desktop: a Tester told the hand plays it on the system it says, which stays that system" {
  let view = fn(c : @ui.Ctx) { c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }
  // a run made on a desktop by a finger (a phone's layout's), replayed so: its core told it was on a desktop
  let _ = @ui.Tester::new(view, platform=0, pointing=Finger)
  assert_eq(@ui.pointing(), @ui.Finger)
  assert_eq(@ui.platform(), 0)
  let _ = @ui.Tester::new(view, platform=2, pointing=Mouse)
  assert_eq(@ui.pointing(), @ui.Mouse)
  assert_eq(@ui.platform(), 2)
}

///|
test "desktop: a finger hovers over nothing, and lifted it is nowhere; a mouse hovers where it rests" {
  let seen : Ref[String] = { val: "" }
  let tapped_at : Array[Int] = []
  let view = fn(c : @ui.Ctx) {
    let b = c.id("b")
    let (px, _, _) = c.pointer()
    // (the frame that sees the tap still reads where it was: what the tap opens there)
    if c.clicked(b) {
      tapped_at.push(px.to_int())
    }
    seen.val = "\{c.hovered(b)} \{px >= 0.0}"
    c.box(id=b, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(view, platform=2)
  t.touch(0, 20.0, 20.0)
  t.touch(1, 22.0, 20.0)
  t.draw()
  assert_eq(seen.val, "false true")
  t.touch(2, 22.0, 20.0)
  t.draw()
  assert_eq(tapped_at, [22])
  assert_eq(seen.val, "false false")
  let t = @ui.Tester::new(view, platform=0)
  t.move(20.0, 20.0)
  t.draw()
  assert_eq(seen.val, "true true")
}

///|
test "desktop: a menu is asked for by a mouse's right click, by a finger held still" {
  let asked : Array[String] = []
  let clicks : Array[String] = []
  let view = fn(c : @ui.Ctx) {
    let row = c.id("row")
    if c.menu_asked(row) is Some((x, _)) {
      asked.push("menu at \{x.to_int()}")
    }
    if c.clicked(row) {
      clicks.push("click")
    }
    c.box(id=row, w=Px(300.0), h=Px(40.0), fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(view, platform=2)
  t.press_at(50.0, 20.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(50.0, 20.0)
  assert_eq(asked, ["menu at 50"])
  assert_eq(clicks, [])
  asked.clear()
  // a mouse held is a press, not a menu; its right click is
  let t = @ui.Tester::new(view, platform=0)
  t.press_at(50.0, 20.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(50.0, 20.0)
  assert_eq(asked, [])
  t.right_click(80.0, 20.0)
  assert_eq(asked, ["menu at 80"])
}

///|
test "desktop: a finger held still asks for the menu once, though what the menu opens builds the frame again" {
  let asked : Array[String] = []
  let view = fn(c : @ui.Ctx) {
    let row = c.id("row")
    if c.menu_asked(row) is Some(_) {
      asked.push("menu")
      // (what opening it changes, as a sheet coming up does: the frame built again, which sees no more of the hold)
      c.built_from_changed("menu")
    }
    c.box(id=row, w=Px(300.0), h=Px(40.0), fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(view, platform=2)
  t.press_at(50.0, 20.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(50.0, 20.0)
  assert_eq(asked, ["menu"])
}

///|
test "desktop: a finger reaches a target smaller than a fingertip from round it, not its neighbour's; a mouse does not" {
  let clicks : Array[String] = []
  let view = fn(c : @ui.Ctx) {
    let row = c.id("row")
    let a = c.id("a")
    let b = c.id("b")
    for p in [("row", row), ("a", a), ("b", b)] {
      if c.clicked(p.1) {
        clicks.push(p.0)
      }
    }
    // a row 300 by 60, two 20 by 20 buttons in it 4 apart at its end
    c.box(id=row, w=Px(300.0), h=Px(60.0), dir=Row, align=ACenter, pl=240.0, gap=4.0, fn() {
      c.box(id=a, w=Px(20.0), h=Px(20.0), fn() {  }) |> ignore
      c.box(id=b, w=Px(20.0), h=Px(20.0), fn() {  }) |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(view, platform=2)
  // 10 over the first button (at 240..260, 20..40): its own
  t.tap(250.0, 12.0)
  // on the first, by its edge nearest the second: the first keeps it
  t.tap(259.0, 30.0)
  // between them, nearer the second
  t.tap(263.5, 30.0)
  // far from both: the row's
  t.tap(100.0, 30.0)
  assert_eq(clicks, ["a", "a", "b", "row"])
  clicks.clear()
  let t = @ui.Tester::new(view, platform=0)
  t.tap(250.0, 12.0)
  assert_eq(clicks, ["row"])
}

///|
test "desktop: lit by the hand on it: a mouse resting on it, a finger pressing it (and nothing once lifted)" {
  let lit : Ref[Bool] = { val: false }
  let view = fn(c : @ui.Ctx) {
    let b = c.id("b")
    lit.val = c.lit(b)
    c.box(id=b, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(view, platform=2)
  t.press_at(20.0, 20.0)
  t.draw()
  assert_true(lit.val)
  t.release(20.0, 20.0)
  t.draw()
  assert_false(lit.val)
  let t = @ui.Tester::new(view, platform=0)
  t.move(20.0, 20.0)
  t.draw()
  assert_true(lit.val)
}

///|
test "a field leaving keys to the app: ↑ keeps its caret, Enter sends nothing; the app still reads them" {
  let f = @ui.Field::new(text="one\ntwo")
  let leaves : Ref[Array[Int]] = Ref::new([])
  let up = Ref::new(false)
  let enter = Ref::new(false)
  let sent : Ref[String?] = Ref::new(None)
  let t = @ui.Tester::new(fn(c) {
    let r = c.editor("e", field=f, leaves=leaves.val)
    if r.submitted is Some(_) {
      sent.val = r.submitted
    }
    if c.key_pressed(@ui.key_code_up, in_field=true) {
      up.val = true
    }
    if c.key_pressed(@ui.key_code_enter, in_field=true) {
      enter.val = true
    }
  })
  t.draw()
  t.tap(100.0, 20.0)
  f.set("one\ntwo", caret=7)
  leaves.val = [@ui.key_code_up, @ui.key_code_down, @ui.key_code_enter]
  t.draw()
  t.key(@ui.key_code_up)
  assert_eq(f.selection(), (7, 7))
  assert_true(up.val)
  t.key(@ui.key_code_enter)
  assert_true(enter.val)
  assert_eq(sent.val, None)
  assert_eq(f.text(), "one\ntwo")
  // Tab too: the focus stays in the field
  leaves.val = [@ui.key_tab]
  t.draw()
  t.key(@ui.key_tab)
  assert_true(t.ctx().editor_focused("e"))
  // given back: ↑ goes up a line
  leaves.val = []
  t.draw()
  t.key(@ui.key_code_up)
  assert_true(f.selection().1 < 4)
}

///|
test "desktop: one right click, one menu: the innermost asker's under it (a row's, not its list's, though the list asks first)" {
  let menus : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let list = c.id("list")
      let row = c.id("row")
      c.box(id=list, w=Px(300.0), h=Px(200.0), fn() {
        // (the list asks before its row is built, as a list's box does before it lays its rows out)
        if c.menu_asked(list) is Some(_) {
          menus.push("list")
        }
        c.box(id=row, w=Px(300.0), h=Px(40.0), fn() {  }) |> ignore
        if c.menu_asked(row) is Some(_) {
          menus.push("row")
        }
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  t.right_click(20.0, 20.0)
  assert_eq(menus, ["row"])
  menus.clear()
  // under the row, the list's alone
  t.right_click(20.0, 120.0)
  assert_eq(menus, ["list"])
}

///|
test "desktop: a right click is on what a press there is on: not on what lies under a layer over it (its panel, its ground)" {
  let menus : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let row = c.id("row")
      let panel = c.id("panel")
      if c.menu_asked(row) is Some(_) {
        menus.push("row")
      }
      if c.right_clicked(panel) is Some(_) {
        menus.push("panel")
      }
      c.box(id=row, w=Px(400.0), h=Px(300.0), fn() {  }) |> ignore
      // a menu open over it: its panel, its ground over all the rest
      c.overlay("menu", modal=true, fn() {
        c.box(tx=100.0, ty=100.0, w=Px(180.0), h=Px(80.0), id=panel, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  // on the menu's panel: its, not the row's under it (a second menu of the row's over the first)
  t.right_click(150.0, 120.0)
  assert_eq(menus, ["panel"])
  menus.clear()
  // on its ground: nobody's
  t.right_click(20.0, 250.0)
  assert_eq(menus, [])
}
