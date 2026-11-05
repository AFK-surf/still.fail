// A list's heights kept by their sums (Heights): where each block starts and which lies at a point, against the
// blocks summed one by one; the same sums whatever order they were measured in.

///|
/// Where block `i` starts, the blocks before it summed one by one.
fn heights_summed(hs : Array[Double], i : Int) -> Double {
  let mut s = 0.0
  for k in 0..<i {
    s = s + hs[k]
  }
  s
}

///|
test "where each block starts and which lies at a point, as the blocks summed one by one have it" {
  let hs : Array[Double] = []
  for i in 0..<37 {
    hs.push(((i * 7919) % 53).to_double() + 0.5)
  }
  let h = @view.Heights::of(hs.copy())
  // (measured anew, some of them: taller, shorter, as tall as nothing)
  for i in [0, 5, 16, 31, 36] {
    let to = if i == 16 { 0.0 } else { hs[i] * 1.5 + 3.0 }
    hs[i] = to
    h.set(i, to)
  }
  for i in 0..=37 {
    assert_true((h.top(i) - heights_summed(hs, i)).abs() < 0.001, msg="top \{i}")
  }
  assert_true((h.total() - heights_summed(hs, 37)).abs() < 0.001)
  // (the block at a point: the first whose foot is under it)
  for i in 0..<37 {
    let top = heights_summed(hs, i)
    if hs[i] > 0.0 {
      assert_eq(h.at(top), i)
      assert_eq(h.at(top + hs[i] / 2.0), i)
    }
  }
  assert_eq(h.at(-5.0), 0)
  assert_eq(h.at(h.total()), 37)
  assert_eq(h.at(h.total() + 100.0), 37)
}

///|
test "a block ending at a point, or as tall as nothing there, lies before it" {
  let h = @view.Heights::of([10.0, 0.0, 20.0, 5.0])
  assert_eq(h.at(0.0), 0)
  assert_eq(h.at(9.5), 0)
  // (the first ends at 10, the second as tall as nothing there: the third lies at 10)
  assert_eq(h.at(10.0), 2)
  assert_eq(h.at(30.0), 3)
  assert_eq(h.at(34.9), 3)
  assert_eq(h.at(35.0), 4)
}

///|
test "the sums are the same whatever order the blocks were measured in" {
  let a = @view.Heights::new(500, 80.0)
  let b = @view.Heights::new(500, 80.0)
  let heights = Array::makei(500, fn(i) { 40.0 + (i % 17).to_double() / 3.25 })
  for i in 0..<500 {
    a.set(i, heights[i])
  }
  for i in 0..<500 {
    let j = 499 - i
    b.set(j, heights[j] + 7.25)
    b.set(j, heights[j])
  }
  for i in [0, 1, 99, 250, 499, 500] {
    assert_eq(a.top(i), b.top(i))
  }
  assert_eq(a.total(), b.total())
}

///|
test "the first block reaching a point: one ending at it, or as tall as nothing there, is it" {
  let h = @view.Heights::of([10.0, 0.0, 20.0, 5.0])
  assert_eq(h.reaching(-1.0), 0)
  assert_eq(h.reaching(0.0), 0)
  assert_eq(h.reaching(10.0), 0)
  // (the second as tall as nothing at 10, its foot over 10.5: the third)
  assert_eq(h.reaching(10.5), 2)
  assert_eq(h.reaching(35.0), 3)
  assert_eq(h.reaching(35.5), 4)
  assert_eq(@view.Heights::new(0, 80.0).reaching(10.0), 0)
  assert_eq(@view.Heights::new(0, 80.0).at(10.0), 0)
}
