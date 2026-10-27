// What reads a table or a list kept in place (live.mbt) follows its changes: a computed of it is worked out again
// once it changed, not before, and not for a change that changed nothing.

///|
test "a computed of a LiveMap is worked out again as it changes, and only then" {
  let m : LiveMap[String, Int] = LiveMap::new()
  let runs = Ref(0)
  let sum = @signals.computed(fn(_) {
    runs.val += 1
    m.values().fold(init=0, fn(a, b) { a + b })
  })
  assert_eq(sum.get(), 0)
  m["a"] = 2
  m["b"] = 3
  assert_eq(sum.get(), 5)
  assert_eq(sum.get(), 5)
  assert_eq(runs.val, 2)
  // (what is not there let go of: nothing changed)
  m.remove("c")
  assert_eq(sum.get(), 5)
  assert_eq(runs.val, 2)
  m.remove("a")
  assert_eq(sum.get(), 3)
}

///|
test "a computed of a LiveArray follows what is pushed, put in place of it and let go of" {
  let a : LiveArray[String] = LiveArray::new()
  let seen = @signals.computed(fn(_) { a.length() })
  assert_eq(seen.get(), 0)
  a.push("x")
  assert_eq(seen.get(), 1)
  a.replace(["y", "z"])
  assert_eq(seen.get(), 2)
  a.retain(fn(s) { s != "y" })
  assert_eq((seen.get(), a.copy()), (1, ["z"]))
  // (a copy read as it is: nothing followed changes it)
  let c = a.copy()
  a.clear()
  assert_eq((seen.get(), c), (0, ["z"]))
}
