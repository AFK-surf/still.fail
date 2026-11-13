// Watch (signals.mbt): what a run read followed, the run never run again by it.

///|
test "a watch is stale until read, then as what it read changes, told once" {
  let a = signal(1)
  let b = signal(10)
  let told = Ref(0)
  let w = watch(fn() { told.val += 1 })
  assert_true(w.is_stale())
  let runs = Ref(0)
  let v = w.read(fn() {
    runs.val += 1
    a.get() + 1
  })
  assert_eq(v, 2)
  assert_true(!w.is_stale())
  // (what it did not read: nothing)
  b.set(11)
  assert_true(!w.is_stale())
  assert_eq(told.val, 0)
  // (set to what it is: nothing)
  a.set(1)
  assert_true(!w.is_stale())
  a.set(2)
  assert_true(w.is_stale())
  assert_eq(told.val, 1)
  a.set(3)
  assert_eq(told.val, 1)
  // (never run again by it)
  assert_eq(runs.val, 1)
}

///|
test "a watch follows what its last read read, not what the one before read" {
  let a = signal(1)
  let b = signal(1)
  let told = Ref(0)
  let w = watch(fn() { told.val += 1 })
  w.read(fn() { a.get() }) |> ignore
  w.read(fn() { b.get() }) |> ignore
  a.set(2)
  assert_true(!w.is_stale())
  b.set(2)
  assert_true(w.is_stale())
  assert_eq(told.val, 1)
}

///|
test "a watch through a computed: told only where the computed's value changes" {
  let a = signal(1)
  let odd = computed(fn(_) { a.get() % 2 == 1 })
  let told = Ref(0)
  let w = watch(fn() { told.val += 1 })
  w.read(fn() { odd.get() }) |> ignore
  a.set(3)
  assert_true(!w.is_stale())
  assert_eq(told.val, 0)
  a.set(4)
  assert_true(w.is_stale())
  assert_eq(told.val, 1)
}

///|
test "what a watch read set again as it read: stale at its end, told" {
  let a = signal(1)
  let told = Ref(0)
  let w = watch(fn() { told.val += 1 })
  w.read(fn() {
    a.get() |> ignore
    a.set(2)
  })
  assert_true(w.is_stale())
  assert_eq(told.val, 1)
}

///|
test "what is reading as a watch reads does not read what it reads" {
  let a = signal(1)
  let outer_runs = Ref(0)
  let w = watch(fn() {  })
  effect(fn() {
    outer_runs.val += 1
    w.read(fn() { a.get() }) |> ignore
  })
  |> ignore
  a.set(2)
  assert_eq(outer_runs.val, 1)
  assert_true(w.is_stale())
}

///|
test "a watch stopped follows nothing" {
  let a = signal(1)
  let told = Ref(0)
  let w = watch(fn() { told.val += 1 })
  w.read(fn() { a.get() }) |> ignore
  w.stop()
  a.set(2)
  assert_eq(told.val, 0)
  assert_true(w.is_stale())
}

///|
test "a watch touched as it reads stays stale after the read: what it holds told as it is built is not lost" {
  let s = signal(0)
  let told = Ref(0)
  let w = watch(fn() { told.val = told.val + 1 })
  // (an inner part told as the outer one builds: the outer touched during its own read)
  w.read(fn() {
    s.get() |> ignore
    w.touch()
  })
  assert_true(w.is_stale())
  // (read again with nothing touching it: fresh)
  w.read(fn() { s.get() |> ignore })
  assert_false(w.is_stale())
  // (what it read changing still tells it)
  s.set(1)
  assert_eq((w.is_stale(), told.val), (true, 1))
}
