///|
test "what a watch is told as a signal is set says where; told by anything else, nothing" {
  let a = @signals.signal(0)
  let b = @signals.signal(0)
  let seen : Array[String] = []
  let w = @signals.watch(fn() {
    seen.push(match @signals.setting_at() { Some(_) => "set"; None => "none" })
  })
  w.read(fn() { a.get() + b.get() }) |> ignore
  a.set(1)
  w.read(fn() { a.get() + b.get() }) |> ignore
  // (told by a trigger after that set: not the set's place)
  @signals.trigger(fn() { b.get() |> ignore })
  assert_eq(seen, ["set", "none"])
  assert_true(@signals.setting_at() is None)
}

///|
test "what a watch is told as a batch ends says where the set in it that marked it was" {
  let a = @signals.signal(0)
  let b = @signals.signal(0)
  let seen : Array[String] = []
  let w = @signals.watch(fn() {
    seen.push(match @signals.setting_at() { Some(l) => l.to_string(); None => "none" })
  })
  w.read(fn() { a.get() }) |> ignore
  @signals.start_batch()
  b.set(1)
  a.set(1)
  @signals.end_batch()
  assert_eq(seen.length(), 1)
  assert_true(seen[0].contains("setting_at_test.mbt:"), msg=seen[0])
  assert_true(@signals.setting_at() is None)
  // (the next told by a trigger: none, not the batch's set)
  w.read(fn() { a.get() + b.get() }) |> ignore
  @signals.trigger(fn() { b.get() |> ignore })
  assert_eq(seen[1], "none")
}
