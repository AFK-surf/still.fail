// The conformance suite alien-signals runs (reactive-framework-test-suite 0.0.2, its tests/conformance.spec.ts:
// https://www.npmjs.com/package/reactive-framework-test-suite), ported case by case: its framework's signal, computed,
// effect, run, batch and untracked are fw_* below, each case run as there (fw_run: in a scope, disposed after). A
// value is the same as another as JS's `===` has them for the numbers and strings the cases use (same: ==).
// This file: Graph Propagation (graphPropagation.ts).

///|
fn[T : Eq] fw_signal(v : T) -> Signal[T] {
  signal(v, same=fn(a, b) { a == b })
}

///|
fn[T : Eq] fw_computed(f : () -> T) -> Computed[T] {
  computed(fn(_) { f() }, same=fn(a, b) { a == b })
}

///|
fn fw_effect(f : () -> Unit) -> () -> Unit {
  effect(f)
}

///|
/// A case run in a scope, disposed after; what it asserted raised once it is.
fn fw_run(f : () -> Unit raise) -> Unit raise {
  let failed : Ref[Error?] = Ref(None)
  effect_scope(fn() {
    try {
      f()
    } catch {
      e => failed.val = Some(e)
    }
  })()
  match failed.val {
    Some(e) => raise e
    None => ()
  }
}

///|
/// A batch (startBatch, endBatch in a finally): what it asserted raised once it is over.
fn fw_batch(f : () -> Unit raise) -> Unit raise {
  start_batch()
  let failed : Error? = try {
    f()
    None
  } catch {
    e => Some(e)
  }
  end_batch()
  match failed {
    Some(e) => raise e
    None => ()
  }
}

///|
fn[T] fw_untracked(f : () -> T) -> T {
  let prev = set_active_sub(None)
  let v = f()
  set_active_sub(prev) |> ignore
  v
}

///|
test "graph #1 diamond" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { a.get() })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      b.get() + " " + c.get()
    })
    assert_eq(d.get(), "a a")
    assert_eq(d_calls.val, 1)
    a.set("aa")
    assert_eq(d.get(), "aa aa")
    assert_eq(d_calls.val, 2)
  })
}

///|
test "graph #2 diamond + tail" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { a.get() })
    let d = fw_computed(fn() { b.get() + " " + c.get() })
    let e_calls = Ref(0)
    let e = fw_computed(fn() {
      e_calls.val += 1
      d.get()
    })
    assert_eq(e.get(), "a a")
    assert_eq(e_calls.val, 1)
    a.set("aa")
    assert_eq(e.get(), "aa aa")
    assert_eq(e_calls.val, 2)
  })
}

///|
test "graph #3 jagged diamond + tails" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { a.get() })
    let d = fw_computed(fn() { c.get() })
    let e_calls = Ref(0)
    let e = fw_computed(fn() {
      e_calls.val += 1
      b.get() + " " + d.get()
    })
    let f_calls = Ref(0)
    let f = fw_computed(fn() {
      f_calls.val += 1
      e.get()
    })
    let g_calls = Ref(0)
    let g = fw_computed(fn() {
      g_calls.val += 1
      e.get()
    })
    assert_eq(f.get(), "a a")
    assert_eq(g.get(), "a a")
    e_calls.val = 0
    f_calls.val = 0
    g_calls.val = 0
    a.set("b")
    assert_eq(e.get(), "b b")
    assert_eq(e_calls.val, 1)
    assert_eq(f.get(), "b b")
    assert_eq(f_calls.val, 1)
    assert_eq(g.get(), "b b")
    assert_eq(g_calls.val, 1)
  })
}

///|
test "graph #5 drop A→B→A updates" {
  fw_run(fn() raise {
    let a = fw_signal(2)
    let b = fw_computed(fn() { a.get() - 1 })
    let c = fw_computed(fn() { a.get() + b.get() })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      "d: " + c.get().to_string()
    })
    assert_eq(d.get(), "d: 3")
    assert_eq(d_calls.val, 1)
    a.set(4)
    assert_eq(d.get(), "d: 7")
    assert_eq(d_calls.val, 2)
  })
}

///|
test "graph #6 one unchanged dep does not block update from changed dep" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() {
      a.get() |> ignore
      "c"
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      b.get() + " " + c.get()
    })
    assert_eq(d.get(), "a c")
    d_calls.val = 0
    a.set("aa")
    assert_eq(d.get(), "aa c")
    assert_eq(d_calls.val, 1)
  })
}

///|
test "graph #7 unchanged computed values stop propagation to downstream" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() {
      a.get() |> ignore
      "b"
    })
    let c = fw_computed(fn() {
      a.get() |> ignore
      "c"
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      b.get() + " " + c.get()
    })
    assert_eq(d.get(), "b c")
    d_calls.val = 0
    a.set("aa")
    assert_eq(d.get(), "b c")
    assert_eq(d_calls.val, 0)
  })
}

///|
test "graph #8 topological order" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let order : Array[String] = []
    let b = fw_computed(fn() {
      let v = a.get()
      order.push("b")
      v
    })
    let c = fw_computed(fn() {
      let v = a.get()
      order.push("c")
      v
    })
    let d = fw_computed(fn() {
      let v = b.get() + c.get()
      order.push("d")
      v
    })
    assert_eq(d.get(), 0)
    order.clear()
    a.set(1)
    assert_eq(d.get(), 2)
    let at = fn(x : String) { order.search(x).unwrap_or(-1) }
    assert_true(at("d") > at("b"))
    assert_true(at("d") > at("c"))
    assert_eq(order.filter(fn(x) { x == "d" }).length(), 1)
  })
}

///|
test "graph #9 linear convergence" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get() + b.get()
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      a.get() + c.get()
    })
    assert_eq(d.get(), 0)
    c_calls.val = 0
    d_calls.val = 0
    a.set(1)
    assert_eq(d.get(), 3)
    assert_eq(c_calls.val, 1)
    assert_eq(d_calls.val, 1)
  })
}

///|
test "graph #10 exponential convergence" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      b.get() + a.get()
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      c.get() + b.get()
    })
    let e_calls = Ref(0)
    let e = fw_computed(fn() {
      e_calls.val += 1
      d.get() + c.get()
    })
    assert_eq(e.get(), 0)
    c_calls.val = 0
    d_calls.val = 0
    e_calls.val = 0
    a.set(1)
    assert_eq(e.get(), 5)
    assert_eq(c_calls.val, 1)
    assert_eq(d_calls.val, 1)
    assert_eq(e_calls.val, 1)
  })
}

///|
test "graph #116 other listeners still notified after one disposes" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let c = fw_computed(fn() { a.get() * 2 })
    let runs1 = Ref(0)
    let runs2 = Ref(0)
    let dispose1 = fw_effect(fn() {
      c.get() |> ignore
      runs1.val += 1
    })
    fw_effect(fn() {
      c.get() |> ignore
      runs2.val += 1
    })
    |> ignore
    assert_eq(runs1.val, 1)
    assert_eq(runs2.val, 1)
    dispose1()
    a.set(1)
    assert_eq(runs1.val, 1)
    assert_eq(runs2.val, 2)
    a.set(2)
    assert_eq(runs1.val, 1)
    assert_eq(runs2.val, 3)
  })
}

///|
test "graph #157 three-way diamond: sub updates when two of three deps unmark" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() {
      a.get() |> ignore
      "c"
    })
    let d = fw_computed(fn() {
      a.get() |> ignore
      "d"
    })
    let e_calls = Ref(0)
    let e = fw_computed(fn() {
      e_calls.val += 1
      b.get() + " " + c.get() + " " + d.get()
    })
    assert_eq(e.get(), "a c d")
    e_calls.val = 0
    a.set("aa")
    assert_eq(e.get(), "aa c d")
    assert_eq(e_calls.val, 1)
  })
}

///|
test "graph #187 effect disposal deactivates upstream computed" {
  fw_run(fn() raise {
    let a = fw_signal("a")
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
    let d = fw_computed(fn() { a.get() })
    let result = Ref("")
    let dispose = fw_effect(fn() { result.val = c.get() })
    assert_eq(result.val, "a")
    assert_eq(d.get(), "a")
    b_calls.val = 0
    c_calls.val = 0
    dispose()
    a.set("aa")
    assert_eq(b_calls.val, 0)
    assert_eq(c_calls.val, 0)
    assert_eq(d.get(), "aa")
  })
}

///|
test "graph #188 batch + dynamic deps: unnecessary recompute avoided" {
  fw_run(fn() raise {
    let c_calls = Ref(0)
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_computed(fn() {
      b.get() |> ignore
      c_calls.val += 1
    })
    let d = fw_computed(fn() { if a.get() == 0 { c.get() } })
    d.get()
    assert_eq(c_calls.val, 1)
    fw_batch(fn() {
      b.set(1)
      a.set(1)
    })
    d.get()
    assert_eq(c_calls.val, 1)
  })
}

///|
test "graph #189 multi-signal change: topological ordering preserved" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_signal(1)
    let c = fw_signal(1)
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      c.get()
    })
    let e = fw_computed(fn() {
      if a.get() > 0 {
        b.get() |> ignore
        d.get() |> ignore
      } else {
        b.get() |> ignore
      }
    })
    e.get()
    d_calls.val = 0
    a.set(2)
    b.set(2)
    c.set(2)
    e.get()
    assert_eq(d_calls.val, 1)
    d_calls.val = 0
    a.set(-1)
    b.set(-1)
    c.set(-1)
    e.get()
    assert_eq(d_calls.val, 0)
  })
}

///|
test "graph #190 computed notifies newly-subscribed effect after prior read" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { b.get() })
    c.get() |> ignore
    let runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    a.set(1)
    assert_eq(runs.val, 2)
  })
}

///|
test "graph #191 effect sees latest computed value when subscribing after source change" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let c = fw_computed(fn() { s.get() })
    c.get() |> ignore
    s.set(1)
    let seen : Ref[Int?] = Ref(None)
    fw_effect(fn() { seen.val = Some(c.get()) }) |> ignore
    assert_eq(seen.val, Some(1))
  })
}

///|
test "graph #192 effect not re-run when computed dep value unchanged" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let c = fw_computed(fn() {
      s.get() |> ignore
      0
    })
    let runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    s.set(1)
    assert_eq(runs.val, 1)
  })
}

///|
test "graph #204 multi-source fan-in" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_signal(10)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get() + b.get()
    })
    let runs = Ref(0)
    fw_effect(fn() {
      c.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(c.get(), 11)
    assert_eq(runs.val, 1)
    c_calls.val = 0
    runs.val = 0
    fw_batch(fn() {
      a.set(2)
      b.set(20)
    })
    assert_eq(c.get(), 22)
    assert_eq(c_calls.val, 1)
    assert_eq(runs.val, 1)
  })
}

///|
test "graph #205 multi-source cross-diamond" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_signal(10)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      a.get() + b.get()
    })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      a.get() * b.get()
    })
    let e_calls = Ref(0)
    let e = fw_computed(fn() {
      e_calls.val += 1
      c.get() + d.get()
    })
    assert_eq(e.get(), 21)
    c_calls.val = 0
    d_calls.val = 0
    e_calls.val = 0
    a.set(2)
    b.set(20)
    assert_eq(e.get(), 62)
    assert_eq(c_calls.val, 1)
    assert_eq(d_calls.val, 1)
    assert_eq(e_calls.val, 1)
  })
}

///|
test "graph #206 stacked diamonds" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { a.get() })
    let d_calls = Ref(0)
    let d = fw_computed(fn() {
      d_calls.val += 1
      b.get() + c.get()
    })
    let e = fw_computed(fn() { d.get() })
    let f = fw_computed(fn() { d.get() })
    let g_calls = Ref(0)
    let g = fw_computed(fn() {
      g_calls.val += 1
      e.get() + f.get()
    })
    assert_eq(g.get(), 4)
    d_calls.val = 0
    g_calls.val = 0
    a.set(2)
    assert_eq(g.get(), 8)
    assert_eq(d_calls.val, 1)
    assert_eq(g_calls.val, 1)
  })
}

///|
test "graph #207 wide fan-out: all effects fire once" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let n = 6
    let runs = Array::make(n, 0)
    for i in 0..<n {
      let c = fw_computed(fn() { a.get() + i })
      fw_effect(fn() {
        c.get() |> ignore
        runs[i] = runs[i] + 1
      })
      |> ignore
    }
    for i in 0..<n {
      assert_eq(runs[i], 1)
    }
    a.set(1)
    for i in 0..<n {
      assert_eq(runs[i], 2)
    }
    a.set(2)
    for i in 0..<n {
      assert_eq(runs[i], 3)
    }
  })
}

///|
test "graph #208 deep asymmetric join (depth 3 vs 1)" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { b.get() })
    let d = fw_computed(fn() { c.get() })
    let e = fw_computed(fn() { a.get() })
    let f_calls = Ref(0)
    let f = fw_computed(fn() {
      f_calls.val += 1
      d.get() + e.get()
    })
    assert_eq(f.get(), 2)
    f_calls.val = 0
    a.set(2)
    assert_eq(f.get(), 4)
    assert_eq(f_calls.val, 1)
  })
}
