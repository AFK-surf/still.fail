// alien-signals' own tests (tests/effect.spec.ts, effectScope.spec.ts, trigger.spec.ts), ported as they are.

// ── effect.spec.ts ──────────────────────────────────────────────────────────────────────────────────────────

///|
test "should support custom recurse effect" {
  let src = signal(0)
  let triggers = Ref(0)
  effect(fn() {
    let sub = active_sub().unwrap()
    sub.flags = sub.flags & RECURSED_CHECK.lnot()
    triggers.val += 1
    src.set(if src.get() + 1 < 5 { src.get() + 1 } else { 5 })
  })
  |> ignore
  assert_eq(triggers.val, 6)
}

///|
test "cleanup order on outer re-run: inner before outer, before new run" {
  let log : Array[String] = []
  let a = signal(0)
  effect_cleanup(fn() {
    a.get() |> ignore
    log.push("outer:run")
    effect_cleanup(fn() {
      log.push("inner:run")
      fn() { log.push("inner:cleanup") }
    })
    |> ignore
    fn() { log.push("outer:cleanup") }
  })
  |> ignore
  assert_eq(log, ["outer:run", "inner:run"])
  log.clear()
  a.set(1)
  assert_eq(log, ["inner:cleanup", "outer:cleanup", "outer:run", "inner:run"])
}

///|
test "cleanup order on dispose: inner before outer" {
  let log : Array[String] = []
  let dispose = effect_cleanup(fn() {
    log.push("outer:run")
    effect_cleanup(fn() {
      log.push("inner:run")
      fn() { log.push("inner:cleanup") }
    })
    |> ignore
    fn() { log.push("outer:cleanup") }
  })
  log.clear()
  dispose()
  assert_eq(log, ["inner:cleanup", "outer:cleanup"])
}

///|
test "sibling cleanup order on dispose: reverse creation (LIFO)" {
  let log : Array[String] = []
  let dispose = effect_cleanup(fn() {
    effect_cleanup(fn() { fn() { log.push("inner1:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("inner2:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("inner3:cleanup") } }) |> ignore
    fn() { log.push("outer:cleanup") }
  })
  dispose()
  assert_eq(log, ["inner3:cleanup", "inner2:cleanup", "inner1:cleanup", "outer:cleanup"])
}

///|
test "sibling cleanup order on outer re-run: reverse creation (LIFO)" {
  let log : Array[String] = []
  let a = signal(0)
  effect_cleanup(fn() {
    a.get() |> ignore
    effect_cleanup(fn() { fn() { log.push("inner1:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("inner2:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("inner3:cleanup") } }) |> ignore
    fn() { log.push("outer:cleanup") }
  })
  |> ignore
  log.clear()
  a.set(1)
  assert_eq(log[0:4].to_owned(), ["inner3:cleanup", "inner2:cleanup", "inner1:cleanup", "outer:cleanup"])
}

///|
test "three-level nested cleanup on dispose: deepest first (depth-first reverse)" {
  let log : Array[String] = []
  let dispose = effect_cleanup(fn() {
    effect_cleanup(fn() {
      effect_cleanup(fn() { fn() { log.push("grandchild:cleanup") } }) |> ignore
      fn() { log.push("child:cleanup") }
    })
    |> ignore
    fn() { log.push("outer:cleanup") }
  })
  dispose()
  assert_eq(log, ["grandchild:cleanup", "child:cleanup", "outer:cleanup"])
}

///|
test "computed unwatched: child effect cleanups run in reverse creation (LIFO)" {
  // When the computed loses its last subscriber and gets unwatched, any effects it created during its getter must be
  // cleaned up LIFO, not FIFO.
  let log : Array[String] = []
  let c = computed(fn(_) {
    effect_cleanup(fn() { fn() { log.push("e1") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("e2") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("e3") } }) |> ignore
    0
  })
  let dispose = effect(fn() { c.get() |> ignore })
  log.clear()
  dispose()
  assert_eq(log, ["e3", "e2", "e1"])
}

///|
test "effect created inside computed: old inner cleanup runs before new inner setup" {
  // When a computed re-evaluates, any effects its getter created on the previous run must be disposed (with cleanup)
  // before the getter runs again. Otherwise the old inner's cleanup ends up running after the new inner has already
  // been set up.
  let a = signal(0)
  let log : Array[String] = []
  let c = computed(fn(_) {
    log.push("computed:eval")
    effect_cleanup(fn() {
      log.push("inner:run")
      fn() { log.push("inner:cleanup") }
    })
    |> ignore
    a.get()
  })
  effect(fn() { c.get() |> ignore }) |> ignore
  log.clear()
  a.set(1)
  assert_eq(log, ["inner:cleanup", "computed:eval", "inner:run"])
}

///|
test "cleanup order is correct on outer re-run after a prior inner-only re-run" {
  // Regression: inner re-running alone routes outer through run()'s not-dirty branch (restore Watching), which must
  // preserve any "has child effect" tracking so the next real outer re-run still disposes children before its own
  // cleanup.
  let a = signal(0)
  let b = signal(0)
  let log : Array[String] = []
  effect_cleanup(fn() {
    a.get() |> ignore
    log.push("outer:run")
    effect_cleanup(fn() {
      b.get() |> ignore
      log.push("inner:run")
      fn() { log.push("inner:cleanup") }
    })
    |> ignore
    fn() { log.push("outer:cleanup") }
  })
  |> ignore
  // inner re-runs alone; outer is touched via notify chain
  b.set(1)
  log.clear()
  a.set(1)
  assert_eq(log, ["inner:cleanup", "outer:cleanup", "outer:run", "inner:run"])
}

///|
test "outer effect keeps responding to its own dep after inner re-runs (issue 115)" {
  let a = signal(0)
  let b = signal(0)
  let outer_runs = Ref(0)
  let inner_runs = Ref(0)
  effect(fn() {
    a.get() |> ignore
    outer_runs.val += 1
    effect(fn() {
      b.get() |> ignore
      inner_runs.val += 1
    })
    |> ignore
  })
  |> ignore
  assert_eq(outer_runs.val, 1)
  assert_eq(inner_runs.val, 1)
  b.set(1)
  assert_eq(outer_runs.val, 1)
  assert_true(inner_runs.val >= 2)
  a.set(1)
  assert_eq(outer_runs.val, 2)
}

// ── effectScope.spec.ts ─────────────────────────────────────────────────────────────────────────────────────

///|
test "scope dispose runs child effect cleanup" {
  let log : Array[String] = []
  let dispose = effect_scope(fn() {
    effect_cleanup(fn() { fn() { log.push("inner:cleanup") } }) |> ignore
  })
  dispose()
  assert_eq(log, ["inner:cleanup"])
}

///|
test "scope dispose: sibling effects clean up in reverse creation (LIFO)" {
  let log : Array[String] = []
  let dispose = effect_scope(fn() {
    effect_cleanup(fn() { fn() { log.push("e1:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("e2:cleanup") } }) |> ignore
    effect_cleanup(fn() { fn() { log.push("e3:cleanup") } }) |> ignore
  })
  dispose()
  assert_eq(log, ["e3:cleanup", "e2:cleanup", "e1:cleanup"])
}

///|
test "scope dispose: nested effect cleanup runs depth-first reverse" {
  let log : Array[String] = []
  let dispose = effect_scope(fn() {
    effect_cleanup(fn() {
      effect_cleanup(fn() { fn() { log.push("grandchild:cleanup") } }) |> ignore
      fn() { log.push("child:cleanup") }
    })
    |> ignore
  })
  dispose()
  assert_eq(log, ["grandchild:cleanup", "child:cleanup"])
}

///|
test "scope as intermediate parent: cleanup order respects nesting" {
  // When effectScope is used as an intermediate scope inside an outer effect, the outer's re-run must still dispose
  // the scope (and its effects) before running the outer's own cleanup.
  let a = signal(0)
  let log : Array[String] = []
  effect_cleanup(fn() {
    a.get() |> ignore
    log.push("outer:run")
    effect_scope(fn() {
      effect_cleanup(fn() {
        log.push("inner:run")
        fn() { log.push("inner:cleanup") }
      })
      |> ignore
    })
    |> ignore
    fn() { log.push("outer:cleanup") }
  })
  |> ignore
  log.clear()
  a.set(1)
  assert_eq(log, ["inner:cleanup", "outer:cleanup", "outer:run", "inner:run"])
}

// ── trigger.spec.ts ─────────────────────────────────────────────────────────────────────────────────────────

///|
test "should not throw when triggering with no dependencies" {
  trigger(fn() {  })
}

///|
test "should trigger updates for dependent computed signals" {
  let arr : Signal[Array[Int]] = signal([])
  let length = computed(fn(_) { arr.get().length() })
  assert_eq(length.get(), 0)
  arr.get().push(1)
  trigger(fn() { arr.get() |> ignore })
  assert_eq(length.get(), 1)
}

///|
test "should trigger updates for the second source signal" {
  let src1 : Signal[Array[Int]] = signal([])
  let src2 : Signal[Array[Int]] = signal([])
  let length = computed(fn(_) { src2.get().length() })
  assert_eq(length.get(), 0)
  src2.get().push(1)
  trigger(fn() {
    src1.get() |> ignore
    src2.get() |> ignore
  })
  assert_eq(length.get(), 1)
}

///|
test "should trigger effect once" {
  let src1 : Signal[Array[Int]] = signal([])
  let src2 : Signal[Array[Int]] = signal([])
  let triggers = Ref(0)
  effect(fn() {
    triggers.val += 1
    src1.get() |> ignore
    src2.get() |> ignore
  })
  |> ignore
  assert_eq(triggers.val, 1)
  trigger(fn() {
    src1.get() |> ignore
    src2.get() |> ignore
  })
  assert_eq(triggers.val, 2)
}

///|
test "should not notify the trigger function sub" {
  let src1 : Signal[Array[Int]] = signal([])
  let src2 = computed(fn(_) { src1.get() })
  effect(fn() {
    src1.get() |> ignore
    src2.get() |> ignore
  })
  |> ignore
  trigger(fn() {
    src1.get() |> ignore
    src2.get() |> ignore
  })
}

///|
test "should allow writing a signal after reading it" {
  let src1 = signal(1)
  trigger(fn() {
    src1.get() |> ignore
    src1.set(src1.get() + 1)
  })
  assert_eq(src1.get(), 2)
}

///|
test "should rerun effect once when writing a signal after reading it" {
  let src1 = signal(1)
  let triggers = Ref(0)
  effect(fn() {
    triggers.val += 1
    src1.get() |> ignore
  })
  |> ignore
  assert_eq(triggers.val, 1)
  trigger(fn() {
    src1.get() |> ignore
    src1.set(src1.get() + 1)
  })
  assert_eq(triggers.val, 2)
  assert_eq(src1.get(), 2)
}

///|
test "a computed reading what is built for it after it ran, and what another read" {
  let a = signal(1)
  let b = signal(10)
  let runs = Ref(0)
  let holder = computed(fn(_) {
    runs.val = runs.val + 1
    a.get()
  })
  assert_eq(holder.get(), 1)
  // (read for it after its run: b changed, it runs again)
  holder.reading(fn() { b.get() }) |> ignore
  b.set(11)
  assert_eq(holder.get(), 1)
  assert_eq(runs.val, 2)
  // its run read b no more: let go
  b.set(12)
  assert_eq(holder.get(), 1)
  assert_eq(runs.val, 2)
  // what another computed read, lent to it
  let c = signal(100)
  let other = computed(fn(_) { c.get() })
  assert_eq(other.get(), 100)
  other.lend(holder)
  c.set(101)
  assert_eq(holder.get(), 1)
  assert_eq(runs.val, 3)
  // (its run read c no more)
  c.set(102)
  holder.get() |> ignore
  assert_eq(runs.val, 3)
  assert_eq(other.get(), 102)
}
