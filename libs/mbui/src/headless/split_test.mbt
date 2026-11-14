// The headless split handle (@headless.split), under a look of the tests' own: read out a Separator by its name with
// its range and Increment/Decrement actions; dragged in window coordinates without feedback drift as the pane beside it
// resizes; stepped by the arrow keys along its axis and by Home/End; stepped by a screen reader's Increment and
// Decrement; reset by a double click; disabled, none of these. Each window is made by `window` (window_test.mbt), which
// holds that split.mbt draws and lays out nothing.

///|
test "a horizontal split handle between two panes: read out a Separator with range and Increment/Decrement, dragged across the window as the left pane resizes with it, stepped by ←/→ and Home/End, stepped by a screen reader, reset on double click, and inert when disabled" {
  let val = @signals.signal(150.0)
  let off = @signals.signal(false)
  let state : Ref[@headless.Split?] = Ref(None)
  let t = window(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(left) {
      left.width(By(fn() { Some(val.get()) })).height(Is(Some(200.0))).ground(Is(c_rest)) |> ignore
    })
    |> ignore
    @headless.split(
      root,
      fn() { "侧栏分界" },
      fn() { val.get() },
      min=100.0,
      max=300.0,
      step=10.0,
      fn(to) { val.set(to) },
      reset=fn() { val.set(150.0) },
      disabled=fn() { off.get() },
      fn(v, s) {
        state.val = Some(s)
        v
        .width(Is(Some(8.0)))
        .height(Is(Some(200.0)))
        .ground(By(fn() { if s.dragging() { c_pressed } else { c_hovered } }))
        |> ignore
      },
    )
    |> ignore
  })
  let sem = t.get(Separator, label="侧栏分界")
  assert_eq(
    (sem.value, sem.range, sem.actions.contains(Focus), state.val.unwrap().part()),
    ("150", Some((100.0, 150.0, 300.0)), true, 0.25),
  )
  // Drag the splitter from x=154 to x=214 (+60px): left pane resizes to 210 while dragging
  t.press_at(154.0, 100.0)
  t.move_to(214.0, 100.0)
  let dragged_val = (val.get(), state.val.unwrap().dragging())
  t.release(214.0, 100.0)
  // Keyboard: focus, Right (+10 -> 220), Left (-10 -> 210), Home (100), End (300)
  t.act(Separator, Focus, label="侧栏分界")
  t.key(@ui.key_code_right)
  let after_right = val.get()
  t.key(@ui.key_code_left)
  let after_left = val.get()
  t.key(@ui.key_code_home)
  let after_home = val.get()
  t.key(@ui.key_code_end)
  let after_end = val.get()
  // Screen reader Decrement (-10 -> 290)
  t.act(Separator, Decrement, label="侧栏分界")
  let after_dec = val.get()
  // Double-click at the handle's new center (x=294, y=100) resets to 150
  t.tap(294.0, 100.0)
  t.tap(294.0, 100.0)
  let after_reset = val.get()
  // Disabled: no drag, no key, no step
  off.set(true)
  t.frame()
  t.key(@ui.key_code_right)
  t.act(Separator, Increment, label="侧栏分界")
  assert_eq(
    (dragged_val, after_right, after_left, after_home, after_end, after_dec, after_reset, val.get()),
    ((210.0, true), 220.0, 210.0, 100.0, 300.0, 290.0, 150.0, 150.0),
  )
}
