// A chain of effects, each setting what the next reads (a page let go telling its rows, each row what it holds): run
// one after another by the one flush under way, none inside another's run, so the stack is as deep for a chain of a
// thousand as for a chain of two.

///|
test "effects setting what the next reads run one after another, never one inside another" {
  let n = 1000
  let cells = Array::makei(n, fn(_) { @signals.signal(0) })
  let depth = Ref(0)
  let most = Ref(0)
  let order : Array[Int] = []
  let stops = []
  for i in 0..<(n - 1) {
    stops.push(
      @signals.effect(fn() {
        let v = cells[i].get()
        if v > 0 {
          depth.val += 1
          if depth.val > most.val {
            most.val = depth.val
          }
          order.push(i)
          cells[i + 1].set(v)
          depth.val -= 1
        }
      }),
    )
  }
  cells[0].set(7)
  assert_eq(cells[n - 1].get(), 7)
  assert_eq(order.length(), n - 1)
  assert_eq(order[0], 0)
  assert_eq(order[n - 2], n - 2)
  // (each run done before the next is begun)
  assert_eq(most.val, 1)
  for s in stops {
    s()
  }
}

///|
test "a batch written inside an effect is run after it, in its turn, not inside it" {
  let a = @signals.signal(0)
  let b = @signals.signal(0)
  let seen : Array[String] = []
  let s1 = @signals.effect(fn() {
    let v = a.get()
    if v > 0 {
      seen.push("a \{v} begins")
      @signals.start_batch()
      b.set(v * 10)
      @signals.end_batch()
      seen.push("a \{v} ends")
    }
  })
  let s2 = @signals.effect(fn() {
    let v = b.get()
    if v > 0 {
      seen.push("b \{v}")
    }
  })
  a.set(1)
  assert_eq(seen, ["a 1 begins", "a 1 ends", "b 10"])
  s1()
  s2()
}
