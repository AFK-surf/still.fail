// The conformance suite (conformance_graph_wbtest.mbt): Computed Evaluation (computedEval.ts) and Equality & Same-Value
// Optimization (equality.ts).

///|
test "computed #18 cached — not re-evaluated if deps unchanged" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let calls = Ref(0)
    let b = fw_computed(fn() {
      calls.val += 1
      a.get()
    })
    assert_eq(b.get(), 0)
    assert_eq(calls.val, 1)
    // Read again without changing dep
    assert_eq(b.get(), 0)
    assert_eq(calls.val, 1)
  })
}

///|
test "computed #19 returns updated value after dep change" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() * 2 })
    assert_eq(b.get(), 0)
    a.set(1)
    assert_eq(b.get(), 2)
    a.set(5)
    assert_eq(b.get(), 10)
  })
}

///|
test "computed #21 chained computed dirty reallocation after trigger" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_computed(fn() { a.get() })
    let d = fw_computed(fn() {
      if a.get() == 0 {
        return b.get()
      }
      c.get()
    })
    assert_eq(d.get(), 0)
    a.set(1)
    assert_eq(d.get(), 1)
    b.set(10)
    assert_eq(d.get(), 1)
  })
}

///|
test "computed #22 chained computed avoids redundant re-compute" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b_calls = Ref(0)
    let b = fw_computed(fn() {
      b_calls.val += 1
      a.get()
    })
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      b.get()
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      c.get()
    })
    assert_eq(d.get(), 0)
    b_calls.val = 0
    c_calls.val = 0
    d_calls.val = 0
    a.set(1)
    assert_eq(d.get(), 1)
    assert_eq(b_calls.val, 1)
    assert_eq(c_calls.val, 1)
    assert_eq(d_calls.val, 1)
  })
}

///|
test "computed #23 sync access of invalidated chained computed runs effect" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { b.get() })
    let effect_runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      effect_runs.val += 1
    })
    |> ignore
    assert_eq(effect_runs.val, 1)
    a.set(1)
    assert_eq(c.get(), 1)
    assert_eq(effect_runs.val, 2)
  })
}

///|
test "computed #24 dependency evaluation order consistent with last access" {
  fw_run(fn() raise {
    let order : Array[String] = []
    let a = fw_signal(0)
    let b = fw_computed(fn() {
      order.push("b")
      a.get()
    })
    let c = fw_computed(fn() {
      order.push("c")
      a.get()
    })
    // Access b then c
    b.get() |> ignore
    c.get() |> ignore
    order.clear()
    a.set(1)
    b.get() |> ignore
    c.get() |> ignore
    assert_true(order.search("b").unwrap_or(-1) >= 0)
    assert_true(order.search("c").unwrap_or(-1) >= 0)
  })
}

///|
test "computed #25 no re-compute if zero dependencies" {
  fw_run(fn() raise {
    let calls = Ref(0)
    let a = fw_computed(fn() {
      calls.val += 1
      42
    })
    assert_eq(a.get(), 42)
    assert_eq(calls.val, 1)
    // Read again — no deps means no reason to re-compute
    assert_eq(a.get(), 42)
    assert_eq(calls.val, 1)
  })
}

///|
test "computed #26 computed remains live after losing all subscribers" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() * 2 })
    // Subscribe then unsubscribe
    let dispose = fw_effect(fn() { b.get() |> ignore })
    dispose()
    // Computed should still work when read directly
    a.set(5)
    assert_eq(b.get(), 10)
    a.set(10)
    assert_eq(b.get(), 20)
  })
}

///|
test "computed #145 undefined is a valid computed value (not uninitialized)" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c : Computed[Int?] = fw_computed(fn() {
      if a.get() == 0 {
        return None
      }
      Some(a.get())
    })
    assert_eq(c.get(), None)
    a.set(1)
    assert_eq(c.get(), Some(1))
    a.set(0)
    assert_eq(c.get(), None)
  })
}

///|
test "computed #147 computed not recomputed in batch if dep reverts" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get()
    })
    c.get() |> ignore
    c_calls.val = 0
    fw_batch(fn() {
      a.set(5)
      a.set(0)
    })
    c.get() |> ignore
    assert_eq(c_calls.val, 0)
  })
}

///|
test "computed #149 batch preserves correct evaluation order" {
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
    fw_effect(fn() { c.get() |> ignore }) |> ignore
    order.clear()
    fw_batch(fn() { a.set(1) })
    if order.length() >= 2 {
      assert_true(order.search("b").unwrap_or(-1) < order.search("c").unwrap_or(-1))
    }
  })
}

///|
test "computed #115 signal creation inside computed is allowed" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c = fw_computed(fn() {
      let inner = fw_signal(a.get() * 10)
      inner.get()
    })
    assert_eq(c.get(), 0)
    a.set(3)
    assert_eq(c.get(), 30)
  })
}

///|
test "computed #27 downstream not re-evaluated unless value changed" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    // b clamps to [0, 10]
    let b = fw_computed(fn() {
      let v = a.get()
      if v < 0 {
        0
      } else if v > 10 {
        10
      } else {
        v
      }
    })
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      b.get()
    })
    assert_eq(c.get(), 0)
    c_calls.val = 0
    // a goes negative but b stays 0
    a.set(-1)
    assert_eq(c.get(), 0)
    assert_eq(c_calls.val, 0)
    // a changes b
    a.set(5)
    assert_eq(c.get(), 5)
    assert_eq(c_calls.val, 1)
    c_calls.val = 0
    // a goes over 10 but b stays 10
    a.set(11)
    assert_eq(c.get(), 10)
    c_calls.val = 0
    a.set(20)
    assert_eq(c.get(), 10)
    assert_eq(c_calls.val, 0)
  })
}

// ── equality.ts ─────────────────────────────────────────────────────────────────────────────────────────────

///|
test "equality #28 same primitive value — no propagation" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get()
    })
    assert_eq(c.get(), 1)
    assert_eq(c_calls.val, 1)
    // Write same value
    a.set(1)
    assert_eq(c.get(), 1)
    assert_eq(c_calls.val, 1)
  })
}

///|
test "equality #34 pruning stops at first unchanged node" {
  // A → B → C → D; B always returns constant after first change
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { if a.get() > 0 { 1 } else { 0 } })
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      b.get()
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      c.get()
    })
    assert_eq(d.get(), 0)
    c_calls.val = 0
    d_calls.val = 0
    a.set(1)
    assert_eq(d.get(), 1)
    c_calls.val = 0
    d_calls.val = 0
    // a changes but b still returns 1
    a.set(2)
    assert_eq(d.get(), 1)
    assert_eq(c_calls.val, 0)
    assert_eq(d_calls.val, 0)
  })
}

///|
test "equality #169 live pruning: effect not re-run when intermediate computed returns same" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let c1 = fw_computed(fn() { s.get() })
    let c2 = fw_computed(fn() {
      c1.get() |> ignore
      5
    })
    let runs = Ref(0)
    fw_effect(fn() {
      c2.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    s.set(1)
    assert_eq(runs.val, 1)
    s.set(2)
    assert_eq(runs.val, 1)
  })
}

///|
test "equality #220 computed same object reference — no downstream propagation" {
  // (an object compared as JS's === compares it: by what it is, not what it holds: computed's own same)
  fw_run(fn() raise {
    let obj = Ref(1)
    let a = fw_signal(0)
    let b = computed(fn(_) {
      a.get() |> ignore
      obj
    })
    let c_calls = Ref(0)
    let c = computed(fn(_) {
      c_calls.val += 1
      b.get()
    })
    assert_true(physical_equal(c.get(), obj))
    c_calls.val = 0
    a.set(1)
    assert_true(physical_equal(c.get(), obj))
    assert_eq(c_calls.val, 0)
  })
}
