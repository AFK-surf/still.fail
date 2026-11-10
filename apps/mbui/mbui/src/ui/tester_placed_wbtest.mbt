// The rule that what a frame draws was placed by the layout it draws by (tester_placed.mbt): what it says of a node as
// it stands, and none of it on a frame drawn as a frame draws.

///|
test "placed rule: a node never placed, or placed another size than laid out, is said; one placed as laid out is not" {
  assert_eq(placed_fault(7, (true, 40.0, 30.0, 40.0, 30.0)), None)
  assert_eq(placed_fault(7, (true, 40.0, 30.0, 40.3, 30.0)), None)
  assert_eq(placed_fault(7, (false, 0.0, 0.0, 390.0, 844.0)), Some("node 7 drawn, never placed (laid out 390×844)"))
  assert_eq(placed_fault(7, (true, 0.0, 0.0, 302.0, 22.0)), Some("node 7 drawn as placed 0×0, laid out 302×22"))
}

///|
test "placed rule: a frame a Tester draws, its nodes made and changed, says none" {
  let t = Tester::new(fn(_c) {  }, platform=1)
  t.check_looks(false)
  let wide = @signals.signal(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(By(fn() { Some(if wide.get() { 200.0 } else { 100.0 }) })).height(Is(Some(40.0))).ground(Is(1L)) |> ignore
      b.show(fn() { wide.get() }, fn(s) { s.words(Is("came"), look={ ..@view.words_plain, size: 12.0 }) |> ignore })
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.placed_faults(), [])
  wide.set(true)
  t.draw()
  assert_eq(t.placed_faults(), [])
}
