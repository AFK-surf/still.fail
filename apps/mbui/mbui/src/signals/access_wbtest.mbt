///|
test "panic a signal read in a phase that may read none aborts, in every build" {
  let s = signal(1)
  set_access_guard(Some("a test's phase")) |> ignore
  s.get() |> ignore
}

///|
test "panic a signal written in a phase that may read none aborts" {
  let s = signal(1)
  set_access_guard(Some("a test's phase")) |> ignore
  s.set(2)
}

///|
test "outside such a phase a signal is read and written as ever; the phase said ended, the one before is again" {
  let s = signal(1)
  let was = set_access_guard(Some("a test's phase"))
  assert_eq(set_access_guard(was), Some("a test's phase"))
  s.set(2)
  assert_eq(s.get(), 2)
}
