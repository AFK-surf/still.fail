// Flushes run in each other only so deep (flush_deepest): past it, said with where they were set off.

///|
test "a chain of effects each writing in a batch what the next reads, longer than flushes may run deep: said, with the sets that set it off" {
  let said : Array[String] = []
  flush_too_deep_said.val = Some(fn(s) { said.push(s) })
  let n = flush_deepest + 16
  let cells = Array::makei(n + 1, fn(_) { signal(0) })
  let stops = Array::makei(n, fn(i) {
    effect(fn() {
      let v = cells[i].get()
      if v > 0 {
        start_batch()
        cells[i + 1].set(v)
        end_batch()
      }
    })
  })
  cells[0].set(1)
  flush_too_deep_said.val = None
  for s in stops {
    s()
  }
  assert_eq(said.length() > 0, true)
  assert_true(said[0].contains("flushes 64 deep"), msg=said[0])
  assert_true(said[0].contains("flush_deep_wbtest.mbt"), msg=said[0])
}

///|
test "a chain of effects as deep as flushes may run, and no deeper: run whole, nothing said" {
  let said : Array[String] = []
  flush_too_deep_said.val = Some(fn(s) { said.push(s) })
  let n = flush_deepest - 2
  let cells = Array::makei(n + 1, fn(_) { signal(0) })
  let stops = Array::makei(n, fn(i) {
    effect(fn() {
      let v = cells[i].get()
      if v > 0 {
        start_batch()
        cells[i + 1].set(v)
        end_batch()
      }
    })
  })
  cells[0].set(1)
  flush_too_deep_said.val = None
  for s in stops {
    s()
  }
  assert_eq(said, [])
  assert_eq(cells[n].get(), 1)
}

///|
test "two effects each setting what the other reads: said, with where the set going round was" {
  let said : Array[String] = []
  effect_round_said.val = fn(s) { said.push(s) }
  let a = signal(0)
  let b = signal(0)
  let s1 = effect(fn() { b.set(a.get() + 1) })
  let s2 = effect(fn() { a.set(b.get() + 1) })
  a.set(100)
  effect_round_said.val = fn(s) { abort(s) }
  s1()
  s2()
  assert_true(said.length() > 0, msg="nothing said; a \{a.get()}, b \{b.get()}")
  // (both effects named by where they were made, and the set going round)
  assert_true(said[0].contains("the effect made at"), msg=said[0])
  assert_true(said[0].contains("by the effect made at"), msg=said[0])
  assert_true(said[0].contains("flush_deep_wbtest.mbt"), msg=said[0])
}

///|
test "an effect setting what it read itself: run once, nothing said" {
  let said : Array[String] = []
  effect_round_said.val = fn(s) { said.push(s) }
  let a = signal(1)
  let s1 = effect(fn() {
    let v = a.get()
    if v < 3 {
      a.set(v + 1)
    }
  })
  effect_round_said.val = fn(s) { abort(s) }
  s1()
  assert_eq(said, [])
}

///|
test "an effect taking a flag it reads and putting it back, untracked: its own, nothing said" {
  let said : Array[String] = []
  effect_round_said.val = fn(s) { said.push(s) }
  let go = signal(false)
  let sent = Ref(0)
  let s1 = effect(fn() {
    if go.get() {
      untracked(fn() {
        go.set(false)
        sent.val += 1
      })
    }
  })
  go.set(true)
  effect_round_said.val = fn(s) { abort(s) }
  s1()
  assert_eq((said, sent.val, go.get()), ([], 1, false))
}
