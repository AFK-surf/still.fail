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

///|
test "nested geometry notifications keep the frame's moment and restore the next input's scope" {
  let wall = Ref(0.0)
  let page : Ref[@view.View?] = Ref(None)
  let stage = @signals.signal(0.0)
  let leaf = @signals.signal(0.0)
  let seen : Array[(String, Double)] = []
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root)
    root.reacts(fn() { stage.get() }, fn(n) {
      seen.push(("stage", root.cause_at()))
      leaf.set(n * 2.0)
    })
    root.reacts(fn() { leaf.get() }, fn(_) { seen.push(("leaf", root.cause_at())) })
    root.box(fn(v) {
      v.width_share(Is(0.5)).height(Is(Some(40.0))) |> ignore
      v.reacts(fn() { v.laid_window_told() }, fn(r) {
        match r {
          Some(r) => {
            seen.push(("geometry", v.cause_at()))
            stage.set(r.2)
          }
          None => ()
        }
      })
    }) |> ignore
  }, time=fn() { wall.val })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  page.val.unwrap().at_moment(15.0, fn() { seen.push(("deadline", page.val.unwrap().cause_at())) }) |> ignore
  seen.clear()
  wall.val = 900.0
  tree.at(20.0)
  tree.frame(600.0, 300.0, now=10.0) |> ignore
  assert_eq(seen, [("geometry", 10.0), ("stage", 10.0), ("leaf", 10.0)])
  seen.clear()
  tree.event(12.0, fn() { stage.set(700.0) })
  assert_eq(seen, [("stage", 12.0), ("leaf", 12.0)])
  seen.clear()
  wall.val = 30.0
  stage.set(800.0)
  assert_eq(seen, [("deadline", 15.0), ("stage", 30.0), ("leaf", 30.0)])
  assert_eq(tree.logic_at(), 30.0)
}

///|
test "prediction preserves equal-time deadline registration order and cancellation" {
  let page : Ref[@view.View?] = Ref(None)
  let seen : Array[(String, Double)] = []
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root)
    root.reacts(fn() { root.drawn_past(95.0) }, fn(_) { })
  })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let v = page.val.unwrap()
  let cancel_b : Ref[() -> Unit] = Ref(fn() { })
  v.at_moment(100.0, fn() {
    seen.push(("a", v.cause_at()))
    (cancel_b.val)()
    v.at_moment(100.0, fn() { seen.push(("d", v.cause_at())) }) |> ignore
  }) |> ignore
  cancel_b.val = v.at_moment(100.0, fn() { seen.push(("b", v.cause_at())) })
  v.at_moment(100.0, fn() { seen.push(("c", v.cause_at())) }) |> ignore
  let cancel = v.at_moment(99.0, fn() { seen.push(("cancelled", v.cause_at())) })
  tree.at(110.0)
  tree.frame(400.0, 300.0, now=90.0) |> ignore
  assert_eq(seen, [])
  tree.event(95.0, cancel)
  tree.advance(120.0)
  assert_eq(seen, [("a", 100.0), ("c", 100.0), ("d", 100.0)])
  tree.advance(120.0)
  assert_eq(seen.length(), 3, msg="each deadline runs once")
}
