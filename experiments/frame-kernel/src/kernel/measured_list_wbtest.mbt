///|
test "the same variable-height timed scroll resolves the same rows with dense or sparse frames" {
  let run = fn(step : Int, count : Int) {
    let store = Store::new()
    let rows = Array::makei(count, fn(i) {
      store.cell(Fixed(if i % 2 == 1 { 80.0 } else { 40.0 }), fn(a, b) { a == b })
    })
    let list = MeasuredList::new(rows)
    let project = store.query(fn(at : Int) { list.sample(0, at.to_double(), 300.0, 100.0) })
    defer { project.release() }
    project.get(0) |> ignore
    if step > 0 {
      for at = step; at < 1000; at = at + step { project.get(at) |> ignore }
    }
    let shown = project.get(1000)
    (shown, list.measures)
  }
  let sparse = run(0, 100)
  assert_eq(sparse, run(10, 100))
  assert_eq(sparse.0.map(fn(row) { row.0 }), [17, 18])
  assert_eq(sparse.0[0].1.y, 0.0)
  assert_eq(sparse.0[1].1.y, 80.0)
  assert_eq(run(0, 30), run(0, 3000))
}

///|
test "the anchor skips preceding history and a changed crossed height invalidates its projection" {
  let store = Store::new()
  let rows = Array::makei(3000, fn(_) {
    store.cell(Fixed(40.0), fn(a, b) { a == b })
  })
  let list = MeasuredList::new(rows)
  let project = store.query(fn(_ : Unit) { list.sample(2500, 100.0, 300.0, 100.0) })
  defer { project.release() }
  let first = project.get(())
  assert_eq(first.map(fn(row) { row.0 }), [2502, 2503, 2504])
  assert_eq(list.measures, 5)
  // Off the causal path: the current anchor and requested distance ignore it.
  store.commit(100.0, fn(tx) { rows[10].set(tx, Fixed(800.0)) })
  assert_eq(project.get(()), first)
  assert_eq(project.runs, 1)
  // On the crossed path: the same requested distance now resolves another row.
  store.commit(200.0, fn(tx) { rows[2500].set(tx, Fixed(80.0)) })
  let changed = project.get(())
  assert_eq(changed.map(fn(row) { row.0 }), [2501, 2502, 2503])
  assert_eq(project.runs, 2)
  assert_eq(list.measures, 6)
}

///|
test "a requested distance near or beyond the end keeps the final window filled" {
  let store = Store::new()
  let rows = Array::makei(3, fn(_) { store.cell(Fixed(40.0), fn(a, b) { a == b }) })
  let list = MeasuredList::new(rows)
  let at_end = list.sample(0, 20.0, 300.0, 100.0)
  assert_eq(at_end.map(fn(row) { (row.0, row.1.y) }), [(0, -20.0), (1, 20.0), (2, 60.0)])
  assert_eq(list.sample(0, 21.0, 300.0, 100.0), at_end)
  assert_eq(list.sample(0, 1000.0, 300.0, 100.0), at_end)
}
