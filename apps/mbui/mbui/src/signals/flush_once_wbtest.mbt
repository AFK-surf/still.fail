// A flush never runs inside another (signals.mbt's flush, end_batch, Signal::set): what an effect sets is run after
// it returns, in the order it was queued, each effect one deep however long the chain it starts.

///|
test "a chain of 1000 effects, each setting what the next reads, all run in order and none inside another" {
  let n = 1000
  let s = Array::makei(n + 1, fn(_) { signal(0) })
  let order : Array[Int] = []
  let stops = []
  for i in 0..<n {
    stops.push(effect(fn() {
      let v = s[i].get()
      if v > 0 {
        order.push(i)
        s[i + 1].set(v + 1)
      }
    }))
  }
  effect_nesting_most() |> ignore
  s[0].set(1)
  assert_eq(s[n].get(), n + 1)
  assert_eq(order, Array::makei(n, fn(i) { i }))
  assert_eq(effect_nesting_most(), 1)
  for stop in stops {
    stop()
  }
}

///|
test "a batch that writes inside an effect runs what it queued after that effect, not inside it" {
  let a = signal(0)
  let b = signal(0)
  let seen : Array[String] = []
  let stop_b = effect(fn() {
    let v = b.get()
    if v > 0 {
      seen.push("b \{v}")
    }
  })
  let stop_a = effect(fn() {
    let v = a.get()
    if v > 0 {
      start_batch()
      b.set(v)
      end_batch()
      seen.push("a \{v} done")
    }
  })
  effect_nesting_most() |> ignore
  a.set(5)
  assert_eq(seen, ["a 5 done", "b 5"])
  assert_eq(effect_nesting_most(), 1)
  stop_a()
  stop_b()
}

///|
test "two effects setting each other round are said, with the sets that queued them, at the 65th run of one" {
  let said : Array[String] = []
  effect_cycle_said.val = Some(fn(s) { said.push(s) })
  let a = signal(0)
  let b = signal(0)
  let stop_b = effect(fn() { b.set(a.get() + 1) })
  let stop_a = effect(fn() { a.set(b.get() + 1) })
  a.set(1)
  effect_cycle_said.val = None
  stop_a()
  stop_b()
  assert_eq(said.length(), 1)
  assert_true(said[0].contains("ran 64 times in one flush"))
  assert_true(said[0].contains("flush_once_wbtest.mbt"))
}
