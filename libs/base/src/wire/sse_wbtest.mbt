///|
test "the room for what is held doubles, and past 1 GiB is the most an Int says, never a number wrapped" {
  assert_eq(grown(4096, 5000), 8192)
  assert_eq(grown(4096, 10000), 10000)
  assert_eq(grown(0x2000_0000, 0x2000_0001), 0x4000_0000)
  // (twice 1 GiB is no Int: it wrapped to less than nothing, and the room grew by what each chunk needed)
  assert_eq(grown(0x4000_0000, 0x4000_0001), 0x7FFF_FFFF)
  assert_eq(grown(0x7000_0000, 0x7000_0001), 0x7FFF_FFFF)
}
