///|
test "an extent preserves the supplied binary metric through normal and subnormal values" {
  for bits in [1UL, 0xfffffffffffffUL, 0x10000000000000UL, 0x3fb999999999999aUL, 0x3fe6666666666666UL, 0x7fefffffffffffffUL] {
    let value = bits.reinterpret_as_double()
    assert_eq(Extent::of(value).to_double().reinterpret_as_uint64(), bits)
  }
  assert_eq(Extent::of(0.0).to_double(), 0.0)
}

///|
test "adding cached extents is associative even at fractional boundaries" {
  let a = Extent::of(0.7)
  let b = Extent::of(0.1)
  let c = Extent::of(1000000.0)
  assert_eq(a.add(b).add(c), a.add(b.add(c)))
  assert_false(a.add(b).at_most(Extent::of(0.7999999999999999)))
  assert_eq(a.add(b).minus(a), b)
  assert_eq(a.add(b).to_double(), 0.7 + 0.1)
  // Ties round to even only at the final conversion, never while composing spans.
  let one = Extent::of(1.0)
  let half_ulp = Extent::of(0x3ca0000000000000UL.reinterpret_as_double())
  assert_eq(one.add(half_ulp).to_double(), 1.0)
  assert_eq(one.add(half_ulp).add(half_ulp).to_double(), 0x3ff0000000000001UL.reinterpret_as_double())
}
