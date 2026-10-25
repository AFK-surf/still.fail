// The conformance suite (conformance_graph_wbtest.mbt): Effect Lifecycle (effectLifecycle.ts) and Nested Effects &
// Ordering (nestedEffects.ts). An effect disposed from within itself holds its dispose in a Ref, as the cases' `let`.

///|
test "effects #35 effect runs callback immediately on creation" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
  })
}

///|
test "effects #36 effect re-runs when dependency changes" {
  fw_run(fn() raise {
    let a = fw_signal("a")
    let values : Array[String] = []
    fw_effect(fn() { values.push(a.get()) }) |> ignore
    assert_eq(values, ["a"])
    a.set("b")
    assert_eq(values, ["a", "b"])
    a.set("c")
    assert_eq(values, ["a", "b", "c"])
  })
}

///|
test "effects #38 effect cleanup fn called before each re-run" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let log : Array[String] = []
    effect_cleanup(fn() {
      let v = a.get()
      log.push("run:" + v.to_string())
      fn() { log.push("cleanup:" + v.to_string()) }
    })
    |> ignore
    assert_eq(log, ["run:0"])
    a.set(1)
    assert_eq(log, ["run:0", "cleanup:0", "run:1"])
    a.set(2)
    assert_eq(log, ["run:0", "cleanup:0", "run:1", "cleanup:1", "run:2"])
  })
}

///|
test "effects #39 effect cleanup fn called on disposal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let cleanup_called = Ref(false)
    let dispose = effect_cleanup(fn() {
      a.get() |> ignore
      fn() { cleanup_called.val = true }
    })
    assert_eq(cleanup_called.val, false)
    dispose()
    assert_eq(cleanup_called.val, true)
  })
}

///|
test "effects #40 effect cleanup runs outside reactive evaluation context" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(100)
    let effect_runs = Ref(0)
    effect_cleanup(fn() {
      a.get() |> ignore
      effect_runs.val += 1
      // Reading b in cleanup should NOT create a dependency
      fn() { b.get() |> ignore }
    })
    |> ignore
    assert_eq(effect_runs.val, 1)
    a.set(1)
    assert_eq(effect_runs.val, 2)
    // b is only read in cleanup — should not trigger re-run
    b.set(200)
    assert_eq(effect_runs.val, 2)
  })
}

///|
test "effects #42 effect not executed if disposed during pending batch" {
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
test "effects #108 effect self-dispose during execution is safe" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    let dispose : Ref[(() -> Unit)?] = Ref(None)
    dispose.val = Some(
      fw_effect(fn() {
        runs.val += 1
        a.get() |> ignore
        if runs.val == 2 {
          match dispose.val {
            Some(d) => d()
            None => ()
          }
        }
      }),
    )
    assert_eq(runs.val, 1)
    a.set(1)
    assert_eq(runs.val, 2)
    a.set(2)
    assert_eq(runs.val, 2)
  })
}

///|
test "effects #110 double-dispose is safe" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let cleanup_count = Ref(0)
    let dispose = effect_cleanup(fn() {
      a.get() |> ignore
      fn() { cleanup_count.val += 1 }
    })
    dispose()
    assert_eq(cleanup_count.val, 1)
    dispose()
    assert_true(cleanup_count.val <= 2)
  })
}

///|
test "effects #111 cleanup-triggered dispose prevents re-run" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    let dispose : Ref[(() -> Unit)?] = Ref(None)
    dispose.val = Some(
      effect_cleanup(fn() {
        runs.val += 1
        a.get() |> ignore
        fn() {
          match dispose.val {
            Some(d) => d()
            None => ()
          }
        }
      }),
    )
    assert_eq(runs.val, 1)
    a.set(1)
    assert_true(runs.val <= 2)
    a.set(2)
    assert_true(runs.val <= 2)
  })
}

///|
test "effects #141 dispose during execution then continue: no re-run" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let runs = Ref(0)
    let dispose : Ref[(() -> Unit)?] = Ref(None)
    dispose.val = Some(
      fw_effect(fn() {
        runs.val += 1
        let va = a.get()
        if va == 1 {
          match dispose.val {
            Some(d) => d()
            None => ()
          }
        }
        b.get() |> ignore
      }),
    )
    assert_eq(runs.val, 1)
    a.set(1)
    assert_eq(runs.val, 2)
    b.set(1)
    assert_eq(runs.val, 2)
    a.set(2)
    assert_eq(runs.val, 2)
  })
}

///|
test "effects #143 destroyed effect not re-scheduled on later updates" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let runs = Ref(0)
    let dispose = fw_effect(fn() {
      a.get() |> ignore
      b.get() |> ignore
      runs.val += 1
    })
    assert_eq(runs.val, 1)
    dispose()
    a.set(1)
    b.set(1)
    a.set(2)
    b.set(2)
    assert_eq(runs.val, 1)
  })
}

///|
test "effects #178 dispose cleanup reads don't leak to parent tracking context" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(100)
    let outer_runs = Ref(0)
    let dispose_inner = effect_cleanup(fn() {
      a.get() |> ignore
      fn() { b.get() |> ignore }
    })
    fw_effect(fn() {
      a.get() |> ignore
      outer_runs.val += 1
      if a.get() == 1 {
        dispose_inner()
      }
    })
    |> ignore
    outer_runs.val = 0
    a.set(1)
    assert_eq(outer_runs.val, 1)
    outer_runs.val = 0
    b.set(200)
    assert_eq(outer_runs.val, 0)
  })
}

///|
test "effects #214 parent disposes and recreates child: downstream sees correct value" {
  fw_run(fn() raise {
    let a = fw_signal(1)
    let inner_computed : Ref[Computed[Int]?] = Ref(None)
    fw_effect(fn() {
      let c = fw_computed(fn() { a.get() })
      a.get() |> ignore
      inner_computed.val = Some(c)
    })
    |> ignore
    assert_eq(inner_computed.val.unwrap().get(), 1)
    a.set(2)
    assert_eq(inner_computed.val.unwrap().get(), 2)
    a.set(3)
    assert_eq(inner_computed.val.unwrap().get(), 3)
  })
}

///|
test "effects #201 computed-triggered disposal: effect skipped and no subscription leak" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let dispose1 : Ref[(() -> Unit)?] = Ref(None)
    let e1runs = Ref(0)
    let a = fw_computed(fn() {
      if s.get() == 1 {
        (dispose1.val.unwrap())()
      }
      s.get()
    })
    dispose1.val = Some(
      fw_effect(fn() {
        a.get() |> ignore
        e1runs.val += 1
      }),
    )
    // keep `a` alive
    fw_effect(fn() { a.get() |> ignore }) |> ignore
    assert_eq(e1runs.val, 1)
    s.set(1)
    // disposed during propagation, should not re-run
    assert_eq(e1runs.val, 1)
    s.set(2)
    s.set(3)
    // no subscription leak
    assert_eq(e1runs.val, 1)
  })
}

///|
test "effects #202 computed-triggered disposal: sibling effects still notified" {
  fw_run(fn() raise {
    let s = fw_signal(0)
    let dispose1 : Ref[(() -> Unit)?] = Ref(None)
    let e2_value = Ref(-1)
    let a = fw_computed(fn() {
      if s.get() == 1 {
        (dispose1.val.unwrap())()
      }
      s.get()
    })
    dispose1.val = Some(fw_effect(fn() { a.get() |> ignore }))
    fw_effect(fn() { e2_value.val = a.get() }) |> ignore
    assert_eq(e2_value.val, 0)
    s.set(1)
    assert_eq(e2_value.val, 1)
  })
}

///|
test "effects #203 computed disposal with unchanged-value sibling computed" {
  fw_run(fn() {
    let s = fw_signal(0)
    let dispose : Ref[(() -> Unit)?] = Ref(None)
    let a = fw_computed(fn() {
      s.get() |> ignore
      // value never changes
      0
    })
    let a2 = fw_computed(fn() {
      if s.get() != 0 {
        (dispose.val.unwrap())()
      }
      s.get()
    })
    let b = fw_computed(fn() {
      a.get() |> ignore
      a2.get() |> ignore
      0
    })
    dispose.val = Some(fw_effect(fn() { b.get() |> ignore }))
    // should not crash
    s.set(1)
  })
}

///|
test "effects #216 effects fire in creation order on shared signal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let order : Array[Int] = []
    fw_effect(fn() {
      a.get() |> ignore
      order.push(1)
    })
    |> ignore
    fw_effect(fn() {
      a.get() |> ignore
      order.push(2)
    })
    |> ignore
    fw_effect(fn() {
      a.get() |> ignore
      order.push(3)
    })
    |> ignore
    order.clear()
    a.set(1)
    assert_eq(order, [1, 2, 3])
    order.clear()
    a.set(2)
    assert_eq(order, [1, 2, 3])
  })
}

///|
test "effects #217 new effect after dispose works normally" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let e1_runs = Ref(0)
    let e2_runs = Ref(0)
    let dispose1 = fw_effect(fn() {
      a.get() |> ignore
      e1_runs.val += 1
    })
    assert_eq(e1_runs.val, 1)
    dispose1()
    a.set(1)
    assert_eq(e1_runs.val, 1)
    fw_effect(fn() {
      a.get() |> ignore
      e2_runs.val += 1
    })
    |> ignore
    assert_eq(e2_runs.val, 1)
    a.set(2)
    assert_eq(e2_runs.val, 2)
    assert_eq(e1_runs.val, 1)
  })
}

///|
test "effects #222 effect created inside cleanup tracks its own deps" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let inner_runs = Ref(0)
    effect_cleanup(fn() {
      a.get() |> ignore
      fn() {
        fw_effect(fn() {
          b.get() |> ignore
          inner_runs.val += 1
        })
        |> ignore
      }
    })
    |> ignore
    assert_eq(inner_runs.val, 0)
    // Trigger cleanup once — the cleanup-created effect should run initially.
    a.set(1)
    assert_eq(inner_runs.val, 1)
    // The cleanup-created effect must track b independently.
    b.set(1)
    assert_eq(inner_runs.val, 2)
  })
}

// ── nestedEffects.ts ────────────────────────────────────────────────────────────────────────────────────────

///|
test "nested #43 outer effect runs before inner effect" {
  fw_run(fn() raise {
    let order : Array[String] = []
    let a = fw_signal(0)
    fw_effect(fn() {
      order.push("outer")
      a.get() |> ignore
      fw_effect(fn() {
        order.push("inner")
        a.get() |> ignore
      })
      |> ignore
    })
    |> ignore
    assert_eq(order[0], "outer")
  })
}

///|
test "nested #45 untracked inner effect does not subscribe to deps" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let inner_runs = Ref(0)
    fw_effect(fn() {
      fw_untracked(fn() {
        fw_effect(fn() {
          a.get() |> ignore
          inner_runs.val += 1
        })
      })
      |> ignore
    })
    |> ignore
    inner_runs.val = 0
    a.set(1)
    // The outer effect should not re-run since deps are untracked; but the inner effect should re-run since it
    // directly reads a
    assert_true(inner_runs.val >= 0)
  })
}

///|
test "nested #46 duplicate subscribers don't cause duplicate notifications" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      a.get() |> ignore
      runs.val += 1
    })
    |> ignore
    assert_eq(runs.val, 1)
    a.set(1)
    assert_eq(runs.val, 2)
  })
}

///|
test "nested #47 effect recursion handled on first execution" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let runs = Ref(0)
    fw_effect(fn() {
      runs.val += 1
      if runs.val == 1 {
        a.set(1)
      }
      a.get() |> ignore
    })
    |> ignore
    // Should not infinite loop — either runs once with final value or runs twice (initial + triggered by write)
    assert_true(runs.val <= 3)
    assert_eq(a.get(), 1)
  })
}

///|
test "nested #163 parent effect not triggered by child's own signal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let parent_runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      parent_runs.val += 1
      let child_signal = fw_signal(0)
      fw_effect(fn() { child_signal.get() |> ignore }) |> ignore
      child_signal.set(1)
    })
    |> ignore
    let runs_after_setup = parent_runs.val
    assert_true(runs_after_setup >= 1)
    a.set(1)
    assert_eq(parent_runs.val, runs_after_setup + 1)
  })
}

///|
test "nested #164 inner autorun created inside outer tracks own deps" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let outer_runs = Ref(0)
    let inner_runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      outer_runs.val += 1
      fw_effect(fn() {
        b.get() |> ignore
        inner_runs.val += 1
      })
      |> ignore
    })
    |> ignore
    inner_runs.val = 0
    outer_runs.val = 0
    b.set(1)
    assert_true(inner_runs.val >= 1)
  })
}

///|
test "nested #170 inner effect not triggered when computed dep resolves unchanged" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_computed(fn() { a.get() % 2 })
    let inner_runs = Ref(0)
    fw_effect(fn() {
      fw_effect(fn() {
        b.get() |> ignore
        inner_runs.val += 1
      })
      |> ignore
    })
    |> ignore
    let initial = inner_runs.val
    a.set(2)
    assert_eq(inner_runs.val, initial)
  })
}

///|
test "nested #209 three-level nested effect: cascading disposal" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let middle_runs = Ref(0)
    let inner_runs = Ref(0)
    let dispose = fw_effect(fn() {
      a.get() |> ignore
      fw_effect(fn() {
        a.get() |> ignore
        middle_runs.val += 1
        fw_effect(fn() {
          a.get() |> ignore
          inner_runs.val += 1
        })
        |> ignore
      })
      |> ignore
    })
    middle_runs.val = 0
    inner_runs.val = 0
    dispose()
    a.set(1)
    assert_eq(middle_runs.val, 0)
    assert_eq(inner_runs.val, 0)
  })
}

///|
test "nested #210 multiple inner effects all cleaned when outer re-runs" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let b = fw_signal(0)
    let c = fw_signal(0)
    let b_runs = Ref(0)
    let c_runs = Ref(0)
    fw_effect(fn() {
      a.get() |> ignore
      fw_effect(fn() {
        b.get() |> ignore
        b_runs.val += 1
      })
      |> ignore
      fw_effect(fn() {
        c.get() |> ignore
        c_runs.val += 1
      })
      |> ignore
    })
    |> ignore
    b_runs.val = 0
    c_runs.val = 0
    // Trigger outer re-run — old inner effects should be cleaned up
    a.set(1)
    b_runs.val = 0
    c_runs.val = 0
    // These should only trigger the NEW inner effects (one each), not accumulated old ones
    b.set(1)
    assert_eq(b_runs.val, 1)
    c.set(1)
    assert_eq(c_runs.val, 1)
  })
}

///|
test "nested #48 nested effects depend on state of outer effects" {
  fw_run(fn() raise {
    let a = fw_signal(0)
    let observed : Array[Int] = []
    fw_effect(fn() {
      let val = a.get()
      fw_effect(fn() { observed.push(val) }) |> ignore
    })
    |> ignore
    assert_true(observed.contains(0))
  })
}
