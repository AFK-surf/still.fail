// The conformance suite (conformance_graph_wbtest.mbt): Dynamic Dependencies (dynamicDeps.ts).

///|
test "dynamic #12 active dep triggers, inactive dep does not" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_signal("b")
    let cond = fw_signal(true)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      if cond.get() {
        a.get()
      } else {
        b.get()
      }
    })
    assert_eq(c.get(), "a")
    assert_eq(c_calls.val, 1)
    // b is inactive, changing it should not trigger c
    b.set("bb")
    assert_eq(c.get(), "a")
    assert_eq(c_calls.val, 1)
    // a is active, changing it should trigger c
    a.set("aa")
    assert_eq(c.get(), "aa")
    assert_eq(c_calls.val, 2)
  })
}

///|
test "dynamic #13 switching branches deactivates old deps" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let b = fw_signal("b")
    let cond = fw_signal(true)
    let c_calls = Ref(0)
    let c = fw_computed(fn() {
      c_calls.val += 1
      if cond.get() {
        a.get()
      } else {
        b.get()
      }
    })
    assert_eq(c.get(), "a")
    c_calls.val = 0
    // Switch to b branch
    cond.set(false)
    assert_eq(c.get(), "b")
    c_calls.val = 0
    // a is now inactive
    a.set("aa")
    assert_eq(c.get(), "b")
    assert_eq(c_calls.val, 0)
    // b is now active
    b.set("bb")
    assert_eq(c.get(), "bb")
    assert_eq(c_calls.val, 1)
  })
}

///|
test "dynamic #14 new deps updated before dependee" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_signal(10)
    let cond = fw_signal(false)
    let c = fw_computed(fn() { a.get() })
    let d = fw_computed(fn() { if cond.get() { c.get() } else { b.get() } })
    assert_eq(d.get(), 10)
    // Switch to c branch, and change a at the same time
    cond.set(true)
    a.set(2)
    // d should see the updated a through c
    assert_eq(d.get(), 2)
  })
}

///|
test "dynamic #16 lazy branch" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() { if a.get() > 0 { a.get() } else { b.get() } })
    assert_eq(c.get(), 0)
    a.set(1)
    assert_eq(c.get(), 1)
    a.set(0)
    assert_eq(c.get(), 0)
  })
}

///|
test "dynamic #165 computed dep cleanup doesn't delete sibling subscription" {
  fw_run(fn() raise {
    let toggle = fw_signal(true)
    let state = fw_signal(1)
    let p = fw_computed(fn() { if toggle.get() { state.get() } else { 111 } })
    let pp = fw_computed(fn() { state.get() })
    fw_effect(fn() { p.get() |> ignore }) |> ignore
    toggle.set(false)
    assert_eq(p.get(), 111)
    state.set(2)
    assert_eq(pp.get(), 2)
  })
}

///|
test "dynamic #166 after dep removed via branch switch, re-subscribing works" {
  fw_run(fn() raise {
    let flag = fw_signal(true)
    let src = fw_signal(1)
    let c = fw_computed(fn() { if flag.get() { src.get() } else { 0 } })
    let seen = Ref(-1)
    fw_effect(fn() { seen.val = c.get() }) |> ignore
    assert_eq(seen.val, 1)
    flag.set(false)
    assert_eq(seen.val, 0)
    src.set(2)
    flag.set(true)
    assert_eq(seen.val, 2)
  })
}

///|
test "dynamic #193 sequential dirty check: branch switch skips unreachable computed" {
  // a → b, b → c, d reads c only when b is truthy. When a becomes null, b becomes null, d skips c. c should NOT
  // re-evaluate even though its dep b changed.
  fw_run(fn() raise {
    let c_calls = Ref(0)
    let a : Signal[Int?] = fw_signal(Some(1))
    let b = fw_computed(fn() { a.get() })
    let c = fw_computed(fn() {
      c_calls.val += 1
      b.get()
    })
    let d = fw_computed(fn() {
      if b.get() is Some(_) {
        return c.get().unwrap_or(0)
      }
      0
    })
    d.get() |> ignore
    assert_eq(c_calls.val, 1)
    a.set(None)
    d.get() |> ignore
    // c should not have been re-evaluated — d skipped it
    assert_eq(c_calls.val, 1)
  })
}

///|
test "dynamic #194 chained computed dirty reallocation via effect" {
  // items → isLoaded (boolean) → msg (string); effect observes msg. Repeated writes to items.
  fw_run(fn() raise {
    let seen = Ref("")
    let items : Signal[Array[Int]?] = fw_signal(None)
    let is_loaded = fw_computed(fn() { items.get() is Some(_) })
    let msg = fw_computed(fn() { if is_loaded.get() { "loaded" } else { "not loaded" } })
    fw_effect(fn() { seen.val = msg.get() }) |> ignore
    assert_eq(seen.val, "not loaded")
    items.set(Some([1, 2, 3]))
    assert_eq(seen.val, "loaded")
    items.set(Some([4, 5]))
    assert_eq(seen.val, "loaded")
    items.set(None)
    assert_eq(seen.val, "not loaded")
  })
}

///|
test "dynamic #195 chained computed dirty reallocation via manual read" {
  // Same chain as #194 but driven by manual reads with intermediate computed reads interleaved.
  fw_run(fn() raise {
    let items : Signal[Array[Int]?] = fw_signal(None)
    let is_loaded = fw_computed(fn() { items.get() is Some(_) })
    let msg = fw_computed(fn() { if is_loaded.get() { "loaded" } else { "not loaded" } })
    assert_eq(msg.get(), "not loaded")
    items.set(Some([1, 2, 3]))
    // Read intermediate computed before final
    is_loaded.get() |> ignore
    assert_eq(msg.get(), "loaded")
    items.set(None)
    assert_eq(msg.get(), "not loaded")
  })
}

///|
test "dynamic #196 maybe-dirty diamond: first dep unmarked, second still triggers" {
  // c1 = src1, c2 = (src1 % 2) + src2, c3 = f(c1, c2). When src1: 0→2, c1 changes but c2 stays 0. c3 must still
  // re-evaluate. When src2: 0→1, c2 changes. c3 must re-evaluate again.
  fw_run(fn() raise {
    let c3_calls = Ref(0)
    let src1 = fw_signal(0)
    let src2 = fw_signal(0)
    let c1 = fw_computed(fn() { src1.get() })
    let c2 = fw_computed(fn() { src1.get() % 2 + src2.get() })
    let c3 = fw_computed(fn() {
      c3_calls.val += 1
      c1.get() + c2.get()
    })
    c3.get() |> ignore
    assert_eq(c3_calls.val, 1)
    src1.set(2)
    c3.get() |> ignore
    assert_eq(c3_calls.val, 2)
    src2.set(1)
    c3.get() |> ignore
    assert_eq(c3_calls.val, 3)
  })
}

///|
test "dynamic #197 chained value-equality stops propagation across multiple writes" {
  // src → c1 (src % 2) → c2 (c1 + 1) → effect. Multiple writes to src that don't change c1's output. c2 and effect
  // should not re-run.
  fw_run(fn() raise {
    let c1_calls = Ref(0)
    let c2_calls = Ref(0)
    let effect_runs = Ref(0)
    let src = fw_signal(0)
    let c1 = fw_computed(fn() {
      c1_calls.val += 1
      src.get() % 2
    })
    let c2 = fw_computed(fn() {
      c2_calls.val += 1
      c1.get() + 1
    })
    fw_effect(fn() {
      c2.get() |> ignore
      effect_runs.val += 1
    })
    |> ignore
    assert_eq(effect_runs.val, 1)
    c1_calls.val = 0
    c2_calls.val = 0
    effect_runs.val = 0
    // All even numbers: c1 stays 0
    src.set(2)
    src.set(4)
    src.set(6)
    assert_true(c1_calls.val >= 1)
    assert_eq(c2_calls.val, 0)
    assert_eq(effect_runs.val, 0)
  })
}

///|
test "dynamic #198 effect discovers new branch deps" {
  // Effect has dynamic branch: cond ? a : "other". Initially cond=false, a is not tracked. After cond→true, changing a
  // should trigger effect.
  fw_run(fn() raise {
    let cond = fw_signal(false)
    let a = fw_signal("value")
    let runs = Ref(0)
    let seen = Ref("")
    fw_effect(fn() {
      runs.val += 1
      seen.val = if cond.get() { a.get() } else { "other" }
    })
    |> ignore
    assert_eq(seen.val, "other")
    assert_eq(runs.val, 1)
    // a is inactive — should not trigger
    a.set("Hi")
    assert_eq(seen.val, "other")
    assert_eq(runs.val, 1)
    // Switch branch → a becomes active
    cond.set(true)
    assert_eq(seen.val, "Hi")
    assert_eq(runs.val, 2)
    // a is now active
    a.set("World")
    assert_eq(seen.val, "World")
    assert_eq(runs.val, 3)
  })
}

///|
test "dynamic #199 effect ignores inactive branch dep" {
  // Effect has dynamic branch: cond ? a : "other". Initially cond=true, a is tracked. After cond→false, changing a
  // should NOT trigger effect.
  fw_run(fn() raise {
    let cond = fw_signal(true)
    let a = fw_signal("value")
    let runs = Ref(0)
    let seen = Ref("")
    fw_effect(fn() {
      runs.val += 1
      seen.val = if cond.get() { a.get() } else { "other" }
    })
    |> ignore
    assert_eq(seen.val, "value")
    assert_eq(runs.val, 1)
    // Switch to inactive branch
    cond.set(false)
    assert_eq(seen.val, "other")
    assert_eq(runs.val, 2)
    // a is now inactive — should not trigger
    a.set("changed")
    assert_eq(seen.val, "other")
    assert_eq(runs.val, 2)
  })
}

///|
test "dynamic #200 independent dep tracking across effects with dynamic deps" {
  // Two effects with overlapping deps that change branches based on a shared condition signal. fx1: c<2 → reads a;
  // c>1 → reads b. fx2: c>1 → reads a; c<3 → reads b; also reads fx1 output.
  fw_run(fn() raise {
    let a = fw_signal(1)
    let b = fw_signal(2)
    let c = fw_signal(0)
    let fx1_out = fw_signal(0)
    let fx2_out = fw_signal(0)
    let fx1_runs = Ref(0)
    fw_effect(fn() {
      fx1_runs.val += 1
      let mut result = 0
      if c.get() < 2 {
        result += a.get()
      }
      if c.get() > 1 {
        result += b.get()
      }
      fx1_out.set(result)
    })
    |> ignore
    let fx2_runs = Ref(0)
    fw_effect(fn() {
      fx2_runs.val += 1
      let mut result = 0
      if c.get() > 1 {
        result += a.get()
      }
      if c.get() < 3 {
        result += b.get()
      }
      result += fx1_out.get()
      fx2_out.set(result)
    })
    |> ignore
    // c=0: fx1 reads a(1)→1, fx2 reads b(2)+fx1Out(1)→3
    assert_eq(fx1_out.get(), 1)
    assert_eq(fx2_out.get(), 3)
    fx1_runs.val = 0
    fx2_runs.val = 0
    // b changes: fx1 doesn't read b (c<2 only), fx2 reads b
    b.set(3)
    assert_eq(fx1_out.get(), 1)
    assert_eq(fx2_out.get(), 4)
    assert_eq(fx1_runs.val, 0)
    assert_eq(fx2_runs.val, 1)
    fx1_runs.val = 0
    fx2_runs.val = 0
    // c=2: fx1 reads b(3)→3, fx2 reads a(1)+b(3)+fx1Out(3)→7
    c.set(2)
    assert_eq(fx1_out.get(), 3)
    assert_eq(fx2_out.get(), 7)
  })
}
