// A bounded classic-Wasm executable probe, separate from the Wasm-GC tests.
// It exercises the actual module under the development host's Wasmtime stack
// budget. It does not draw Android pixels or measure Android frame times.

///|
pub fn check_development_runtime() -> Unit {
  for count in [30, 3000] {
    for _ in 0..<25 {
      let k = Kernel::new(count)
      k.frame(0.0, 0.0, 350.7692307692308, 804.9230769230769) |> ignore
      k.commit(100.0, Composer(100.0))
      k.commit(100.0, RowHeight(count - 1, 80.0))
      k.commit(100.0, Leave(390.0, @motion.spring()))
      k.frame(170.0, 178.0, 350.7692307692308, 804.9230769230769) |> ignore
      let before = k.page.sample(180.0)
      k.commit(180.0, Return(@motion.spring()))
      guard k.page.sample(180.0) == before else { abort("interruption changed its initial condition") }
      let p = k.frame(250.0, 258.0, 350.7692307692308, 804.9230769230769)
      guard p.layout.composer.y == p.layout.viewport.height else { abort("sibling constraints disagree") }
      guard p.layout.rows[0].1.height == 80.0 else { abort("the changed row was not measured") }
      k.placement.release()
    }
    let store = Store::new()
    let rows = Array::makei(count, fn(i) {
      store.cell(Fixed(if i % 2 == 1 { 80.0 } else { 40.0 }), fn(a, b) { a == b })
    })
    let list = MeasuredList::new(rows)
    let query = store.query(fn(t : Int) { list.sample(0, t.to_double(), 300.0, 100.0) })
    let first = query.get(1000)
    guard first.map(fn(row) { row.0 }) == [17, 18] else { abort("timed scrolling changed its meaning") }
    query.release()
    println("classic Wasm: rows=\{count} cycles=25 layout/motion/scroll contracts passed")
  }
  let store = Store::new()
  let source = IndexedRows::new(store, Array::makei(3000, fn(_) { Fixed(40.0) }))
  let index = IndexedList::new(source)
  let query = store.query(fn(distance : Double) { index.sample(0, distance, 300.0, 100.0) })
  query.get(80000.0) |> ignore
  let reads = index.reads
  let nodes = index.nodes
  let measures = index.measures
  let shown = query.get(80001.0)
  guard shown.map(fn(row) { row.0 }) == [2000, 2001, 2002] else { abort("indexed history changed the window") }
  guard index.reads - reads <= 4 else { abort("indexed history was reread") }
  println("classic Wasm: indexed warm read_rows=\{index.reads - reads} visited_spans=\{index.nodes - nodes} measured_rows=\{index.measures - measures}")
  store.commit(100.0, fn(tx) { source.set(tx, 10, Fixed(80.0)) })
  guard index.measures == measures else { abort("a write performed geometry work") }
  let changed = query.get(80001.0)
  guard changed.map(fn(row) { row.0 }) == [1999, 2000, 2001] else { abort("a changed crossed span was ignored") }
  guard index.measures - measures == 1 else { abort("a row change measured unrelated history") }
  query.release()
  let k = Kernel::new(30)
  k.commit(100.0, Leave(390.0, Snap(0.0)))
  guard !k.alive && k.owner_released_at == Some(100.0) else { abort("an immediate exit escaped its cause") }
  println("classic Wasm: indexed invalidation and immediate owner completion passed")
}
