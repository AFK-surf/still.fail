// The smaller and the larger of two numbers, as every package of the app works them out (one place: the library's).

///|
/// The smaller of `a` and `b` (`b` where they are equal or either is not a number).
pub fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// The larger of `a` and `b` (`b` where they are equal or either is not a number).
pub fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}
