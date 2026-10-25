// The conformance suite (conformance_graph_wbtest.mbt): Batching / Transaction (batching.ts). #69 and #121 are not
// here: they throw out of a batch and an effect, and nothing here throws.

///|
test "batch #66 nested batches: outer completion triggers propagation" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() raise {
      a.set(1)
      fw_batch(fn() { a.set(2) })
      // Inner batch complete but outer still open
      assert_eq(runs.val, 1)
      a.set(3)
    })
    assert_eq(runs.val, 2)
    assert_eq(a.get(), 3)
  })
}

///|
test "batch #67 signals readable with updated value inside batch" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    fw_batch(fn() raise {
      a.set(1)
      assert_eq(a.get(), 1)
      a.set(2)
      assert_eq(a.get(), 2)
    })
  })
}

///|
test "batch #70 effect first run is immediate even inside batch" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_batch(fn() raise {
      fw_effect(fn() {
        a.get() |> ignore
        runs.val += 1
      })
      |> ignore
      assert_eq(runs.val, 1)
    })
  })
}

///|
test "batch #72 intermediate values skipped (only final value observed)" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let values : Array[Int] = []
    fw_effect(fn() { values.push(a.get()) }) |> ignore
    assert_eq(values, [0])
    fw_batch(fn() {
      a.set(1)
      a.set(2)
      a.set(3)
    })
    assert_eq(values, [0, 3])
  })
}

///|
test "batch #119 batch: computed same result despite source change — no effect run" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_computed(fn() { a.get() + b.get() })
    let runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    assert_eq(c.get(), 0)
    fw_batch(fn() {
      a.set(1)
      b.set(-1)
    })
    assert_eq(c.get(), 0)
    assert_eq(runs.val, 1)
  })
}

///|
test "batch #120 cleanup writes inside effect are implicitly batched" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let log : Array[String] = []
    effect_cleanup(fn() {
      a.get() |> ignore
      fn() { b.set(a.get()) }
    })
    |> ignore
    fw_effect(fn() { log.push("b:" + b.get().to_string()) }) |> ignore
    log.clear()
    a.set(1)
    assert_true(log.length() >= 1)
    assert_eq(log[log.length() - 1], "b:1")
  })
}

///|
test "batch #122 post-batch writes work normally" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() { a.set(1) })
    assert_eq(runs.val, 2)
    a.set(2)
    assert_eq(runs.val, 3)
    assert_eq(a.get(), 2)
  })
}

///|
test "batch #123 repeated no-op batches don't re-trigger effects" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(1)
      a.set(0)
    })
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(2)
      a.set(0)
    })
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(3)
      a.set(0)
    })
    assert_eq(runs.val, 1)
  })
}

///|
test "batch #124 trigger+dispose+retrigger in batch = no run" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    let dispose = fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(1)
      dispose()
      a.set(2)
    })
    assert_eq(runs.val, 1)
  })
}

///|
test "batch #125 batch: source reverts → computed not notified" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c = fw_computed(fn() { a.get() * 2 })
    let runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(5)
      a.set(0)
    })
    assert_eq(runs.val, 1)
    assert_eq(c.get(), 0)
  })
}

///|
test "batch #126 new effect inside batch after write sees updated value" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let seen = Ref(-1)
    fw_batch(fn() {
      a.set(42)
      fw_effect(fn() { seen.val = a.get() }) |> ignore
    })
    assert_eq(seen.val, 42)
  })
}

///|
test "batch #127 unsubscribe inside batch: not called at end" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    let dispose = fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(1)
      dispose()
    })
    assert_eq(runs.val, 1)
  })
}

///|
test "batch #128 reading computed in batch forces upstream evaluation" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() + 1 })
    let c = fw_computed(fn() { b.get() * 2 })
    fw_batch(fn() raise {
      a.set(5)
      assert_eq(c.get(), 12)
      assert_eq(b.get(), 6)
    })
  })
}

///|
test "batch #129 reading one computed doesn't notify sibling effect early" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c1 = fw_computed(fn() { a.get() + 1 })
    let c2 = fw_computed(fn() { a.get() * 2 })
    let c2_runs = Ref(0)
    fw_effect(fn() {
      c2.get() |> ignore
      c2_runs.val += 1
    })
    |> ignore
    assert_eq(c2_runs.val, 1)
    fw_batch(fn() raise {
      a.set(5)
      c1.get() |> ignore
      assert_eq(c2_runs.val, 1)
    })
    assert_eq(c2_runs.val, 2)
  })
}

///|
test "batch #130 effect inner writes are implicitly batched" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_signal(0)
    let log : Array[String] = []
    fw_effect(fn() {
      let v = a.get()
      b.set(v + 1)
      c.set(v + 2)
    })
    |> ignore
    fw_effect(fn() { log.push(b.get().to_string() + "," + c.get().to_string()) }) |> ignore
    log.clear()
    a.set(10)
    assert_eq(log[log.length() - 1], "11,12")
  })
}

///|
test "batch #131 derived-of-derived: source reverts in batch" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(10)
    let c1 = fw_computed(fn() { a.get() * 2 })
    let c2 = fw_computed(fn() { c1.get() + b.get() })
    let runs = Ref(0)
    fw_effect(fn() {
      c2.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(5)
      a.set(0)
      b.set(20)
    })
    assert_eq(c2.get(), 20)
    assert_eq(runs.val, 2)
  })
}

///|
test "batch #132 batch: computed not recomputed if dep reverts" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get() * 2
    })
    fw_effect(fn() { c.get() |> ignore }) |> ignore
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
test "batch #74 multiple signals grouped in single update" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      b.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    fw_batch(fn() {
      a.set(1)
      b.set(1)
    })
    assert_eq(runs.val, 2)
    assert_eq(a.get(), 1)
    assert_eq(b.get(), 1)
  })
}
