// The headless toggle (@headless.toggle), under a look of the tests' own: found a checkbox or a switch by its name, on
// or off as its caller says; turned by the pointer, by Enter and Space, by a screen reader's ask, each telling its
// caller the other of what it is then; disabled, none of these and the focus let go; what its look reads of it. Each
// window is made by `window` (window_test.mbt), which holds that the toggle's own file draws and lays out nothing.

///|
/// What a case keeps: its window, what its caller was told each press (in order), what its look was handed, what its
/// caller says of it (on, disabled).
struct ToggleCase {
  t : @ui.Tester
  told : Array[Bool]
  state : Ref[@headless.Toggle?]
  on : @signals.Signal[Bool]
  off : @signals.Signal[Bool]
}

///|
/// A window 400 by 300: a box "别处" 50 by 50 that takes the focus, then a toggle of `kind` "提醒", 120 by 40, its
/// ground c_rest, c_hovered, c_pressed or c_focus by what its look reads (button_test's), c_disabled while disabled;
/// its caller writes what it is told (`writes`), or only keeps it.
fn toggle_case(kind? : @headless.ToggleKind = Checkbox, writes? : Bool = true) -> ToggleCase raise {
  let flag = fn(v : Bool) { @signals.signal(v, same=fn(a : Bool, b : Bool) { a == b }) }
  let (told, state) = ([], Ref(None))
  let (on, off) = (flag(false), flag(false))
  let t = window(fn(root) {
    root.box(fn(e) {
      e
      .width(Is(Some(50.0)))
      .height(Is(Some(50.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="别处"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    @headless.toggle(
      root,
      kind,
      fn() { "提醒" },
      fn() { on.get() },
      fn(to) {
        told.push(to)
        if writes {
          on.set(to)
        }
      },
      fn(v, s) {
        state.val = Some(s)
        v
        .width(Is(Some(120.0)))
        .height(Is(Some(40.0)))
        .ground(By(fn() {
          if s.disabled() {
            c_disabled
          } else if s.pressed() {
            c_pressed
          } else if s.focus_shown() {
            c_focus
          } else if s.hovered() {
            c_hovered
          } else {
            c_rest
          }
        }))
        |> ignore
      },
      disabled=fn() { off.get() },
    )
    |> ignore
  })
  { t, told, state, on, off }
}

///|
/// Who has the keyboard's focus, by name ("": nobody that says a name).
fn ToggleCase::focus(self : ToggleCase) -> String {
  match self.t.focused() {
    Some(s) => s.label
    None => ""
  }
}

///|
/// The ground the toggle's look draws now (its rect 120 by 40).
fn ToggleCase::ground(self : ToggleCase) -> Int64 {
  for r in self.t.drawn_rects() {
    if r.2 == 120.0 && r.3 == 40.0 {
      return r.4
    }
  }
  0L
}

///|
test "a checkbox is read out a checkbox by its name, off, with a press to do; a tap tells its caller on, and read out on once it says so" {
  let k = toggle_case()
  let s = k.t.get(Checkbox, label="提醒", checked=Off)
  k.t.click(Checkbox, label="提醒")
  assert_eq(
    (s.disabled, s.actions.contains(Activate), k.told, k.t.query(Checkbox, label="提醒", checked=On) is Some(_)),
    (false, true, [true], true),
  )
}

///|
test "a switch is read out a switch, on or off as its caller says, and no checkbox" {
  let k = toggle_case(kind=Switch)
  let off = k.t.query(Switch, label="提醒", checked=Off) is Some(_)
  k.on.set(true)
  k.t.frame()
  assert_eq((off, k.t.query(Switch, label="提醒", checked=On) is Some(_), k.t.query(Checkbox, label="提醒") is None), (true, true, true))
}

///|
test "a toggle button is read out a button, pressed or not as its caller says, and turned by a press" {
  let k = toggle_case(kind=Button)
  let off = k.t.get(Button, label="提醒").pressed
  k.t.click(Button, label="提醒")
  let on = k.t.get(Button, label="提醒").pressed
  assert_eq((off, on, k.told), (Some(false), Some(true), [true]))
}

///|
test "Tab goes to a toggle; Enter turns it, Space turns it back, a screen reader's ask turns it again: each told the other of what it is then" {
  let k = toggle_case()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let at = k.focus()
  k.t.enter()
  k.t.key(@ui.key_space)
  k.t.act(Checkbox, Activate, label="提醒")
  assert_eq((at, k.told, k.on.get()), ("提醒", [true, false, true], true))
}

///|
test "a toggle whose caller keeps what it is told and writes none: each press tells it on again, never what it was told before" {
  let k = toggle_case(writes=false)
  k.t.click(Checkbox, label="提醒")
  k.t.click(Checkbox, label="提醒")
  assert_eq(k.told, [true, true])
}

///|
test "a toggle disabled: read out disabled with nothing to do, no turn by a tap, a key or its state's press; Tab passes it" {
  let k = toggle_case()
  k.off.set(true)
  k.t.frame()
  let s = k.t.get(Checkbox, label="提醒")
  let (x, y, w, h) = s.rect
  k.t.tap(x + w / 2.0, y + h / 2.0)
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  k.t.enter()
  k.t.key(@ui.key_space)
  k.state.val.unwrap().press()
  assert_eq((s.disabled, s.actions.contains(Activate), k.focus() == "提醒", k.told), (true, false, false, []))
}

///|
test "a toggle turned on by its caller in the change that presses it, the tree not yet told: told off, what it is as it is pressed" {
  let k = toggle_case()
  @signals.start_batch()
  k.on.set(true)
  k.state.val.unwrap().press()
  @signals.end_batch()
  assert_eq(k.told, [false])
}

///|
test "a toggle with the focus, disabled: the focus let go of it at that cause" {
  let k = toggle_case()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let had = k.focus()
  k.off.set(true)
  assert_eq((had, k.focus()), ("提醒", ""))
}

///|
test "what a toggle's look reads: on as its caller says it; hovered under a mouse, pressed while held, the focus come by the keyboard; disabled as its caller says it" {
  let k = toggle_case()
  let s = k.state.val.unwrap()
  let (x, y, w, h) = k.t.get(Checkbox, label="提醒").rect
  let (mx, my) = (x + w / 2.0, y + h / 2.0)
  let was = s.on()
  k.t.move_to(mx, my)
  let over = k.ground()
  k.t.press_at(mx, my)
  let down = k.ground()
  k.t.release(mx, my)
  let now = s.on()
  k.t.move_to(390.0, 290.0)
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let focus = (k.ground(), s.focus_shown())
  k.off.set(true)
  k.t.draw()
  assert_eq(
    (was, over, down, now, focus, k.ground(), s.disabled()),
    (false, c_hovered, c_pressed, true, (c_focus, true), c_disabled, true),
  )
}

///|
test "a toggle with hold_press: a press held past the hold time and let go on it turns it; let go off it, does not" {
  let on = @signals.signal(false)
  let t = window(pointing=Finger, fn(root) {
    @headless.toggle(
      root,
      Switch,
      fn() { "开关" },
      fn() { on.get() },
      fn(to) { on.set(to) },
      hold_press=(@ui.touch_slop(), @ui.long_press_ms),
      fn(v, _) {
        v.width(Is(Some(80.0))).height(Is(Some(40.0))).ground(Is(c_rest)) |> ignore
      },
    )
    |> ignore
  })
  t.press_at(40.0, 20.0)
  t.run_for(held_ms)
  t.release(40.0, 20.0)
  let held_on = on.get()
  t.press_at(40.0, 20.0)
  t.run_for(held_ms)
  t.move_to(200.0, 200.0)
  t.release(200.0, 200.0)
  assert_eq((held_on, on.get()), (true, true))
}
