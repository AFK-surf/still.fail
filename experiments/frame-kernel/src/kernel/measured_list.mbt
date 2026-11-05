// Geometry discovered by an optional frame is a memoized answer, never an
// estimate substituted into the meaning of a timed scroll. Distance is from a
// declared key's top. Resolving unknown crossed rows costs work; the contract
// exposes that cost rather than promising an impossible constant-time lookup.

///|
struct RowMetric {
  revision : Int
  width : Double
  height : Double
}

///|
struct MeasuredList {
  rows : Array[Cell[Intrinsic]]
  metrics : Map[Int, RowMetric]
  mut reads : Int
  mut measures : Int
}

///|
fn MeasuredList::new(rows : Array[Cell[Intrinsic]]) -> MeasuredList {
  { rows, metrics: {}, reads: 0, measures: 0 }
}

///|
fn MeasuredList::height(self : MeasuredList, i : Int, width : Double) -> Double {
  self.reads += 1
  let row = self.rows[i]
  let content = row.get()
  match self.metrics.get(i) {
    Some(m) if m.revision == row.revision && m.width == width => m.height
    _ => {
      self.measures += 1
      let height = content.height(width)
      guard height >= 0.0 && !height.is_inf() else { abort("a measured row must have a nonnegative finite height") }
      self.metrics[i] = { revision: row.revision, width, height }
      height
    }
  }
}

///|
fn MeasuredList::end_window(self : MeasuredList, width : Double, viewport : Double) -> Array[(Int, Box)] {
  let out : Array[(Int, Box)] = []
  let mut bottom = viewport
  let mut i = self.rows.length() - 1
  while i >= 0 && bottom > 0.0 {
    let h = self.height(i, width)
    bottom -= h
    out.push((i, { x: 0.0, y: bottom, width, height: h }))
    i -= 1
  }
  out.rev()
}

///|
fn MeasuredList::sample(self : MeasuredList, anchor : Int, distance : Double, width : Double, viewport : Double) -> Array[(Int, Box)] {
  let out : Array[(Int, Box)] = []
  if self.rows.is_empty() || viewport <= 0.0 { return out }
  guard anchor >= 0 && anchor < self.rows.length() else { abort("the anchor must name an existing row") }
  guard distance >= 0.0 else { abort("this slice samples forward from its anchor") }
  let mut i = anchor
  let mut top = -distance
  // A future index may skip already measured spans in logarithmic time. This
  // reference resolver deliberately keeps its O(crossed + visible) read bound.
  while i < self.rows.length() {
    let h = self.height(i, width)
    if top + h > 0.0 { break }
    top += h
    i += 1
  }
  if i == self.rows.length() {
    // A request beyond the end shows the end. Its last visible window needs no
    // scan over unrelated source history; every crossed row was required above.
    return self.end_window(width, viewport)
  }
  while i < self.rows.length() && top < viewport {
    let h = self.height(i, width)
    out.push((i, { x: 0.0, y: top, width, height: h }))
    top += h
    i += 1
  }
  if i == self.rows.length() && top < viewport {
    return self.end_window(width, viewport)
  }
  out
}
