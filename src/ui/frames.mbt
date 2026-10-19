// A run as data (PocketJS has it so: docs/DETERMINISM.md there): what each frame drew as one number, so two runs of
// the same steps are compared frame by frame (the same, or the first frame they part at) rather than by their last
// screen alone, and a test that gives the same steps another order of what comes from outside (a seed, a replay's
// pace) can say the frames that should not change did not.

///|
fn hash_mix(h : Int64, v : Int64) -> Int64 {
  (h ^ v) * 1099511628211L
}

///|
/// What the last frame drew, as one number (FNV-1a): every instance drawn (where, how large, its kind and colour, in
/// 1/64 px and 1/255 steps) and the laid-out tree with its words and carets (`dump`). The same steps give the same
/// number on every run and every machine.
pub fn Tester::frame_hash(self : Tester) -> Int64 {
  let c = g()
  let mut h = -3750763034362895579L
  for k in 0..<(c.ninst * inst_size) {
    h = hash_mix(h, (c.inst[k] * 64.0).round().to_int64())
  }
  for ch in self.dump() {
    h = hash_mix(h, ch.to_int().to_int64())
  }
  h
}

///|
/// `n` frames, `ms` apart: each one's hash (`frame_hash`) as it was drawn.
pub fn Tester::frames(self : Tester, n : Int, ms? : Double = 16.0) -> Array[Int64] {
  let out : Array[Int64] = []
  for _ in 0..<n {
    self.frame(ms~)
    out.push(self.frame_hash())
  }
  out
}

///|
/// The first frame at which two runs' hashes part (None: the same, frame for frame; one longer than the other parts
/// where the shorter ends).
pub fn first_difference(a : Array[Int64], b : Array[Int64]) -> Int? {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return Some(i)
    }
  }
  if a.length() != b.length() {
    Some(n)
  } else {
    None
  }
}
