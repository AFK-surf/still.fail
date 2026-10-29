///|
/// A plain button for these tests: its words, an id from them, Enter and Space (or `keys`) pressing it.
fn btn(c : Ctx, label : String, keys? : Int = 3, w? : Size = Auto) -> Response {
  let id = c.id(label)
  let r = c.interact(id, keys~)
  let i = c.box(w~, padx=8.0, pady=4.0, id~, fn() { c.text(label, wrap=false) |> ignore })
  c.semantics(i, Button, id~, actions=[Activate])
  r
}

///|
test "Tab goes through what can take the focus in the order it is built, round; Shift+Tab back" {
  let t = Tester::new(fn(c) {
    c.column(gap=4.0, fn() {
      btn(c, "one") |> ignore
      btn(c, "two") |> ignore
      btn(c, "three") |> ignore
    })
    |> ignore
  })
  assert_true(t.focused() is None)
  t.tab()
  assert_eq(t.focused().unwrap().label, "one")
  t.tab()
  t.tab()
  assert_eq(t.focused().unwrap().label, "three")
  t.tab()
  assert_eq(t.focused().unwrap().label, "one")
  t.tab(back=true)
  assert_eq(t.focused().unwrap().label, "three")
}

///|
test "Enter and Space press what has the focus, as it says; the key is taken from the view" {
  let log : Array[String] = []
  let seen_enter = Ref(0)
  let t = Tester::new(fn(c) {
    if c.key_pressed(key_code_enter) {
      seen_enter.val = seen_enter.val + 1
    }
    c.column(fn() {
      if btn(c, "both").clicked {
        log.push("both")
      }
      if btn(c, "space only", keys=press_space).clicked {
        log.push("space only")
      }
    })
    |> ignore
  })
  t.tab()
  t.press("Enter")
  t.press("Space")
  assert_eq(log, ["both", "both"])
  assert_eq(seen_enter.val, 0)
  t.tab()
  t.press("Enter")
  assert_eq(log, ["both", "both"])
  // not taken by it: the view sees it
  assert_eq(seen_enter.val, 1)
  t.press("Space")
  assert_eq(log, ["both", "both", "space only"])
}

///|
test "the focus shows only when it came by the keyboard; a press lets it go from a button, not from a field" {
  let shown = Ref(false)
  let t = Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      let r = btn(c, "button")
      shown.val = r.focus_shown
      c.editor("field", placeholder="type here") |> ignore
      btn(c, "send") |> ignore
    })
    |> ignore
  })
  t.tab()
  assert_true(shown.val)
  // a tap on it: no ring (it came by the pointer); a tap on nothing: the focus let go
  t.click(Button, label="button")
  assert_false(shown.val)
  t.tap(300.0, 600.0)
  assert_true(t.focused() is None)
  // a field takes the focus on a press, and keeps it when a button beside it is tapped
  t.tap_text("type here")
  assert_eq(t.focused().unwrap().role, TextField)
  t.click(Button, label="send")
  assert_eq(t.focused().unwrap().role, TextField)
  // Tab from the field goes on to the button after it
  t.tab()
  assert_eq(t.focused().unwrap().label, "send")
}

///|
test "a roving group is one stop for Tab; the arrows move in it, round, Home and End to its ends" {
  let t = Tester::new(fn(c) {
    c.column(fn() {
      btn(c, "before") |> ignore
      c.roving("group", orientation=Horizontal, current=c.id("b"), fn() {
        c.row(fn() {
          btn(c, "a") |> ignore
          btn(c, "b") |> ignore
          btn(c, "c") |> ignore
        })
        |> ignore
      })
      btn(c, "after") |> ignore
    })
    |> ignore
  })
  t.tab()
  t.tab()
  // the stop it says while none has been focused
  assert_eq(t.focused().unwrap().label, "b")
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "c")
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "a")
  t.press("Left")
  assert_eq(t.focused().unwrap().label, "c")
  t.press("Home")
  assert_eq(t.focused().unwrap().label, "a")
  // Up and Down are not a horizontal group's
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "a")
  t.tab()
  assert_eq(t.focused().unwrap().label, "after")
  // back in: where it was left
  t.tab(back=true)
  assert_eq(t.focused().unwrap().label, "a")
  t.press("End")
  t.tab(back=true)
  assert_eq(t.focused().unwrap().label, "before")
}

///|
test "right to left, a row runs from the right and Left and Right swap in a group" {
  let t = Tester::new(fn(c) {
    c.with_direction(Rtl, fn() {
      c.roving("group", orientation=Horizontal, fn() {
        c.box(dir=Row, pl=10.0, fn() {
          btn(c, "first") |> ignore
          btn(c, "second") |> ignore
        })
        |> ignore
      })
    })
  })
  let (x1, _, w1, _) = t.get(Button, label="first").rect
  let (x2, _, _, _) = t.get(Button, label="second").rect
  assert_true(x2 < x1)
  // the start padding is the right one
  assert_eq(x1 + w1, 390.0 - 10.0)
  t.tab()
  assert_eq(t.focused().unwrap().label, "first")
  t.press("Left")
  assert_eq(t.focused().unwrap().label, "second")
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "first")
}

///|
test "held long: long_pressed once, and no click when let go" {
  let log : Array[String] = []
  let t = Tester::new(fn(c) {
    let r = btn(c, "hold me")
    if r.long_pressed {
      log.push("long")
    }
    if r.clicked {
      log.push("click")
    }
  })
  let (x, y, w, h) = t.get(Button, label="hold me").rect
  // (held from the moment the finger went down: the press's own time)
  let pressed = t.time()
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.draw()
  let due = pressed + long_press_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_eq(log, [])
  t.run_for(due - t.time())
  assert_eq(log, ["long"])
  // held on as long again: still once
  t.run_for(long_press_ms)
  assert_eq(log, ["long"])
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(log, ["long"])
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(log, ["long", "click"])
}

///|
test "an action asked of a node comes to its widget as input: Activate is a click, Focus the focus" {
  let n = Ref(0)
  let t = Tester::new(fn(c) {
    c.column(fn() {
      btn(c, "other") |> ignore
      if btn(c, "count").clicked {
        n.val = n.val + 1
      }
    })
    |> ignore
  })
  t.act(Button, Activate, label="count")
  assert_eq(n.val, 1)
  t.act(Button, Focus, label="other")
  assert_eq(t.focused().unwrap().label, "other")
}

///|
test "a Tester starts with a fresh context: no focus, theme or direction of the test before" {
  let t = Tester::new(fn(c) {
    c.set_theme(Theme::dark())
    c.set_direction(Rtl)
    btn(c, "x") |> ignore
  })
  t.tab()
  assert_true(t.ctx().theme().dark)
  let t2 = Tester::new(fn(c) { btn(c, "y") |> ignore })
  assert_false(t2.ctx().theme().dark)
  assert_eq(t2.ctx().direction(), Ltr)
  assert_true(t2.focused() is None)
}

///|
test "Tab goes into a list's rows too, built as the list is laid out" {
  let t = Tester::new(fn(c) {
    c.column(fn() {
      btn(c, "before") |> ignore
      c.list("rows", 3, 30.0, h=Px(120.0), fn(i) { btn(c, "row \{i}") |> ignore }) |> ignore
      btn(c, "after") |> ignore
    })
    |> ignore
  })
  t.tab()
  assert_eq(t.focused().unwrap().label, "before")
  t.tab()
  assert_eq(t.focused().unwrap().label, "row 0")
  t.tab()
  t.tab()
  t.tab()
  assert_eq(t.focused().unwrap().label, "after")
}
