///|
test "the spacing scale lists every named step once, in order, each larger than the one before" {
  let scale = space_scale()
  for i, sp in scale {
    assert_eq(sp.step(), i)
    if i > 0 {
      assert_true(sp.px() > scale[i - 1].px())
    }
  }
}
