///|
test "a frame's geometry notifications retain its time even when the host clock has advanced" {
  let wall = Ref(0.0)
  let clock_reads = Ref(0)
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0)))
        .offset(By(fn() { (v.drawn_at(), 0.0) })) |> ignore
      v.reacts(fn() { v.laid_window_told() }, fn(_) { })
    }))
  }, time=fn() { clock_reads.val += 1; wall.val })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  clock_reads.val = 0
  wall.val = 100.0
  tree.at(10.0)
  tree.frame(400.0, 300.0, now=10.0) |> ignore
  assert_eq(clock_reads.val, 0)
  assert_eq(page.val.unwrap().rect().0, 10.0)
}

///|
test "a frame's window changes keep their declared moment and release it before an outside change" {
  let wall = Ref(0.0)
  let clock_reads = Ref(0)
  let change = @signals.signal(0, same=fn(a, b) { a == b })
  let moments : Array[Double] = []
  let tree = @view.Tree::new(fn(root) {
    root.reacts(fn() { (root.window(), change.get()) }, fn(_) {
      moments.push(root.cause_at())
    })
  }, time=fn() { clock_reads.val += 1; wall.val })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  moments.clear()
  clock_reads.val = 0
  wall.val = 200.0
  tree.frame(500.0, 300.0, now=10.0) |> ignore
  assert_eq(clock_reads.val, 0)
  assert_eq(moments, [10.0])
  change.set(1)
  assert_eq(moments, [10.0, 200.0])
}
