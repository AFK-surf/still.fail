///|
test "list position ranges keep fractional boundaries independent of update order" {
  let tree = Tree::new(fn(_) { })
  defer { tree.dispose() }
  let row = fn(i : Int, h : Double) { (i, 0.0, h, true, list_room(h)) }
  let values = [0.1, 0.2, 0.0, 1.0 / 3.25, 42.0, 7.0 / 3.25]
  let a = ListTable::new(values.mapi(fn(i, h) { row(i, h) }), tree.work)
  let b = ListTable::new(values.mapi(fn(i, _) { row(i, 40.0) }), tree.work)
  let mut i = values.length() - 1
  while i >= 0 { b.set(i, row(i, values[i])); i -= 1 }
  for i in 0..<values.length() {
    assert_true(a.row(i) == b.row(i))
    assert_eq(a.first_from(a.top(i)), b.first_from(a.top(i)))
  }
  assert_eq(a.total(), b.total())
  assert_eq(a.first_from(0.0), 0)
  assert_eq(a.first_from(a.total() + 1.0), values.length())
  b.set(3, row(3, 99.0))
  b.set(3, row(3, values[3]))
  for i in 0..<values.length() { assert_true(a.row(i) == b.row(i)) }
}

///|
test "list position ranges preserve zero-height rows and measurement knowledge" {
  let tree = Tree::new(fn(_) { })
  defer { tree.dispose() }
  let rows = [(0, 0.0, 0.0, false, list_room(0.0)), (1, 0.0, 40.0, true, list_room(40.0)), (2, 0.0, 0.0, false, list_room(0.0))]
  let table = ListTable::new(rows, tree.work)
  assert_eq(table.first_from(0.0), 0)
  assert_eq(table.first_from(40.0), 1)
  assert_eq(table.top(2), 40.0)
  assert_eq(table.unknown, 2)
  table.set(0, (0, 0.0, 0.0, true, list_room(0.0)))
  assert_eq(table.unknown, 1)
  assert_eq(table.total(), 40.0)
  table.set(1, (1, 0.0, 80.0, true, list_room(80.0)))
  assert_eq(table.top(2), 80.0)
}
