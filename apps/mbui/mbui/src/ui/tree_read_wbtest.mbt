///|
test "a drawn observation tells the final layout once, including a paint-only change, and stops with its node" {
  let rows = @signals.signal([30.0])
  let shifted = @signals.signal(0.0)
  let visible = @signals.signal(true)
  let told = []
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.show(fn() { visible.get() }, fn(list) {
      list.offset(By(fn() { (0.0, shifted.get()) })) |> ignore
      list.box(fn(contents) {
        contents.each(fn() { rows.get() }, fn(h) { h }, fn(row, h) {
          row.height(By(fn() { Some(h.get()) })) |> ignore
        }) |> ignore
      }) |> ignore
      read_drawn(list, fn() { list.laid_window_told() }, fn(rect) {
        match rect { Some((_, y, _, h)) => told.push((y, h)); None => () }
      })
    })
  })
  t.draw()
  assert_eq(told, [(0.0, 30.0)])
  rows.set([30.0, 70.0])
  t.draw()
  assert_eq(told, [(0.0, 30.0), (0.0, 100.0)])
  shifted.set(15.0)
  t.draw()
  assert_eq(told, [(0.0, 30.0), (0.0, 100.0), (15.0, 100.0)])
  @signals.start_batch()
  shifted.set(25.0)
  visible.set(false)
  @signals.end_batch()
  t.draw()
  assert_eq(told.length(), 3)
}

///|
test "a reply to one screen observation is not already in another observation of the same frame" {
  let value = @signals.signal(0)
  let told = []
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.words(By(fn() { value.get().to_string() })) |> ignore
    read_drawn(root, fn() { true }, fn(_) { value.set(1) })
    read_drawn(root, fn() { value.get() }, fn(v) { told.push(v) })
  })
  t.draw()
  assert_eq(told[0], 0)
}

///|
test "a layout event from a frame is delivered before the next input without another frame" {
  let requested = @signals.signal(20.0)
  let answer = @signals.signal(10.0)
  let told : Array[Double] = []
  let seen = Ref(0.0)
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.height(By(fn() { Some(requested.get()) })) |> ignore
      react_laid(n, fn() { n.laid_size_told() }, fn(size) {
        match size {
          Some((_, h)) => { told.push(h); answer.set(60.0) }
          None => ()
        }
      })
    }) |> ignore
    root.box(fn(n) { n.height(By(fn() { Some(answer.get()) })) |> ignore }) |> ignore
    root.on_key(fn(_) { seen.val = answer.get(); true }) |> ignore
  })
  t.frame(ms=16.0)
  assert_eq(told, [], msg="the frame's input snapshot is already committed")
  assert_eq(view_tree().unwrap().work().computes, 1)
  t.key_told(key_of_char('x'), 0, t.time() + 1.0)
  assert_eq(told, [20.0])
  assert_eq(seen.val, 60.0, msg="the next input sees the synchronous answer")
}

///|
test "a layout event caused by an input is delivered before the next input without a frame" {
  let requested = @signals.signal(20.0)
  let told : Array[Double] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.laid_before_causes()
    root.box(fn(n) {
      n.height(By(fn() { Some(requested.get()) })) |> ignore
      react_laid(n, fn() { n.laid_size_told() }, fn(size) {
        match size { Some((_, h)) => told.push(h); None => () }
      })
    }) |> ignore
    root.on_key(fn(_) { requested.set(50.0); true }) |> ignore
  })
  t.frame(ms=16.0)
  // Deliver the first frame's observation before exercising an input with no frame after it.
  t.key_told(key_of_char('x'), 0, t.time() + 1.0)
  assert_eq(told, [20.0, 50.0])
}

///|
test "layout events keep their values in cause order when the next change also needs layout" {
  let requested = @signals.signal(20.0)
  let told : Array[Double] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.laid_before_causes()
    root.box(fn(n) {
      n.height(By(fn() { Some(requested.get()) })) |> ignore
      react_laid(n, fn() { n.laid_size_told() }, fn(size) {
        match size { Some((_, h)) => told.push(h); None => () }
      })
    }) |> ignore
  })
  t.frame(ms=16.0)
  t.advance(10.0)
  requested.set(30.0)
  assert_eq(told, [20.0, 30.0])
}

///|
test "a layout event due before a later input retains the earlier cause's time" {
  let requested = @signals.signal(20.0)
  let told : Array[(Double, Double)] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  let start = t.time()
  t.check_looks(false)
  set_view_app(fn(root) {
    root.laid_before_causes()
    root.box(fn(n) {
      n.height(By(fn() { Some(requested.get()) })) |> ignore
      react_laid(n, fn() { n.laid_size_told() }, fn(size) {
        match size { Some((_, h)) => told.push((h, view_tree().unwrap().logic_at())); None => () }
      })
    }) |> ignore
    root.at_moment(start + 75.0, fn() { requested.set(50.0) }) |> ignore
  })
  t.frame_at(start + 16.0)
  t.advance(100.0)
  t.key_told(key_of_char('x'), 0, start + 116.0)
  assert_eq(told, [(20.0, start + 16.0), (50.0, start + 75.0)])
}

///|
test "a layout event for a node gone before delivery is not sent" {
  let visible = @signals.signal(true)
  let told : Array[Double] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { visible.get() }, fn(n) {
      n.height(Is(Some(20.0))) |> ignore
      react_laid(n, fn() { n.laid_size_told() }, fn(size) {
        match size { Some((_, h)) => told.push(h); None => () }
      })
    })
  })
  t.frame(ms=16.0)
  visible.set(false)
  t.key_told(key_of_char('x'), 0, t.time() + 1.0)
  assert_eq(told, [])
}
