// A Tester read after another was made reads the other's frame (its reading calls read the process's: tester_own.mbt):
// what it would read said wrong, before anything is read; read before the next is made, each its own.

///|
/// A Tester whose window draws `words` alone.
fn own_tester(words : String) -> Tester {
  let t = Tester::new(fn(c) { c.text(words) |> ignore }, w=200.0, h=100.0)
  t.draw()
  t
}

///|
test "甲 made, then 乙, then 甲 read: what 甲 would read is 乙's frame, said so" {
  let first = own_tester("甲")
  let second = own_tester("乙")
  assert_eq(
    first.own_read_said(),
    "a Tester read after another was made: what it reads is the frame of the one made after it, not its own; read all of it before making the next",
  )
  // (the one made last reads its own)
  assert_eq(second.own_read_said(), "")
  assert_true(second.words().iter().any(fn(w) { w.0 == "乙" }))
}

///|
test "甲 made and read, then 乙 made and read: each its own frame" {
  let first = own_tester("甲")
  assert_eq(first.own_read_said(), "")
  let firsts = first.words().map(fn(w) { w.0 })
  let second = own_tester("乙")
  assert_eq(second.own_read_said(), "")
  let seconds = second.words().map(fn(w) { w.0 })
  assert_eq((firsts.contains("甲"), firsts.contains("乙")), (true, false))
  assert_eq((seconds.contains("乙"), seconds.contains("甲")), (true, false))
}
