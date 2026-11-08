///|
test "a new run finishes queued frame handovers once" {
  let called = Ref(0)
  let resource = @signals.signal(0)
  resource.on_unwatched(fn() { after_frame(fn() { called.val += 1 }) })
  let reader = @signals.watch(fn() {  })
  reader.read(fn() { resource.get() }) |> ignore
  frame_running.val = true
  reader.stop()
  frame_running.val = false
  assert_eq(called.val, 0)
  let _ = Tester::new(fn(_) {  })
  assert_eq(called.val, 1)
  assert_true(frame_afters.val.is_empty())
  run_let_go()
  assert_eq(called.val, 1)
}

///|
test "readers can hand a resource over during one event between frames" {
  let _ = Tester::new(fn(_) {  })
  let released = Ref(0)
  let resource = @signals.signal(0)
  resource.on_unwatched(fn() {
    after_frame(fn() { if !resource.watched() { released.val += 1 } })
  })
  let first = @signals.watch(fn() {  })
  let second = @signals.watch(fn() {  })
  let during : Array[Int] = []
  first.read(fn() { resource.get() }) |> ignore
  view_event_said(fn() { first.stop() }, fn() {
    during.push(released.val)
    second.read(fn() { resource.get() }) |> ignore
  })
  assert_eq(released.val, 0, msg="the event's next reader kept the resource")
  view_event_said(fn() { second.stop() }, fn() {
    during.push(released.val)
  })
  assert_eq(during, [0, 0], msg="the last reader is checked at the event's end")
  assert_eq(released.val, 1, msg="the last reader is released when the event ends")
  run_let_go()
}

///|
test "nested events finish handovers at the outside event or frame boundary" {
  let _ = Tester::new(fn(_) {  })
  let called = Ref(0)
  let during : Array[Int] = []
  view_event_said(fn() {
    after_frame(fn() { called.val += 1 })
    view_event_said(fn() { after_frame(fn() { called.val += 1 }) }, fn() { during.push(called.val) })
  }, fn() { during.push(called.val) })
  assert_eq(during, [0, 0])
  assert_eq(called.val, 2)
  frame_running.val = true
  view_event_said(fn() { after_frame(fn() { called.val += 1 }) }, fn() {  })
  assert_eq(called.val, 2, msg="an event within a frame waits for that frame")
  frame_running.val = false
  frame_afters_run()
  assert_eq(called.val, 3)
  run_let_go()
}
