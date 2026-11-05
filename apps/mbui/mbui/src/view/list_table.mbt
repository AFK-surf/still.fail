// Rows own their extents. Changing one height updates its path through the
// interval tree; positions are read only for the rows the window asks about.
// No prefix array is copied or rebuilt on a measurement or animation sample.

///|
priv struct ListTable[K] {
  rows : Array[(K, Double, Double, Bool, ListRoom)]
  spans : Array[ListExtent]
  capacity : Int
  tops : Array[(Int, Double)]
  work : Work
  mut revision : Int
  mut unknown : Int
}

///|
fn[K] ListTable::new(rows : Array[(K, Double, Double, Bool, ListRoom)], work : Work) -> ListTable[K] {
  let mut capacity = 1
  while capacity < rows.length() { capacity *= 2 }
  let spans = Array::make(capacity * 2, ListExtent::of(0.0))
  let mut unknown = 0
  for i, row in rows {
    work.list_rows += 1
    spans[capacity + i] = ListExtent::of(row.2)
    if !row.3 { unknown += 1 }
  }
  let mut node = capacity - 1
  while node > 0 {
    work.list_spans += 1
    spans[node] = spans[node * 2].add(spans[node * 2 + 1])
    node -= 1
  }
  { rows, spans, capacity, tops: Array::make(rows.length(), (-1, 0.0)), work, revision: 0, unknown }
}

///|
fn[K] ListTable::length(self : ListTable[K]) -> Int { self.rows.length() }

///|
fn[K] ListTable::set(self : ListTable[K], i : Int, row : (K, Double, Double, Bool, ListRoom)) -> Unit {
  let was = self.rows[i]
  self.rows[i] = row
  self.work.list_rows += 1
  if was.3 != row.3 { self.unknown += if row.3 { -1 } else { 1 } }
  if was.2 == row.2 { return }
  self.revision += 1
  let mut node = self.capacity + i
  self.spans[node] = ListExtent::of(row.2)
  node /= 2
  while node > 0 {
    self.work.list_spans += 1
    self.spans[node] = self.spans[node * 2].add(self.spans[node * 2 + 1])
    node /= 2
  }
}

///|
fn[K] ListTable::top(self : ListTable[K], i : Int) -> Double {
  if i == 0 { return 0.0 }
  if i == self.capacity { return self.spans[1].to_double() }
  if i < self.rows.length() && self.tops[i].0 == self.revision { return self.tops[i].1 }
  let mut sum = ListExtent::of(0.0)
  let mut node = self.capacity + i
  while node > 1 {
    self.work.list_spans += 1
    if (node & 1) != 0 { sum = sum.add(self.spans[node - 1]) }
    node /= 2
  }
  let top = sum.to_double()
  if i < self.rows.length() { self.tops[i] = (self.revision, top) }
  top
}

///|
fn[K] ListTable::row(self : ListTable[K], i : Int) -> (K, Double, Double, Bool, ListRoom) {
  let (key, _, height, known, room) = self.rows[i]
  (key, self.top(i), height, known, room)
}

///|
fn[K] ListTable::get(self : ListTable[K], i : Int) -> (K, Double, Double, Bool, ListRoom)? {
  if i >= 0 && i < self.length() { Some(self.row(i)) } else { None }
}

///|
fn[K] ListTable::last(self : ListTable[K]) -> (K, Double, Double, Bool, ListRoom)? {
  self.get(self.length() - 1)
}

///|
fn[K] ListTable::total(self : ListTable[K]) -> Double { self.spans[1].to_double() }

///|
// The first row whose foot reaches x, including zero-height rows at a boundary.
fn[K] ListTable::first_from(self : ListTable[K], x : Double) -> Int {
  if self.length() == 0 || x <= 0.0 { return 0 }
  if self.total() < x { return self.length() }
  let mut node = 1
  let mut top = ListExtent::of(0.0)
  while node < self.capacity {
    self.work.list_spans += 1
    let boundary = top.add(self.spans[node * 2])
    if boundary.to_double() < x {
      top = boundary
      node = node * 2 + 1
    } else {
      node *= 2
    }
  }
  let i = node - self.capacity
  if i < self.length() { self.tops[i] = (self.revision, top.to_double()) }
  i
}
