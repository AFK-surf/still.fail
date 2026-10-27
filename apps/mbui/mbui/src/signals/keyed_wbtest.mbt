// Keyed (keyed.mbt): a set read by member, each reader told only as its own key comes in or leaves.

///|
test "a key read is told as it comes in and as it leaves, not as another key does" {
  let k : Keyed[Int] = keyed()
  let w3 = watch(fn() {  })
  let w4 = watch(fn() {  })
  assert_eq(w3.read(fn() { k.has(3) }), false)
  w4.read(fn() { k.has(4) }) |> ignore
  // (another key: neither told)
  k.set([5])
  assert_true(!w3.is_stale())
  assert_true(!w4.is_stale())
  k.set([3])
  assert_true(w3.is_stale())
  assert_true(!w4.is_stale())
  assert_eq(w3.read(fn() { k.has(3) }), true)
  // (the same again: none told; moved on to 4: both)
  k.set([3])
  assert_true(!w3.is_stale())
  k.set([4])
  assert_true(w3.is_stale())
  assert_true(w4.is_stale())
}

///|
test "keys read once and read no more are let go, those read still kept" {
  let k : Keyed[Int] = keyed()
  let w = watch(fn() {  })
  w.read(fn() { k.has(0) }) |> ignore
  for i in 1..<200 {
    // (each read once, by none that follows it)
    read_unfollowed(k, i)
    k.set([i])
  }
  k.set([])
  assert_true(k.said.length() < 64)
  assert_true(k.said.contains(0))
  k.set([0])
  assert_true(w.is_stale())
}

///|
/// Reads key `i` of `k`, followed by nothing.
fn read_unfollowed(k : Keyed[Int], i : Int) -> Unit {
  untracked(fn() { k.has(i) }) |> ignore
}
