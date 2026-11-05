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
      let tall = @signals.signal(0.0)
      list.box(fn(contents) {
        contents.each(fn() { rows.get() }, fn(h) { h }, fn(row, h) {
          row.height(By(fn() { Some(h.get()) })) |> ignore
        }) |> ignore
        contents.reacts(fn() { contents.laid_size_told() }, fn(size) {
          tall.set(size.map(fn(s) { s.1 }).unwrap_or(0.0))
        })
      }) |> ignore
      list.height(By(fn() { Some(tall.get()) })) |> ignore
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
test "a reply after presentation asks for its retained text without rebuilding the old frame" {
  let request = @signals.signal(0)
  let reply = @signals.signal(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.words(By(fn() { "reply \{reply.get()}" })) |> ignore
    old(root, fn(c) {
      c.text("beside", size=10.0) |> ignore
    }).height(Is(Some(20.0))) |> ignore
    read_drawn(root, fn() { request.get() }, fn(v) { reply.set(v) })
  })
  t.draw()
  t.measure_as_host()
  let at = t.time()
  request.set(1)
  t.frame_at(at + 1000.0 / 60.0)
  assert_true(t.fake.wants, msg="the reply must ask the host for the frame that shows it")
  assert_false(t.at_rest())
  // The reply is taken after the frame showing the request. Its own node is
  // drawn by the next frame, while the unrelated old view stays as it was.
  t.frame_at(at + 2000.0 / 60.0)
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "reply 1" }))
  assert_eq(t.built_why(), "", msg="a retained-only reply must not invalidate the old frame")
}

///|
test "a reply after presentation still updates an old view that reads it" {
  let request = @signals.signal(0)
  let reply = @signals.signal(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.text("reply \{reply.get()}", size=10.0) |> ignore
    }).height(Is(Some(20.0))) |> ignore
    read_drawn(root, fn() { request.get() }, fn(v) { reply.set(v) })
  })
  t.draw()
  t.measure_as_host()
  let at = t.time()
  request.set(1)
  t.frame_at(at + 1000.0 / 60.0)
  assert_true(t.fake.wants)
  t.frame_at(at + 2000.0 / 60.0)
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "reply 1" }))
}
