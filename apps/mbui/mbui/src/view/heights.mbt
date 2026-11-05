// How tall each of a list's blocks is counted, in their order, kept so that where any of them starts, which lies at a
// point down the column and how tall all of them are is had without going through them all (a Fenwick tree of their
// heights): a block measured anew changes its own count and the sums over it alone, in steps as many as the bits of
// how many there are. A chat of 3000 rows: twelve steps to find where the row in sight starts, or to count a row
// measured anew, where summing them all again took 3000 for each (list_window.mbt's tops, 2026-11-04).
// Counted in whole 65536ths of a point: the sums are exact, the same whatever order the blocks were measured in (what
// a frame rate or a jump of time changes), where adding and taking back fractions of points leaves a different last
// bit for each order.

///|
/// How many parts of a point a height is counted in (Heights).
let heights_unit : Double = 65536.0

///|
/// `h` points in heights_unit's parts, to the nearest.
fn heights_parts(h : Double) -> Int64 {
  (h * heights_unit).round().to_int64()
}

///|
/// The heights of a list's blocks in order, each as counted now, and their sums by the Fenwick tree's ranges.
pub struct Heights {
  /// each block's own, by its place
  priv own : Array[Int64]
  /// the Fenwick tree's partial sums, 1-based: sums[i] the sum of own[i - lowbit(i) .. i - 1]
  priv sums : Array[Int64]
  /// all of them summed
  priv mut all : Int64
}

///|
/// `n` blocks each counted `height` tall.
pub fn Heights::new(n : Int, height : Double) -> Heights {
  Heights::of(Array::make(n, height))
}

///|
/// The blocks counted as `own` has them, in order.
pub fn Heights::of(own : Array[Double]) -> Heights {
  let n = own.length()
  let parts = own.map(heights_parts)
  let sums : Array[Int64] = Array::make(n + 1, 0L)
  let mut all = 0L
  // (each range's sum handed up to the one over it: the tree made in one pass)
  for i in 1..=n {
    sums[i] = sums[i] + parts[i - 1]
    all = all + parts[i - 1]
    let up = i + (i & -i)
    if up <= n {
      sums[up] = sums[up] + sums[i]
    }
  }
  { own: parts, sums, all }
}

///|
/// How many blocks there are.
pub fn Heights::length(self : Heights) -> Int {
  self.own.length()
}

///|
/// How tall block `i` is counted.
pub fn Heights::get(self : Heights, i : Int) -> Double {
  self.own[i].to_double() / heights_unit
}

///|
/// Block `i` counted `h` tall: what it changes by is had by the sums over it alone.
pub fn Heights::set(self : Heights, i : Int, h : Double) -> Unit {
  let p = heights_parts(if h > 0.0 { h } else { 0.0 })
  let d = p - self.own[i]
  if d == 0L {
    return
  }
  self.own[i] = p
  self.all = self.all + d
  let n = self.own.length()
  let mut k = i + 1
  while k <= n {
    self.sums[k] = self.sums[k] + d
    k = k + (k & -k)
  }
}

///|
/// Where block `i` starts: how tall those before it are, all of them (`i` as many as there are: where the last ends).
pub fn Heights::top(self : Heights, i : Int) -> Double {
  let mut s = 0L
  let mut k = if i > self.own.length() { self.own.length() } else { i }
  while k > 0 {
    s = s + self.sums[k]
    k = k - (k & -k)
  }
  s.to_double() / heights_unit
}

///|
/// How tall all of them are.
pub fn Heights::total(self : Heights) -> Double {
  self.all.to_double() / heights_unit
}

///|
/// The block that lies at `y` down the column: the first whose foot is under `y` (one ending at `y`, or as tall as
/// nothing there, lies before it), by halving the tree's ranges; how many there are where all of them end at `y` or
/// over it; 0 where `y` is over the top.
pub fn Heights::at(self : Heights, y : Double) -> Int {
  if y < 0.0 {
    return 0
  }
  self.past(heights_parts(y), true)
}

///|
/// The first block whose foot is at `y` or under it (one ending at `y`, or as tall as nothing there, is it); how many
/// there are where all of them end over `y`; 0 where `y` is at the top or over it.
pub fn Heights::reaching(self : Heights, y : Double) -> Int {
  if y <= 0.0 {
    return 0
  }
  self.past(heights_parts(y), false)
}

///|
/// The most blocks whose sum is no more than `parts` (`even`; else less than it), by halving the tree's ranges: the one
/// after them is the first whose foot is past it (or at it).
fn Heights::past(self : Heights, parts : Int64, even : Bool) -> Int {
  let n = self.own.length()
  let mut step = 1
  while step * 2 <= n {
    step = step * 2
  }
  let mut k = 0
  let mut rest = parts
  while step > 0 {
    let next = k + step
    if next <= n && (self.sums[next] < rest || (even && self.sums[next] == rest)) {
      k = next
      rest = rest - self.sums[next]
    }
    step = step / 2
  }
  k
}
