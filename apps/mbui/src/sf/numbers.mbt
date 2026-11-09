// The smaller and the larger of two numbers, and a number held between two, as every package of the app works them out (one place: the library's).

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

///|
/// `v` held between `lo` and `hi` (`lo` no more than `hi`, as every caller has them: a number of rows less one only
/// where there are rows, a bar's row over the track under it, constants).
pub fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}
