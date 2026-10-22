// Android's press in what scrolls (Compose's clickable in a scrollable container): shown once it has stayed
// tap_indication_ms, so a finger that goes on to scroll lights nothing on its way.

///|
let pressed_rows : Array[Int] = []

///|
fn press_rows_view(c : Ctx) -> Unit {
  pressed_rows.clear()
  c.list("rows", 30, 50.0, fn(i) {
    let id = c.id("row/\{i}")
    if c.pressed(id) {
      pressed_rows.push(i)
    }
    c.box(style=style(w=Full, h=Fixed(50.0)), id~, fn() {  }) |> ignore
  })
  |> ignore
}

///|
test "Android: a press in a list shows once it has stayed, not as it comes down; elsewhere at once" {
  let t = Tester::new(press_rows_view, w=300.0, h=400.0, platform=2)
  t.touch(0, 100.0, 75.0)
  t.frame()
  assert_eq(pressed_rows, [])
  t.run_for(tap_indication_ms)
  assert_eq(pressed_rows, [1])
  t.touch(2, 100.0, 75.0)
  t.frame()
  let d = Tester::new(press_rows_view, w=300.0, h=400.0)
  d.touch(0, 100.0, 75.0)
  d.frame()
  assert_eq(pressed_rows, [1])
}
