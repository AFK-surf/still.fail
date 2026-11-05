///|
test "indexed scrolling has identical geometry under cold, dense and partly warm measurement" {
  let run = fn(step : Int, anchor : Int, distance : Double, fractional : Bool) {
    let store = Store::new()
    let source = IndexedRows::new(store, Array::makei(3000, fn(i) {
      Fixed(if fractional { (1.0 + (i % 11).to_double()) / 3.25 } else if i % 2 == 0 { 40.0 } else { 80.0 })
    }))
    let list = IndexedList::new(source)
    let project = store.query(fn(distance : Double) { list.sample(anchor, distance, 350.7692307692308, 100.0) })
    defer { project.release() }
    if step > 0 {
      for at = 0; at.to_double() < distance; at = at + step { project.get(at.to_double()) |> ignore }
    }
    project.get(distance)
  }
  for fractional in [false, true] {
    for anchor in [0, 17, 2500] {
      for distance in [0.0, 100.0, 1000.0, 1013.25, 100000.0] {
        let cold = run(0, anchor, distance, fractional)
        assert_eq(cold, run(13, anchor, distance, fractional))
        assert_eq(cold, run(127, anchor, distance, fractional))
      }
    }
  }
  assert_eq(run(0, 0, 1000.0, false).map(fn(row) { row.0 }), [17, 18])
}

///|
test "a changed skipped span invalidates locally while unrelated history does not" {
  let store = Store::new()
  let source = IndexedRows::new(store, Array::makei(3000, fn(_) { Fixed(40.0) }))
  let list = IndexedList::new(source)
  let project = store.query(fn(distance : Double) { list.sample(0, distance, 300.0, 100.0) })
  defer { project.release() }
  project.get(80000.0) |> ignore
  let warmed = project.get(80001.0)
  let measures = list.measures
  let runs = project.runs
  store.commit(100.0, fn(tx) { source.set(tx, 2999, Fixed(80.0)) })
  assert_eq(project.get(80001.0), warmed)
  assert_eq(project.runs, runs)
  store.commit(200.0, fn(tx) { source.set(tx, 10, Fixed(80.0)) })
  // Writes only invalidate: no geometry calculation is allowed here.
  assert_eq(list.measures, measures)
  let reads = list.reads
  let nodes = list.nodes
  let changed = project.get(80001.0)
  assert_eq(changed.map(fn(row) { row.0 }), [1999, 2000, 2001])
  assert_eq(changed[0].1.y, -1.0)
  assert_eq(list.measures - measures, 1)
  assert_true(list.reads - reads <= 5)
  assert_true(list.nodes - nodes <= 64)
}

///|
test "jumping to a key does not measure or observe preceding history" {
  let store = Store::new()
  let source = IndexedRows::new(store, Array::makei(3000, fn(_) { Fixed(40.0) }))
  let list = IndexedList::new(source)
  let project = store.query(fn(_ : Unit) { list.sample(2500, 0.0, 300.0, 100.0) })
  defer { project.release() }
  let shown = project.get(())
  assert_eq(shown.map(fn(row) { row.0 }), [2500, 2501, 2502])
  assert_eq(list.measures, 3)
  store.commit(100.0, fn(tx) { source.set(tx, 10, Fixed(800.0)) })
  assert_eq(project.get(()), shown)
  assert_eq(project.runs, 1)
}

///|
test "warming a fractional span cannot change a boundary's visible rows" {
  let run = fn(warm : Bool) {
    let store = Store::new()
    let source = IndexedRows::new(store, [Fixed(0.7), Fixed(0.1), Fixed(1.0), Fixed(1.0)])
    let list = IndexedList::new(source)
    if warm { list.sample(0, 0.9, 300.0, 0.5) |> ignore }
    list.sample(0, 0.7999999999999999, 300.0, 0.5)
  }
  assert_eq(run(false), run(true))
}
