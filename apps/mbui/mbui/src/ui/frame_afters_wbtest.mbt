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
