///|
test "text runs: each line's words where the frame drew them, the spaces it ends in left out" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(pad=10.0, fn() {
        c.text("one two ", size=15.0, line=20.0) |> ignore
        c.text("three", size=15.0, line=20.0, w=@ui.Px(200.0), center=true) |> ignore
      })
      |> ignore
    },
  )
  let runs = t.text_runs()
  assert_eq(runs.map(fn(r) { r.text }), ["one two", "three"])
  let one = runs[0]
  assert_true(one.x0 >= 10.0 && one.x0 < 11.0)
  assert_eq(one.top, 10.0)
  assert_eq(one.bottom, 30.0)
  assert_true(one.base > one.top && one.base < one.bottom)
  assert_true(one.x1 > one.x0)
  // centred in its 200: as far from its left as its right is from the box's
  let three = runs[1]
  assert_eq(three.top, 30.0)
  let left = three.x0 - 10.0
  let right = 210.0 - three.x1
  assert_true((left - right).abs() < 1.0)
}
