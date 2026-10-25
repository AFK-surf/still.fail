// The conformance suite (conformance_graph_wbtest.mbt): Untracked / Unsampled Reads (untracked.ts) and Stale
// Evaluation Order (staleEvaluation.ts).

///|
test "untracked #75 untracked read in effect does not create dependency" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      fw_untracked(fn() { b.get() }) |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    // a is tracked — should trigger
    a.set(1)
    assert_eq(runs.val, 2)
    // b is untracked — should NOT trigger
    b.set(1)
    assert_eq(runs.val, 2)
  })
}

///|
test "untracked #76 untracked read in computed does not create dependency" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(10)
    let c = fw_computed(fn() { a.get() + fw_untracked(fn() { b.get() }) })
    assert_eq(c.get(), 10)
    // a is tracked
    a.set(1)
    assert_eq(c.get(), 11)
    // b is untracked — c should not re-evaluate
    b.set(20)
    assert_eq(c.get(), 11)
  })
}

///|
test "untracked #117 untracked read of stale computed returns fresh value" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() * 2 })
    assert_eq(b.get(), 0)
    a.set(5)
    let result = fw_untracked(fn() { b.get() })
    assert_eq(result, 10)
  })
}

///|
test "untracked #118 untracked transitively doesn't track through nested deps" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() * 2 })
    let effect_runs = Ref(0)
    fw_effect(fn() {
      fw_untracked(fn() { b.get() }) |> ignore
      effect_runs.val += 1
    })
    |> ignore
    assert_eq(effect_runs.val, 1)
    a.set(1)
    assert_eq(effect_runs.val, 1)
    a.set(2)
    assert_eq(effect_runs.val, 1)
  })
}

///|
test "untracked #156 untracked write inside effect doesn't throw" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    fw_effect(fn() {
      a.get() |> ignore
      fw_untracked(fn() { b.set(a.get() * 10) })
    })
    |> ignore
    assert_eq(b.get(), 0)
    a.set(1)
    assert_eq(b.get(), 10)
  })
}

///|
test "untracked #218 untracked read survives across batched writes" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      fw_untracked(fn() { b.get() }) |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() { b.set(1) })
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      b.set(2)
      a.set(1)
    })
    assert_eq(runs.val, 2)
  })
}

///|
test "untracked #219 batch inside untracked still coalesces writes" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_untracked(fn() {
      start_batch()
      a.set(1)
      a.set(2)
      a.set(3)
      end_batch()
    })
    assert_eq(runs.val, 2)
    assert_eq(a.get(), 3)
  })
}

// ── staleEvaluation.ts ──────────────────────────────────────────────────────────────────────────────────────

///|
test "stale #94 stale invocation does not trigger pending computations" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b_calls = Ref(0)
    let b = fw_computed(fn() {
      b_calls.val += 1
      a.get()
    })
    let c = fw_computed(fn() {
      a.get() |> ignore
      "c"
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      b.get().to_string() + " " + c.get()
    })
    assert_eq(d.get(), "0 c")
    b_calls.val = 0
    d_calls.val = 0
    a.set(1)
    assert_eq(d.get(), "1 c")
    assert_eq(b_calls.val, 1)
    assert_eq(d_calls.val, 1)
  })
}

///|
test "stale #95 stale computations evaluated before their dependees" {
  fw_run(fn() raise {
    let order : Array[String] = []
    let a = fw_signal(0)
    let b = fw_computed(fn() {
      order.push("b")
      a.get()
    })
    let c = fw_computed(fn() {
      order.push("c")
      b.get()
    })
    assert_eq(c.get(), 0)
    order.clear()
    a.set(1)
    assert_eq(c.get(), 1)
    assert_true(order.search("b").unwrap_or(-1) < order.search("c").unwrap_or(-1))
  })
}

///|
test "stale #158 stale chained computed accessed after update: values fresh" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() + 1 })
    let c = fw_computed(fn() { b.get() + 1 })
    let d = fw_computed(fn() { c.get() + 1 })
    assert_eq(d.get(), 3)
    a.set(10)
    assert_eq(b.get(), 11)
    assert_eq(c.get(), 12)
    assert_eq(d.get(), 13)
  })
}

///|
test "stale #159 pending computation created after dirty signal still updates" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() * 2 })
    a.set(5)
    let c = fw_computed(fn() { b.get() + 1 })
    assert_eq(c.get(), 11)
    a.set(10)
    assert_eq(c.get(), 21)
  })
}

///|
test "stale #97 flags indirectly updated during dirty-checking" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { b.get() })
    // d depends on both a and c
    let d = fw_computed(fn() { a.get() + c.get() })
    assert_eq(d.get(), 0)
    a.set(1)
    // a=1, b=1, c=1, d=1+1=2
    assert_eq(d.get(), 2)
  })
}
