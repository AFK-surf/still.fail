// Numbers as the package's engines work them out (list_turns.mbt, emit.mbt, flight.mbt).

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  dmax(lo, dmin(hi, v))
}
