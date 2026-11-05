// Time the reference computation on the development engine, never by making
// its model read a clock. No result here is an Android frame-time measurement.

///|
fn measure_case(now : () -> Double, label : String, run : (Int) -> Double) -> Unit {
  let mut count = 256
  let mut checksum = run(count)
  for _ in 0..<3 {
    let start = now()
    checksum += run(count)
    let elapsed = now() - start
    if elapsed >= 150.0 { break }
    let estimate = if elapsed > 0.0 { (300.0 * count.to_double() / elapsed).to_int() } else { 100000 }
    count = if estimate < 1 { 1 } else if estimate > 1000000 { 1000000 } else { estimate }
  }
  let samples : Array[Int] = []
  for _ in 0..<3 {
    let start = now()
    checksum += run(count)
    samples.push((now() - start).round().to_int())
  }
  guard checksum >= 0.0 else { abort("invalid benchmark output") }
  println("PERFCASE \{label} iterations=\{count} ms=\{samples} checksum=\{checksum}")
}

///|
pub fn benchmark_development_runtime(now : () -> Double) -> Unit {
  for count in [30, 3000] {
    let k = Kernel::new(count)
    k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
    let at = Ref(0)
    measure_case(now, "changed-row-\{count}", fn(n) {
      let mut sum = 0.0
      for _ in 0..<n {
        at.val += 1
        let t = at.val.to_double()
        k.commit(t, RowHeight(count - 1, if at.val % 2 == 0 { 40.0 } else { 80.0 }))
        sum += k.frame(t, t, 390.0, 844.0).layout.rows[0].1.height
      }
      sum
    })
    k.placement.release()
  }
  for fractional in [false, true] {
    let store = Store::new()
    let source = IndexedRows::new(store, Array::makei(3000, fn(i) {
      Fixed(if fractional { 40.0 + (i % 11).to_double() / 3.25 } else { 40.0 })
    }))
    let list = IndexedList::new(source)
    let base = 80000.0
    let query = store.query(fn(distance : Double) { list.sample(0, distance, 300.0, 100.0) })
    query.get(base + 30.0) |> ignore
    let at = Ref(0)
    measure_case(now, "indexed-scroll-3000-fractional-\{fractional}", fn(n) {
      let mut sum = 0.0
      for _ in 0..<n {
        at.val += 1
        let distance = base + (at.val % 30).to_double()
        sum += query.get(distance)[0].0.to_double()
      }
      sum
    })
    query.release()
  }
  let store = Store::new()
  let rows = Array::makei(3000, fn(_) { store.cell(Fixed(40.0), fn(a, b) { a == b }) })
  let linear = MeasuredList::new(rows)
  let query = store.query(fn(distance : Double) { linear.sample(0, distance, 300.0, 100.0) })
  query.get(80030.0) |> ignore
  let at = Ref(0)
  measure_case(now, "linear-reference-scroll-3000", fn(n) {
    let mut sum = 0.0
    for _ in 0..<n {
      at.val += 1
      sum += query.get(80000.0 + (at.val % 30).to_double())[0].0.to_double()
    }
    sum
  })
  query.release()
}
