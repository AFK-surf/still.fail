// Numbers as the package's engines work them out (list_turns.mbt, emit.mbt, flight.mbt).

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  dmax(lo, dmin(hi, v))
}

///|
using @sf {
  dmin,
  dmax,
}
