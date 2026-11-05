// A collection owns its range dependencies. An input changes one item through
// the collection; invalidation follows its logarithmic path without measuring
// anything. Pages do not maintain a second set of invalidation flags.

///|
struct IndexedRows {
  values : Array[Cell[Intrinsic]]
  versions : Array[Cell[Int]]
  capacity : Int
}

///|
fn IndexedRows::new(store : Store, values : Array[Intrinsic]) -> IndexedRows {
  let mut capacity = 1
  while capacity < values.length() { capacity *= 2 }
  {
    values: values.map(fn(v) { store.cell(v, fn(a, b) { a == b }) }),
    versions: Array::makei(capacity * 2, fn(_) { store.cell(0, fn(a, b) { a == b }) }),
    capacity,
  }
}

///|
fn IndexedRows::set(self : IndexedRows, tx : Transaction, i : Int, value : Intrinsic) -> Unit {
  if self.values[i].get() == value { return }
  self.values[i].set(tx, value)
  let mut node = self.capacity + i
  while node > 0 {
    self.versions[node].set(tx, self.versions[node].get() + 1)
    node /= 2
  }
}

///|
struct IndexedList {
  source : IndexedRows
  metrics : Map[Int, SpanMetric]
  mut nodes : Int
  mut reads : Int
  mut measures : Int
}

///|
enum Located {
  Within(Int, Extent)
  Across(Extent)
}

///|
struct SpanMetric {
  revision : Int
  width : Double
  height : Extent
}

///|
fn IndexedList::new(source : IndexedRows) -> IndexedList {
  { source, metrics: {}, nodes: 0, reads: 0, measures: 0 }
}

///|
fn IndexedList::stamp(self : IndexedList, node : Int) -> Int {
  // Checking cache validity is not using the cached result. Only a span that is
  // actually skipped becomes a dependency, so unrelated history stays unrelated.
  @signals.untracked(fn() { self.source.versions[node].get() })
}

///|
fn IndexedList::height(self : IndexedList, i : Int, width : Double) -> Double {
  self.reads += 1
  let content = self.source.values[i].get()
  let node = self.source.capacity + i
  let revision = self.stamp(node)
  match self.metrics.get(node) {
    Some(m) if m.revision == revision && m.width == width => m.height.to_double()
    _ => {
      self.measures += 1
      let height = content.height(width)
      guard height >= 0.0 && !height.is_inf() else { abort("a measured row must have a nonnegative finite height") }
      self.metrics[node] = { revision, width, height: Extent::of(height) }
      height
    }
  }
}

///|
fn IndexedList::locate(self : IndexedList, node : Int, start : Int, count : Int, anchor : Int, distance : Extent, width : Double) -> Located {
  self.nodes += 1
  if start + count <= anchor || start >= self.source.values.length() { return Across(Extent::of(0.0)) }
  if anchor <= start {
    match self.metrics.get(node) {
      Some(m) if m.width == width && m.revision == self.stamp(node) && m.height.at_most(distance) => {
        self.source.versions[node].get() |> ignore
        return Across(m.height)
      }
      _ => ()
    }
  }
  if count == 1 {
    let h = Extent::of(self.height(start, width))
    return if h.at_most(distance) { Across(h) } else { Within(start, distance) }
  }
  let half = count / 2
  let left = match self.locate(node * 2, start, half, anchor, distance, width) {
    Within(i, top) => return Within(i, top)
    Across(h) => h
  }
  let right = match self.locate(node * 2 + 1, start + half, half, anchor, distance.minus(left), width) {
    Within(i, top) => return Within(i, top)
    Across(h) => h
  }
  // Exact binary addition makes the cached interval independent of traversal
  // and addition order; the output coordinate is rounded only once.
  let height = left.add(right)
  if anchor <= start {
    self.metrics[node] = { revision: self.stamp(node), width, height }
  }
  Across(height)
}

///|
fn IndexedList::end_window(self : IndexedList, width : Double, viewport : Double) -> Array[(Int, Box)] {
  let out : Array[(Int, Box)] = []
  let mut bottom = viewport
  let mut i = self.source.values.length() - 1
  while i >= 0 && bottom > 0.0 {
    let h = self.height(i, width)
    bottom -= h
    out.push((i, { x: 0.0, y: bottom, width, height: h }))
    i -= 1
  }
  out.rev()
}

///|
fn IndexedList::sample(self : IndexedList, anchor : Int, distance : Double, width : Double, viewport : Double) -> Array[(Int, Box)] {
  let out : Array[(Int, Box)] = []
  if self.source.values.is_empty() || viewport <= 0.0 { return out }
  guard anchor >= 0 && anchor < self.source.values.length() else { abort("the anchor must name an existing row") }
  guard distance >= 0.0 && !distance.is_inf() else { abort("the distance must be nonnegative and finite") }
  let (first, y) = match self.locate(1, 0, self.source.capacity, anchor, Extent::of(distance), width) {
    Within(i, remaining) => (i, -remaining.to_double())
    Across(_) => return self.end_window(width, viewport)
  }
  let mut top = y
  let mut i = first
  while i < self.source.values.length() && top < viewport {
    let h = self.height(i, width)
    out.push((i, { x: 0.0, y: top, width, height: h }))
    top += h
    i += 1
  }
  if i == self.source.values.length() && top < viewport {
    return self.end_window(width, viewport)
  }
  out
}
