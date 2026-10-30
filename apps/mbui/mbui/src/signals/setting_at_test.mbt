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
