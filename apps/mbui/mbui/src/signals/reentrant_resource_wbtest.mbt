// A resource can lose its last reader while its computed getter is running.

///|
test "a computed does not retain dependencies read after its last watch stops during an update" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let w : Ref[Watch?] = Ref(None)
  let fired = Ref(false)
  let c = computed(fn(_) {
    let n = value.get()
    if n == 1 {
      fired.val = true
      w.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  w.val = Some(watch(fn() {  }))
  w.val.unwrap().read(fn() { c.get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_false(value.watched(), msg="the stopped watch no longer reads the input")
  assert_false(resource.watched(), msg="the getter's later read must not retain the resource")
  assert_eq(ended.val, 1, msg="the resource is told when its last reader ends")
}

///|
test "a computed remains live for another watch when one stops during an update" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let first : Ref[Watch?] = Ref(None)
  let fired = Ref(false)
  let c = computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      first.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  first.val = Some(watch(fn() {  }))
  let second = watch(fn() {  })
  first.val.unwrap().read(fn() { c.get() }) |> ignore
  second.read(fn() { c.get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_true(resource.watched())
  assert_eq(ended.val, 0)
  assert_eq(second.read(fn() { c.get() }), 1)
  second.stop()
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "a computed releases reads made after the last watch stops during an explicit read" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let w : Ref[Watch?] = Ref(None)
  let fired = Ref(false)
  let c = computed(fn(_) {
    let n = value.get()
    if n == 1 {
      fired.val = true
      w.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  w.val = Some(watch(fn() {  }))
  w.val.unwrap().read(fn() { c.get() }) |> ignore
  start_batch()
  value.set(1)
  let was_fired = fired.val
  w.val.unwrap().read(fn() { c.get() }) |> ignore
  end_batch()
  assert_false(was_fired, msg="the getter had not rerun before the explicit read")
  assert_true(fired.val)
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "a disconnected chain of computeds does not read its resource again while an update unwinds" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  let fired = Ref(false)
  resource.on_unwatched(fn() { ended.val += 1 })
  let w : Ref[Watch?] = Ref(None)
  let leaf = computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      w.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  let middle = computed(fn(_) { leaf.get() })
  let outer = computed(fn(_) { middle.get() })
  w.val = Some(watch(fn() {  }))
  w.val.unwrap().read(fn() { outer.get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_false(resource.watched(), msg="the now-disconnected computed chain must not keep the resource")
  assert_eq(ended.val, 1)
}

///|
test "a computed chain keeps its resource for a second watch when the first stops during update" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  let fired = Ref(false)
  resource.on_unwatched(fn() { ended.val += 1 })
  let first : Ref[Watch?] = Ref(None)
  let leaf = computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      first.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  let middle = computed(fn(_) { leaf.get() })
  let outer = computed(fn(_) { middle.get() })
  first.val = Some(watch(fn() {  }))
  let second = watch(fn() {  })
  first.val.unwrap().read(fn() { outer.get() }) |> ignore
  second.read(fn() { outer.get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_true(resource.watched())
  assert_eq(ended.val, 0)
  assert_eq(second.read(fn() { outer.get() }), 1)
  second.stop()
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "disposing a watched computed during its getter still releases what it read" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  let fired = Ref(false)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c : Ref[Computed[Int]?] = Ref(None)
  c.val = Some(computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      c.val.unwrap().dispose()
    }
    resource.get() |> ignore
    n
  }))
  let w = watch(fn() {  })
  w.read(fn() { c.val.unwrap().get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_false(resource.watched(), msg="explicit dispose releases the computed's dependencies even while it has a reader")
  assert_eq(ended.val, 1)
  w.stop()
}

///|
test "disposing a computed during its first getter releases what that getter reads" {
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c : Ref[Computed[Int]?] = Ref(None)
  c.val = Some(computed(fn(_) {
    c.val.unwrap().dispose()
    resource.get()
  }))
  let w = watch(fn() {  })
  w.read(fn() { c.val.unwrap().get() }) |> ignore
  assert_false(resource.watched(), msg="a dispose during the initial getter must not keep its reads")
  assert_eq(ended.val, 1)
  w.stop()
}

///|
test "a replacement watch can follow a computed before its old watch finishes stopping" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  let fired = Ref(false)
  resource.on_unwatched(fn() { ended.val += 1 })
  let old : Ref[Watch?] = Ref(None)
  let next = watch(fn() {  })
  let c : Ref[Computed[Int]?] = Ref(None)
  c.val = Some(computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      old.val.unwrap().stop()
      next.read(fn() { c.val.unwrap().get() }) |> ignore
    }
    resource.get() |> ignore
    n
  }))
  old.val = Some(watch(fn() {  }))
  old.val.unwrap().read(fn() { c.val.unwrap().get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_true(resource.watched(), msg="the replacement watch keeps the resource")
  assert_eq(ended.val, 0)
  assert_eq(next.read(fn() { c.val.unwrap().get() }), 1)
  value.set(2)
  assert_eq(next.read(fn() { c.val.unwrap().get() }), 2)
  next.stop()
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "a computed reading callback does not retain reads after its last watch stops" {
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c = computed(fn(_) { 1 })
  let w = watch(fn() {  })
  w.read(fn() { c.get() }) |> ignore
  c.reading(fn() {
    w.stop()
    resource.get() |> ignore
  })
  assert_false(resource.watched(), msg="the extra read belongs to the watch which ended")
  assert_eq(ended.val, 1)
}

///|
test "nested computed reading callbacks finish before releasing their last reader's dependencies" {
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c = computed(fn(_) { 1 })
  let w = watch(fn() {  })
  w.read(fn() { c.get() }) |> ignore
  c.reading(fn() {
    c.reading(fn() {
      w.stop()
      resource.get() |> ignore
    })
    resource.get() |> ignore
  })
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "disposing during an extra read survives a synchronous computed update" {
  let value = signal(0)
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c = computed(fn(_) { value.get() |> ignore; resource.get() })
  let w = watch(fn() {  })
  w.read(fn() { c.get() }) |> ignore
  c.reading(fn() {
    c.dispose()
    value.set(1)
    resource.get() |> ignore
  })
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
  w.stop()
}

///|
test "a computed extra read stays live when its other watch remains" {
  let resource = signal(0)
  let ended = Ref(0)
  resource.on_unwatched(fn() { ended.val += 1 })
  let c = computed(fn(_) { 1 })
  let a = watch(fn() {  })
  let b = watch(fn() {  })
  a.read(fn() { c.get() }) |> ignore
  b.read(fn() { c.get() }) |> ignore
  c.reading(fn() {
    a.stop()
    resource.get() |> ignore
  })
  assert_true(resource.watched())
  assert_eq(ended.val, 0)
  b.stop()
  assert_false(resource.watched())
  assert_eq(ended.val, 1)
}

///|
test "an untracked computed chain still checks its nested dependencies" {
  let value = signal(0)
  let leaf = computed(fn(_) { value.get() })
  let middle = computed(fn(_) { leaf.get() })
  let outer = computed(fn(_) { middle.get() })
  assert_eq(outer.get(), 0)
  value.set(1)
  assert_eq(outer.get(), 1)
  outer.dispose()
}

///|
test "a new watch can read an updated chain after its former watch stopped during update" {
  let value = signal(0)
  let resource = signal(0)
  let fired = Ref(false)
  let old : Ref[Watch?] = Ref(None)
  let leaf = computed(fn(_) {
    let n = value.get()
    if n == 1 && !fired.val {
      fired.val = true
      old.val.unwrap().stop()
    }
    resource.get() |> ignore
    n
  })
  let middle = computed(fn(_) { leaf.get() })
  let outer = computed(fn(_) { middle.get() })
  old.val = Some(watch(fn() {  }))
  old.val.unwrap().read(fn() { outer.get() }) |> ignore
  value.set(1)
  assert_true(fired.val)
  assert_false(resource.watched())
  let next = watch(fn() {  })
  assert_eq(next.read(fn() { outer.get() }), 1)
  assert_true(resource.watched())
  value.set(2)
  assert_eq(next.read(fn() { outer.get() }), 2)
  next.stop()
  assert_false(resource.watched())
}
