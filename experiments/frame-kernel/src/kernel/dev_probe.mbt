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
}
