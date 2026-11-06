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

///|
test "a predicted frame with geometry observers cannot execute a future input" {
  let told : Array[Double] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.laid_before_causes()
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0)))
        .shift(By(fn() { (v.drawn_at() / 1000.0, 0.0) })) |> ignore
      v.reacts(fn() { v.laid_window_told() }, fn(_) { })
    }))
  })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let v = page.val.unwrap()
  v.at_moment(95.0, fn() { told.push(v.cause_at()) }) |> ignore
  tree.at(100.0)
  tree.frame(400.0, 300.0, now=90.0) |> ignore
  assert_eq(told, [], msg="display prediction must not run a deadline before its input time")
  tree.advance(95.0)
  assert_eq(told, [95.0])
}

///|
test "a drawing-clock observer cannot advance a deadline past an input that cancels it" {
  let told : Array[Double] = []
  let shown : Array[Bool] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root)
    root.reacts(fn() { root.drawn_past(95.0) }, fn(past) { shown.push(past) })
  })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let v = page.val.unwrap()
  let cancel = v.at_moment(100.0, fn() { told.push(v.cause_at()) })
  tree.at(110.0)
  tree.frame(400.0, 300.0, now=90.0) |> ignore
  assert_eq(shown.last(), Some(true))
  assert_eq(tree.logic_at(), 90.0)
  tree.event(95.0, cancel)
  tree.advance(120.0)
  assert_eq(told, [])
}
