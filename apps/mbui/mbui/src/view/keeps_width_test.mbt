// A node laid out never narrower than it has been (View::keeps_width): at each change of what sets its width, as wide
// as that change laid it out, kept; what it holds narrower, as wide as it was; wider, as wide as that, whatever frames
// come between; no wider than its most as that is made less.

///|
test "keeps_width: what it holds made narrower, as wide as it was; wider, wider; its most made less than that, no wider than its most, laid out so at once" {
  let inner = @signals.signal(120.0, same=fn(a, b) { a == b })
  let most = @signals.signal(400.0, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      // (in a row: as wide as what it holds, not stretched across)
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(n) {
          id.val = Some(n.id())
          n.keeps_width(fn() { inner.get() }, most=fn() { most.get() }) |> ignore
          n.box(fn(k) { k.width(By(fn() { Some(inner.get()) })).height(Is(Some(10.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let w = fn() {
    t.frame(500.0, 300.0) |> ignore
    t.drawn_of(id.val.unwrap()).map(fn(d) { d.w })
  }
  assert_eq(w(), Some(120.0), msg="as wide as what it holds")
  t.event(10.0, fn() { inner.set(60.0) })
  assert_eq(w(), Some(120.0), msg="what it holds narrower: as wide as it was")
  t.event(20.0, fn() { inner.set(200.0) })
  assert_eq(w(), Some(200.0), msg="wider: as wide as that")
  t.event(30.0, fn() { inner.set(60.0) })
  t.event(30.0, fn() { most.set(150.0) })
  assert_eq(w(), Some(150.0), msg="its most less than it has been: its most, the frame it is")
  // (wider then narrower, no frame between: as wide as the wider laid it out)
  t.event(40.0, fn() { most.set(400.0) })
  t.event(41.0, fn() { inner.set(300.0) })
  t.event(42.0, fn() { inner.set(60.0) })
  assert_eq(w(), Some(300.0), msg="wider then narrower, no frame between: as the wider")
}
