// One height for what is pressed side by side (heights.mbt, Tester::height_faults): a row of buttons of the window's
// tree, one of them another height, found; all alike, or one only wrapped in a box as big as it (#6246's stop in the
// row of 只看收发 and 详情), or taller than a control is, as the rule says.

///|
/// A button of the window's tree in `v`, `h` high, 60 wide, its ground 8 round, named `name`.
fn height_button(v : @view.View, name : String, h : Double) -> Unit {
  v.box(fn(b) {
    b
    .width(Is(Some(60.0)))
    .height(Is(Some(h)))
    .ground(Is(0xEEEEEEFFL))
    .radius(Is(8.0))
    .on_press(fn() {  })
    .says(Is(Some(@view.said(Button, label=name))))
    |> ignore
  })
  |> ignore
}

///|
/// The rule's faults on a row, 8 apart, of buttons `heights` high, the last wrapped in a box as big as it where
/// `wrapped`.
fn heights_row(heights : Array[Double], wrapped? : Bool = false) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).gap(Is(8.0)) |> ignore
      for i, h in heights {
        let name = "b\{i}"
        if wrapped && i == heights.length() - 1 {
          row.box(fn(w) { height_button(w, name, h) }) |> ignore
        } else {
          height_button(row, name, h)
        }
      }
    })
    |> ignore
  })
  t.draw()
  t.height_faults()
}

///|
test "one height in a row: a button 24 high among two 36 high found, the one 24 named; all 36 nothing" {
  let off = heights_row([36.0, 36.0, 24.0])
  assert_eq(off.length(), 1, msg=off.join("\n"))
  assert_true(off[0].contains("at 136,0 60×24") && off[0].contains("in its row 36"), msg=off[0])
  assert_eq(heights_row([36.0, 36.0, 36.0]), [])
}

///|
test "one height in a row: one wrapped in a box as big as it is still of the row (#6246's stop); a card's 60 is no control's" {
  let off = heights_row([22.0, 22.0, 24.0], wrapped=true)
  assert_eq(off.length(), 1, msg=off.join("\n"))
  assert_eq(heights_row([36.0, 60.0]), [])
}
