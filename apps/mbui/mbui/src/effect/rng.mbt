///|
/// A seeded random (xorshift32): the same seed, the same draws, on every
/// backend. The scheduler draws from one (which ready task runs next), sims
/// from another (jitter, order, loss), so a seed replays a whole run.
pub struct Rng {
  priv mut s : UInt
}

///|
pub fn Rng::new(seed : Int) -> Rng {
  let s = (seed.reinterpret_as_uint() * 2654435761U) ^ 0x9E3779B9U
  { s: if s == 0U { 1U } else { s } }
}

///|
pub fn Rng::next(self : Rng) -> UInt {
  let mut x = self.s
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.s = x
  x
}

///|
/// In [0, n).
pub fn Rng::below(self : Rng, n : Int) -> Int {
  if n <= 1 {
    return 0
  }
  (self.next() % n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// In [lo, hi].
pub fn Rng::between(self : Rng, lo : Int, hi : Int) -> Int {
  lo + self.below(hi - lo + 1)
}

///|
/// True with probability `p`.
pub fn Rng::chance(self : Rng, p : Double) -> Bool {
  (self.next() >> 8).reinterpret_as_int().to_double() / 16777216.0 < p
}
