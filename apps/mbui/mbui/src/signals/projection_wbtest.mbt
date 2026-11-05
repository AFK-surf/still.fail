///|
test "captured model inputs keep dependencies and change their computed source" {
  let model = signal(2)
  let use_output = signal(true)
  let value = computed(fn(_) {
    if use_output.get() { output_read() }
    model.get() * 2
  })
  let outer = computed(fn(_) { value.get() + 1 })
  assert_eq(outer.get(), 5)
  use_output.set(false)
  assert_eq(capture_inputs(fn() { outer.get() }), 5)
  let seen = Ref(0)
  let stop = effect(fn() { seen.val = capture_inputs(fn() { outer.get() }) })
  defer { stop() }
  model.set(4)
  assert_eq(seen.val, 9)
  assert_eq(project(fn() { 8 + 1 }), 9)
}

///|
test "output provenance crosses cached computeds even when the numeric answer is unchanged" {
  let use_output = signal(false)
  let value = computed(fn(_) {
    if use_output.get() { output_read() }
    4
  })
  let outer = computed(fn(_) { value.get() + 1 })
  outer.get() |> ignore
  assert_false(outer.0.observes_output)
  use_output.set(true)
  assert_eq(outer.get(), 5)
  assert_true(outer.0.observes_output)
  use_output.set(false)
  assert_eq(capture_inputs(fn() { outer.get() }), 5)
  assert_false(outer.0.observes_output)
}

///|
test "untracked output remains an output in a cached computed" {
  let value = computed(fn(_) { untracked(fn() { output_read(); 4 }) })
  value.get() |> ignore
  let outer = computed(fn(_) { value.peek().unwrap_or(0) + 1 })
  assert_eq(outer.get(), 5)
  assert_true(outer.0.observes_output)
}

///|
test "a borrowed dependency scope cannot hide output provenance from its caller" {
  let source = computed(fn(_) { 0 })
  let outer = computed(fn(_) {
    source.reading(fn() { output_read(); 4 }) + 1
  })
  assert_eq(outer.get(), 5)
  assert_true(source.0.observes_output)
  assert_true(outer.0.observes_output)
}

///|
test "output discovered after a computed ran reaches already cached readers" {
  let model = signal(0)
  let source = computed(fn(_) { model.get() })
  let middle = computed(fn(_) { source.get() + 1 })
  let outer = computed(fn(_) { middle.get() + 1 })
  assert_eq(capture_inputs(fn() { outer.get() }), 2)
  source.reading(fn() { output_read() })
  assert_true(middle.0.observes_output)
  assert_true(outer.0.observes_output)
  model.set(1)
  assert_eq(capture_inputs(fn() { outer.get() }), 3)
}

///|
test "lending output dependencies reaches already cached readers of the recipient" {
  let source = computed(fn(_) { output_read(); 4 })
  let target = computed(fn(_) { 2 })
  let outer = computed(fn(_) { target.get() + 1 })
  source.get() |> ignore
  assert_eq(capture_inputs(fn() { outer.get() }), 3)
  source.lend(target)
  assert_true(target.0.observes_output)
  assert_true(outer.0.observes_output)
}
