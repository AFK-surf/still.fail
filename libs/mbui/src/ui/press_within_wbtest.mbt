// Where a press went down (Ctx::press_within), as what it presses asks it: a part of it only pointed at (Ctx::box's
// `points`: a row's state line) is in a pointer's press that went down on it; a key's press on what has the focus is
// on that alone, on no part of it, whatever a pointer's press went down on before.

///|
test "a press on a part only pointed at is within that part; Enter on what has the focus after it is on no part" {
  let said : Array[Bool] = []
  let t = Tester::new(
    fn(c) {
      let row = c.id("row")
      let part = c.id("row/part")
      c.focusable(row, on_press=true)
      c.on_press(row, fn() { said.push(c.press_within(part)) })
      c.box(left=20.0, top=20.0, w=Px(300.0), h=Px(60.0), id=row, fn() {
        c.box(w=Px(100.0), h=Px(30.0), id=part, taps=false, points=true, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
    platform=0,
  )
  t.check_looks(false)
  t.draw()
  // on the part, then on the row beside it
  t.tap(40.0, 30.0)
  t.tap(250.0, 60.0)
  t.tap(40.0, 30.0)
  assert_eq(said, [true, false, true])
  // the row has the focus from its press: Enter presses it, on no part of it
  t.enter()
  assert_eq(said, [true, false, true, false])
}
