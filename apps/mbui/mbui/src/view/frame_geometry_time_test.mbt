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
test "a frame's geometry notifications do not resettle predicted placement as an input change" {
  let faults : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(s) { faults.push(s) })
  defer {
    @view.faults_stop.val = true
    @view.fault_told.val = None
  }
  let page : Ref[@view.View?] = Ref(None)
  let measured : Array[(Double, Double)] = []
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.laid_before_causes()
      v.width_share(Is(0.5)).height(Is(Some(40.0)))
        .shift(By(fn() { (v.drawn_at() / 1000.0, 0.0) })) |> ignore
      v.reacts(fn() { v.laid_window_told() }, fn(rect) {
        if rect is Some(_) { measured.push(v.laid_size()) }
      })
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  measured.clear()
  tree.at(100.0)
  tree.frame(500.0, 300.0, now=90.0) |> ignore
  assert_eq(faults, [])
  assert_eq(page.val.unwrap().rect().0, 25.0)
  assert_eq(measured.last(), Some((250.0, 40.0)))
}
