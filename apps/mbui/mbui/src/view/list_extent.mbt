// A finite nonnegative binary extent. The index adds the *exact* measured
// doubles, so grouping cached spans cannot change which side of a boundary a
// distance lies on. Coordinates round back to Double once, at the output.
// Cached ranges and direct reads use the same sum, regardless of update order.

///|
#derive(Eq, Debug)
priv struct ListExtent {
  units : @bigint.BigInt
  exponent : Int
}

///|
fn ListExtent::new(units : @bigint.BigInt, exponent : Int) -> ListExtent {
  if units.is_zero() { return { units, exponent: 0 } }
  let shift = units.ctz()
  { units: units >> shift, exponent: exponent + shift }
}

///|
fn ListExtent::of(value : Double) -> ListExtent {
  guard value >= 0.0 && !value.is_inf() else { abort("an extent must be nonnegative and finite") }
  let bits = value.reinterpret_as_uint64()
  let exponent = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction = bits & 0xfffffffffffffUL
  if exponent == 0 {
    ListExtent::new(@bigint.BigInt::from_uint64(fraction), -1074)
  } else {
    ListExtent::new(@bigint.BigInt::from_uint64(fraction | 0x10000000000000UL), exponent - 1075)
  }
}

///|
fn ListExtent::add(self : ListExtent, other : ListExtent) -> ListExtent {
  if self.units.is_zero() { return other }
  if other.units.is_zero() { return self }
  let exponent = if self.exponent < other.exponent { self.exponent } else { other.exponent }
  ListExtent::new((self.units << (self.exponent - exponent)) + (other.units << (other.exponent - exponent)), exponent)
}

///|
fn ListExtent::minus(self : ListExtent, other : ListExtent) -> ListExtent {
  if other.units.is_zero() { return self }
  let exponent = if self.exponent < other.exponent { self.exponent } else { other.exponent }
  let units = (self.units << (self.exponent - exponent)) - (other.units << (other.exponent - exponent))
  guard units.compare_int(0) >= 0 else { abort("a crossed extent exceeded the requested distance") }
  ListExtent::new(units, exponent)
}

///|
fn ListExtent::at_most(self : ListExtent, other : ListExtent) -> Bool {
  let exponent = if self.exponent < other.exponent { self.exponent } else { other.exponent }
  (self.units << (self.exponent - exponent)) <= (other.units << (other.exponent - exponent))
}

///|
fn ListExtent::to_double(self : ListExtent) -> Double {
  if self.units.is_zero() { return 0.0 }
  let mut units = self.units
  let mut exponent = self.exponent
  let shift = units.bit_length() - 53
  if shift > 0 {
    let high = units >> shift
    let tail = units - (high << shift)
    let half = @bigint.BigInt::from_int(1) << (shift - 1)
    units = if tail > half || (tail == half && (high.to_uint64() & 1UL) != 0UL) {
      high + @bigint.BigInt::from_int(1)
    } else { high }
    exponent += shift
  }
  if units.bit_length() > 53 { units = units >> 1; exponent += 1 }
  let length = units.bit_length()
  let power = exponent + length - 1
  if power > 1023 { return 0x7ff0000000000000UL.reinterpret_as_double() }
  if power < -1022 {
    return (units.to_uint64() << (exponent + 1074)).reinterpret_as_double()
  }
  let significand = units.to_uint64() << (53 - length)
  (((power + 1023).to_uint64() << 52) | (significand & 0xfffffffffffffUL)).reinterpret_as_double()
}
