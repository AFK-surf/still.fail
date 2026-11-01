///|
test "canonical decompositions, as harfrust's tables give them" {
  // singletons: ANGSTROM SIGN to Å, EN QUAD to EN SPACE, a CJK compatibility ideograph to one of plane 2
  assert_eq(@shape.decompose(0x212B), Some((0xC5, 0)))
  assert_eq(@shape.decompose(0x2000), Some((0x2002, 0)))
  assert_eq(@shape.decompose(0x2F803), Some((0x20122, 0)))
  // pairs
  assert_eq(@shape.decompose(0xC5), Some((0x41, 0x30A)))
  assert_eq(@shape.decompose(0x1E0A), Some((0x44, 0x307)))
  assert_eq(@shape.decompose(0x41), None)
}
