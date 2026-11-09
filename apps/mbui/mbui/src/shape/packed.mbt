// Tables written as text rather than array literals: a literal is set element by element in the program's start-up
// code (moonbit_init, one function compiled whole on every build), text is data read once. Each number zigzagged
// (0, -1, 1, -2 … as 0, 1, 2, 3 …) and written five bits at a time, lowest first, as characters from '0': 32 and up
// for a group with more after it, below 32 for its last. Characters outside '0' to 'o' (a line's end) are skipped.

///|
/// The numbers of a table written as text, 64-bit.
pub fn packed_int64s(s : String) -> FixedArray[Int64] {
  let out : Array[Int64] = []
  let mut acc = 0UL
  let mut shift = 0
  for c in s {
    let d = c.to_int() - 48
    if d < 0 || d > 63 {
      continue
    }
    acc = acc | ((d & 31).to_uint64() << shift)
    shift += 5
    if d < 32 {
      out.push(((acc >> 1) ^ (0UL - (acc & 1UL))).reinterpret_as_int64())
      acc = 0UL
      shift = 0
    }
  }
  FixedArray::from_array(out)
}

///|
/// The numbers of a table written as text.
pub fn packed_ints(s : String) -> FixedArray[Int] {
  let wide = packed_int64s(s)
  FixedArray::makei(wide.length(), fn(i) { wide[i].to_int() })
}
