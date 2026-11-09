///|
test "source-specific kept values reuse a reader and sweep only unused owners" {
  kept_reset()
  let _tester = @ui.Tester::new(fn(_) {  })
  let first = made_source()
  let second = made_source()
  let kept : SourceKept[String] = { kept: {}, listed: false }
  let first_work = Ref(0)
  let second_work = Ref(0)
  let first_get = fn(_ : String?) { first_work.val += 1; "first" }
  let second_get = fn(_ : String?) { second_work.val += 1; "second" }
  let watch = @signals.watch(fn() {  })
  assert_eq(watch.read(fn() { kept.read(first, "same", first_get) }), "first")
  assert_eq(watch.read(fn() { kept.read(first, "same", first_get) }), "first")
  assert_eq(first_work.val, 1, msg="the same source reuses its computed value")
  assert_eq(kept.read(second, "same", second_get), "second")
  assert_eq(second_work.val, 1)
  assert_eq(kept.peek_from(first, "same"), Some("first"))
  assert_eq(kept.peek_from(second, "same"), Some("second"))
  assert_eq(kept.peek("same"), Some("second"), msg="the unqualified peek is the last value read")
  kept.sweep()
  assert_eq(kept.peek_from(first, "same"), Some("first"), msg="a watched value survives the sweep")
  assert_eq(kept.peek_from(second, "same"), None, msg="an unused source is removed")
  watch.stop()
  kept.sweep()
  assert_true(kept.kept.get("same") is None, msg="the final source entry is removed")
  kept_reset()
  @ui.run_let_go()
}

///|
test "forgetting one source leaves another cached and reset allows both to read again" {
  kept_reset()
  let _tester = @ui.Tester::new(fn(_) {  })
  let first = made_source()
  let second = made_source()
  let kept : SourceKept[String] = { kept: {}, listed: false }
  let first_work = Ref(0)
  let second_work = Ref(0)
  let second_marked = Ref(0)
  let first_get = fn(_ : String?) { first_work.val += 1; "first" }
  let second_get = fn(_ : String?) { second_work.val += 1; "second" }
  let first_watch = @signals.watch(fn() {  })
  let second_watch = @signals.watch(fn() { second_marked.val += 1 })
  first_watch.read(fn() { kept.read(first, "same", first_get) }) |> ignore
  second_watch.read(fn() { kept.read(second, "same", second_get) }) |> ignore
  kept.forget_from(first, "same")
  assert_eq(kept.peek_from(first, "same"), None)
  assert_eq(kept.peek_from(second, "same"), Some("second"))
  assert_eq(second_marked.val, 0, msg="forgetting the first source does not mark the second")
  first_watch.read(fn() { kept.read(first, "same", first_get) }) |> ignore
  second_watch.read(fn() { kept.read(second, "same", second_get) }) |> ignore
  assert_eq(first_work.val, 2)
  assert_eq(second_work.val, 1, msg="the second source reuses its value")
  kept_reset()
  assert_true(kept.kept.get("same") is None)
  first_watch.read(fn() { kept.read(first, "same", first_get) }) |> ignore
  second_watch.read(fn() { kept.read(second, "same", second_get) }) |> ignore
  assert_eq(first_work.val, 3)
  assert_eq(second_work.val, 2)
  first_watch.stop()
  second_watch.stop()
  kept_reset()
  @ui.run_let_go()
}
