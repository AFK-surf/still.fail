// The conformance suite (conformance_graph_wbtest.mbt): Inner Write (innerWrite.ts): what an effect or a computed
// writes as it runs (still.fail's topic_read sets a topic's version signal inside a computed's getter). Here a
// computed may write, so the cases' "side effects forbidden" way out is never taken; #114 and #113 bail out by throwing
// after 20 and 100 runs (here: they stop there), and #185 is not here (nothing throws).

///|
test "inner write #50 effect writes back to signal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    fw_effect(fn() { b.set(a.get() * 2) }) |> ignore
    assert_eq(b.get(), 0)
    a.set(5)
    assert_eq(b.get(), 10)
  })
}

///|
test "inner write #51 effect cleanup modifying dependency does not retrigger" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    effect_cleanup(fn() {
      runs.val += 1
      a.get() |> ignore
      fn() { a.set(999) }
    })
    |> ignore
    assert_eq(runs.val, 1)
    a.set(1)
    assert_true(runs.val >= 2)
    assert_true(runs.val <= 3)
  })
}

///|
test "inner write #52 computed writing to signal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let side_channel = fw_signal(0)
    let c = fw_computed(fn() {
      let v = a.get()
      side_channel.set(v * 10)
      v
    })
    c.get() |> ignore
    assert_eq(side_channel.get(), 0)
  })
}

///|
test "inner write #53 inner write: only final value observed" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let values : Array[Int] = []
    fw_effect(fn() { values.push(a.get()) }) |> ignore
    assert_eq(values, [0])
    a.set(1)
    a.set(2)
    a.set(3)
    assert_eq(values[values.length() - 1], 3)
  })
}

///|
test "inner write #54 inner mutations propagate until changes settle" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    fw_effect(fn() {
      if a.get() > 0 && b.get() == 0 {
        b.set(a.get())
      }
    })
    |> ignore
    a.set(5)
    assert_eq(b.get(), 5)
  })
}

///|
test "inner write #56 effect re-scheduled after reading from derived then writing" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let values : Array[Int] = []
    fw_effect(fn() { values.push(b.get()) }) |> ignore
    assert_eq(values, [0])
    a.set(1)
    assert_eq(values[values.length() - 1], 1)
  })
}

///|
test "inner write #112 computed side-effect doesn't affect sibling computeds" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side_channel = fw_signal(0)
    let writer = fw_computed(fn() {
      let v = src.get()
      side_channel.set(v * 10)
      v
    })
    writer.get() |> ignore
    let reader = fw_computed(fn() { side_channel.get() })
    assert_eq(reader.get(), 0)
    src.set(1)
    writer.get() |> ignore
    assert_eq(reader.get(), 10)
  })
}

///|
test "inner write #114 inner write final value unchanged: no downstream notification" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let effect_runs = Ref(0)
    let downstream_runs = Ref(0)
    fw_effect(fn() {
      effect_runs.val += 1
      if effect_runs.val > 20 {
        return
      }
      let v = a.get()
      if v == 1 {
        a.set(0)
      }
    })
    |> ignore
    let c = fw_computed(fn() { a.get() })
    fw_effect(fn() {
      c.get() |> ignore
      downstream_runs.val += 1
    })
    |> ignore
    let downstream_before = downstream_runs.val
    a.set(1)
    assert_eq(a.get(), 0)
    assert_true(downstream_runs.val <= downstream_before + 1)
  })
}

///|
test "inner write #133 listener writes back: second listener skipped if no net change" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let values1 : Array[Int] = []
    let values2 : Array[Int] = []
    fw_effect(fn() {
      let v = a.get()
      values1.push(v)
      if v == 1 {
        a.set(0)
      }
    })
    |> ignore
    fw_effect(fn() { values2.push(a.get()) }) |> ignore
    a.set(1)
    assert_eq(a.get(), 0)
    assert_eq(values2[values2.length() - 1], 0)
  })
}

///|
test "inner write #134 listener writes back: second listener gets final value" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let final_values : Array[Int] = []
    fw_effect(fn() {
      let v = a.get()
      if v == 1 {
        a.set(10)
      }
    })
    |> ignore
    fw_effect(fn() { final_values.push(a.get()) }) |> ignore
    a.set(1)
    assert_eq(a.get(), 10)
    assert_eq(final_values[final_values.length() - 1], 10)
  })
}

///|
test "inner write #135 chained computed inner write: downstream only sees settled" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let target = fw_signal(0)
    let c1 = fw_computed(fn() {
      let v = src.get()
      target.set(v * 10)
      v
    })
    c1.get() |> ignore
    let c2 = fw_computed(fn() { target.get() })
    assert_eq(c2.get(), 0)
    src.set(1)
    c1.get() |> ignore
    assert_eq(target.get(), 10)
    assert_eq(c2.get(), 10)
  })
}

///|
test "inner write #136 computed inner write unchanged: no downstream notification" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side = fw_signal(0)
    let c = fw_computed(fn() {
      let v = src.get()
      side.set(0)
      v
    })
    c.get() |> ignore
    let downstream_runs = Ref(0)
    fw_effect(fn() {
      side.get() |> ignore
      downstream_runs.val += 1
    })
    |> ignore
    downstream_runs.val = 0
    src.set(1)
    c.get() |> ignore
    assert_true(downstream_runs.val <= 1)
  })
}

///|
test "inner write #137 computed inner write changed: downstream notified" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side = fw_signal(0)
    let c = fw_computed(fn() {
      let v = src.get()
      side.set(v * 100)
      v
    })
    c.get() |> ignore
    src.set(1)
    c.get() |> ignore
    assert_eq(side.get(), 100)
  })
}

///|
test "inner write #138 independent computeds sharing source, one inner-writes" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let shared = fw_signal(0)
    let writer = fw_computed(fn() {
      let v = src.get()
      shared.set(v * 10)
      v
    })
    writer.get() |> ignore
    let reader = fw_computed(fn() { shared.get() + 1 })
    assert_eq(shared.get(), 0)
    assert_eq(reader.get(), 1)
    src.set(2)
    writer.get() |> ignore
    assert_eq(shared.get(), 20)
    assert_eq(reader.get(), 21)
  })
}

///|
test "inner write #172 computed writing to own dep: never caches" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let compute_calls = Ref(0)
    let c = fw_computed(fn() {
      compute_calls.val += 1
      a.set(a.get() + 1)
      a.get()
    })
    c.get() |> ignore
    let calls_after_first = compute_calls.val
    c.get() |> ignore
    assert_true(compute_calls.val > calls_after_first)
  })
}

///|
test "inner write #180 inner write through computed chain resets signal" {
  fw_run(fn() raise {
    let s = fw_signal(false)
    let c = fw_computed(fn() { s.get() })
    let runs = Ref(0)
    fw_effect(fn() {
      runs.val += 1
      if c.get() {
        s.set(false)
      }
    })
    |> ignore
    assert_eq(runs.val, 1)
    s.set(true)
    assert_eq(s.get(), false)
    assert_true(runs.val >= 2)
    let effect_re_runs = runs.val >= 3
    let runs_after_first = runs.val
    s.set(true)
    if effect_re_runs {
      assert_eq(s.get(), false)
      assert_true(runs.val >= runs_after_first + 2)
    } else {
      assert_eq(s.get(), true)
      assert_eq(runs.val, runs_after_first)
    }
  })
}

///|
test "inner write #179 computed self-increment: intra-run read-after-write values correct" {
  fw_run(fn() raise {
    let s = fw_signal(1)
    let c = fw_computed(fn() {
      s.set(s.get() + 1)
      s.get()
    })
    assert_eq(c.get(), 2)
    assert_eq(s.get(), 2)
    assert_eq(c.get(), 3)
    assert_eq(s.get(), 3)
  })
}

///|
test "inner write #113 inner write convergence: converges or cycle-detects" {
  fw_run(fn() raise {
    let counter = fw_signal(0)
    let target = 5
    let iterations = Ref(0)
    fw_effect(fn() {
      iterations.val += 1
      if iterations.val > 100 {
        return
      }
      let v = counter.get()
      if v < target {
        counter.set(v + 1)
      }
    })
    |> ignore
    let value = counter.get()
    let converged = value == target
    let cycle_det = iterations.val <= 100 && value < target
    assert_true(converged || cycle_det)
    if converged {
      assert_eq(value, target)
      assert_true(iterations.val <= target + 1)
    }
  })
}

///|
test "inner write #57 computed side effect triggers downstream" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side_effect = fw_signal(0)
    let c = fw_computed(fn() {
      let v = src.get()
      side_effect.set(v * 10)
      v
    })
    let values : Array[Int] = []
    fw_effect(fn() { values.push(side_effect.get()) }) |> ignore
    c.get() |> ignore
    assert_eq(side_effect.get(), 0)
    src.set(1)
    c.get() |> ignore
    assert_eq(side_effect.get(), 10)
  })
}

///|
test "inner write #181 computed writes multiple signals: downstream sees consistent pair" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_signal(0)
    let writer = fw_computed(fn() {
      let v = src.get()
      b.set(v + 1)
      c.set(v + 2)
      v
    })
    writer.get() |> ignore
    let pair = fw_computed(fn() { b.get().to_string() + "," + c.get().to_string() })
    assert_eq(pair.get(), "1,2")
    src.set(10)
    writer.get() |> ignore
    assert_eq(pair.get(), "11,12")
  })
}

///|
test "inner write #182 computed side effect + batch: writes visible after flush" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side = fw_signal(0)
    let c = fw_computed(fn() {
      let v = src.get()
      side.set(v * 10)
      v
    })
    c.get() |> ignore
    let effect_runs = Ref(0)
    fw_effect(fn() {
      side.get() |> ignore
      effect_runs.val += 1
    })
    |> ignore
    effect_runs.val = 0
    fw_batch(fn() raise {
      src.set(5)
      assert_eq(c.get(), 5)
      assert_eq(side.get(), 50)
    })
    assert_true(effect_runs.val >= 1)
    assert_eq(side.get(), 50)
  })
}

///|
test "inner write #183 branch switch stops computed side effect" {
  fw_run(fn() raise {
    let flag = fw_signal(true)
    let src = fw_signal(0)
    let side = fw_signal(-1)
    let writer = fw_computed(fn() {
      let v = src.get()
      side.set(v)
      v
    })
    writer.get() |> ignore
    let branch = fw_computed(fn() { if flag.get() { writer.get() } else { 999 } })
    assert_eq(branch.get(), 0)
    assert_eq(side.get(), 0)
    src.set(1)
    branch.get() |> ignore
    assert_eq(side.get(), 1)
    flag.set(false)
    assert_eq(branch.get(), 999)
    src.set(2)
    branch.get() |> ignore
    assert_eq(side.get(), 1)
  })
}

///|
test "inner write #184 nested computeds: outer reads inner, both have side effects" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let inner_side = fw_signal(0)
    let outer_side = fw_signal(0)
    let inner = fw_computed(fn() {
      let v = src.get()
      inner_side.set(v * 10)
      v + 1
    })
    let outer = fw_computed(fn() {
      let iv = inner.get()
      outer_side.set(iv * 100)
      iv
    })
    outer.get() |> ignore
    // src=0 → 0*10; inner=1 → 1*100
    assert_eq(inner_side.get(), 0)
    assert_eq(outer_side.get(), 100)
    src.set(2)
    outer.get() |> ignore
    // 2*10; inner=3 → 3*100
    assert_eq(inner_side.get(), 20)
    assert_eq(outer_side.get(), 300)
  })
}

///|
test "inner write #186 effect observes computed side-channel write during propagation" {
  fw_run(fn() raise {
    let src = fw_signal(0)
    let side = fw_signal(0)
    let c = fw_computed(fn() {
      let v = src.get()
      side.set(v)
      v
    })
    c.get() |> ignore
    let observed : Array[Int] = []
    fw_effect(fn() { observed.push(c.get() + side.get()) }) |> ignore
    // c=0 + side=0
    assert_eq(observed[observed.length() - 1], 0)
    src.set(5)
    // c=5 + side=5
    assert_eq(observed[observed.length() - 1], 10)
  })
}

///|
test "inner write #213 inner write during initial effect execution doesn't block future propagation" {
  fw_run(fn() raise {
    let s = fw_signal(1)
    let c = fw_computed(fn() { s.get() })
    fw_effect(fn() {
      if c.get() > 0 {
        s.set(0)
      }
    })
    |> ignore
    assert_eq(s.get(), 0)
    s.set(2)
    assert_eq(s.get(), 0)
    s.set(3)
    assert_eq(s.get(), 0)
  })
}

///|
test "inner write #212 inner write through computed doesn't block future propagation" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let c = fw_computed(fn() { s.get() })
    fw_effect(fn() {
      if c.get() > 0 {
        s.set(0)
      }
    })
    |> ignore
    s.set(1)
    assert_eq(s.get(), 0)
    s.set(2)
    assert_eq(s.get(), 0)
    s.set(3)
    assert_eq(s.get(), 0)
  })
}

///|
test "inner write #224 effect sees fresh computed after sibling's mid-flush inner write" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_computed(fn() { a.get() + b.get() })
    let observed : Array[Int] = []
    fw_effect(fn() {
      if a.get() == 1 {
        b.set(10)
      }
    })
    |> ignore
    fw_effect(fn() { observed.push(c.get()) }) |> ignore
    assert_eq(observed, [0])
    a.set(1)
    assert_eq(observed[observed.length() - 1], 11)
  })
}

///|
test "inner write #225 mid-flush fan-in: e3 sees both sibling effects' inner writes" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b1 = fw_signal(0)
    let b2 = fw_signal(0)
    let c = fw_computed(fn() { b1.get() + b2.get() })
    let observed : Array[Int] = []
    fw_effect(fn() {
      if a.get() == 1 {
        b1.set(10)
      }
    })
    |> ignore
    fw_effect(fn() {
      if a.get() == 1 {
        b2.set(20)
      }
    })
    |> ignore
    fw_effect(fn() { observed.push(c.get()) }) |> ignore
    assert_eq(observed, [0])
    a.set(1)
    assert_eq(observed[observed.length() - 1], 30)
  })
}
