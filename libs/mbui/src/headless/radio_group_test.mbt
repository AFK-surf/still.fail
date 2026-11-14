// The headless radio group and tab list (@headless.radio_group, RadioGroup::item), under a look of the tests' own:
// read out a RadioGroup of Radio items or a TabList of Tab items; roving Tab stop on the chosen item (or the first
// enabled item when none matches); arrow keys along the group's axis wrapping around enabled items and skipping
// disabled ones, Home and End to the first and the last; pressed by the pointer, Space/Enter or Activate to choose an
// unchosen item without re-firing on the already chosen one; items made dynamically by View::each. Each window is made
// by `window` (window_test.mbt), which holds that radio_group.mbt draws and lays out nothing.

///|
test "a radio group and its items: read out a RadioGroup of Radio items, Tab stops at the chosen one alone, ←/→ wrap around and skip disabled items, Home and End go to the ends, pressing chooses an unchosen item once" {
  let chosen = @signals.signal("b")
  let told : Array[String] = []
  let mid_off = @signals.signal(false)
  let t = window(fn(root) {
    root.box(fn(before) {
      before
      .width(Is(Some(40.0)))
      .height(Is(Some(30.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="前"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    @headless.radio_group(
      root,
      fn() { "对齐" },
      fn() { chosen.get() },
      fn(k) {
        told.push(k)
        chosen.set(k)
      },
      fn(g, rg) {
        g.row(Is(true)) |> ignore
        for item in [("a", "左"), ("b", "中"), ("c", "右")] {
          let (k, name) = item
          let off = if k == "b" { fn() { mid_off.get() } } else { fn() { false } }
          rg.item(
            g,
            fn() { k },
            fn() { name },
            disabled=off,
            fn(v, s) {
              v
              .width(Is(Some(60.0)))
              .height(Is(Some(32.0)))
              .ground(By(fn() { if s.chosen() { c_pressed } else { c_rest } }))
              |> ignore
            },
          )
          |> ignore
        }
      },
    )
    |> ignore
    root.box(fn(after) {
      after
      .width(Is(Some(40.0)))
      .height(Is(Some(30.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="后"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
  })
  assert_true(t.query(RadioGroup, label="对齐") is Some(_))
  assert_eq(
    (t.get(Radio, label="左").check, t.get(Radio, label="中").check, t.get(Radio, label="右").check),
    (Some(@view.Check::Off), Some(@view.Check::On), Some(@view.Check::Off)),
  )
  // Tab from "前" lands on the chosen item ("中"), and a second Tab goes straight to "后"
  t.act(Button, Focus, label="前")
  t.tab()
  let tab1 = t.focused().map(fn(s) { s.label }).unwrap_or("")
  t.tab()
  let tab2 = t.focused().map(fn(s) { s.label }).unwrap_or("")
  assert_eq((tab1, tab2), ("中", "后"))
  // Focus back on "中": Right -> "右", Right -> wraps to "左", End -> "右", Home -> "左"
  t.act(Radio, Focus, label="中")
  t.key(@ui.key_code_right)
  let after_r1 = (chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or(""))
  t.key(@ui.key_code_right)
  let after_r2 = (chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or(""))
  t.key(@ui.key_code_end)
  let after_end = (chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or(""))
  t.key(@ui.key_code_home)
  let after_home = (chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or(""))
  assert_eq((after_r1, after_r2, after_end, after_home), (("c", "右"), ("a", "左"), ("c", "右"), ("a", "左")))
  // Disable "中": Right from "左" skips "中" and goes to "右"
  mid_off.set(true)
  t.frame()
  t.key(@ui.key_code_right)
  assert_eq((chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or("")), ("c", "右"))
  // Clicking the already-chosen "右" does not call choose again; clicking "左" chooses "a"
  let count_before = told.length()
  t.click(Radio, label="右")
  let count_same = told.length()
  t.click(Radio, label="左")
  assert_eq((count_same == count_before, chosen.get(), told.last()), (true, "a", Some("a")))
}

///|
test "a vertical tab list with dynamic each items: read out a TabList of Tab items, Tab stops at the first item when none is chosen, ↑/↓ move and choose" {
  let chosen = @signals.signal("none")
  let opts = @signals.signal([("t1", "概览"), ("t2", "日志")])
  let t = window(fn(root) {
    @headless.radio_group(
      root,
      fn() { "面板" },
      fn() { chosen.get() },
      fn(k) { chosen.set(k) },
      kind=Tab,
      axis=Vertical,
      fn(g, rg) {
        g.each(fn() { opts.get().map(fn(o) { o.0 }) }, fn(k) { k }, fn(slot, k) {
          let key = k.untracked()
          let name = fn() {
            match opts.get().iter().find_first(fn(o) { o.0 == key }) {
              Some(o) => o.1
              None => ""
            }
          }
          rg.item(slot, fn() { key }, name, space_only=true, fn(v, s) {
            v
            .width(Is(Some(100.0)))
            .height(Is(Some(32.0)))
            .ground(By(fn() { if s.chosen() { c_pressed } else { c_rest } }))
            |> ignore
          })
          |> ignore
        })
      },
    )
    |> ignore
  })
  assert_true(t.query(TabList, label="面板") is Some(_))
  assert_eq((t.get(Tab, label="概览").selected, t.get(Tab, label="日志").selected), (Some(false), Some(false)))
  // Neither is chosen yet, so Tab lands on the first item ("概览")
  t.tab()
  let first_focus = t.focused().map(fn(s) { s.label }).unwrap_or("")
  // Space chooses the focused first item
  t.key(@ui.key_space)
  let after_space = chosen.get()
  // Down moves to "日志" and chooses "t2"
  t.key(@ui.key_code_down)
  let after_down = (chosen.get(), t.focused().map(fn(s) { s.label }).unwrap_or(""))
  assert_eq((first_focus, after_space, after_down), ("概览", "t1", ("t2", "日志")))
}
