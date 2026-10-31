// What goes beside the pointer's point (View::beside's `at_pointer`): placed by where the pointer is in the window as
// the host says it (Tree::follow_point), its place alone worked out again as it moves, nothing as it stays.

///|
test "beside the pointer: by its point while it is on the anchor; told the same point again, nothing worked out; moved, placed again, nothing laid out or measured again" {
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(20.0))).height(Is(Some(200.0))).offset(Is((100.0, 20.0))) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.beside(ids["a"], side=Right, along=Middle, offset=14.0, at_pointer=true) |> ignore
        b.box(fn(w) { w.words(Is("调整宽度")) |> ignore }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let at = fn() {
    let d = t.drawn_of(ids["b"]).unwrap()
    (d.x, d.y + d.h / 2.0)
  }
  let point = fn(x : Double, y : Double) { t.follow_point(x, y, fn(_) {  }) }
  point(110.0, 100.0)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (124.0, 100.0), msg="by the pointer's point, 14 off, its middle level with it")
  let w0 = t.work()
  // (the same point told again: nothing to do)
  point(110.0, 100.0)
  t.frame(400.0, 300.0) |> ignore
  let w1 = t.work()
  assert_eq((w1.computes, w1.measured, w1.besides, w1.composed), (w0.computes, w0.measured, w0.besides, w0.composed))
  // (moved along it: placed again there alone)
  point(112.0, 150.0)
  t.frame(400.0, 300.0) |> ignore
  let w2 = t.work()
  assert_eq(at(), (126.0, 150.0), msg="by where it moved to")
  assert_eq((w2.computes, w2.measured), (w0.computes, w0.measured), msg="nothing laid out or measured again")
  assert_true(w2.besides > w1.besides, msg="placed again")
  // (off the anchor: beside all of it)
  point(300.0, 100.0)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (134.0, 120.0), msg="the pointer off it: beside all of it")
}
