///|
test "hover provenance follows an unchanged cached answer and is removed by a later model input" {
  let hovering = signal(false)
  let inner = computed(fn(_) {
    if hovering.get() { hover_read() }
    4
  })
  let outer = computed(fn(_) { untracked(fn() { inner.get() }) + 1 })
  assert_eq(before_hover(fn() { outer.get() }), 5)
  // An untracked answer is still cached; explicitly invalidate its reader.
  hovering.set(true)
  outer.invalidate()
  assert_eq(outer.get(), 5)
  assert_true(outer.0.observes_hover)
  hovering.set(false)
  outer.invalidate()
  assert_eq(before_hover(fn() { outer.get() }), 5)
  assert_false(outer.0.observes_hover)
}

///|
test "a reply relaying hover through an equal signal value preserves its source until another input sets it" {
  let relay = signal(4, same=fn(a, b) { a == b })
  let outer = computed(fn(_) { relay.get() + 1 })
  let w = watch(fn() { })
  defer { w.stop() }
  assert_eq(before_hover(fn() { outer.get() }), 5)
  let answer = w.read(fn() { hover_read(); 4 })
  w.reply(fn() { relay.set(answer) })
  assert_eq(outer.get(), 5)
  assert_true(outer.0.observes_hover)
  relay.set(4)
  assert_eq(before_hover(fn() { outer.get() }), 5)
  assert_false(outer.0.observes_hover)
}

///|
test "a paint watch belongs to its owner without making the owner's answer depend on hover" {
  let w = watch(fn() { })
  defer { w.stop() }
  let owner = computed(fn(_) {
    w.read(fn() { hover_read(); true }) |> ignore
    2
  })
  assert_eq(owner.get(), 2)
  assert_eq(before_hover(fn() { owner.get() }), 2)
  assert_false(owner.0.observes_hover)
  assert_true(w.node.observes_hover)
}

///|
test "hover dependencies discovered or lent after caching reach existing readers" {
  let source = computed(fn(_) { 2 })
  let target = computed(fn(_) { 3 })
  let source_reader = computed(fn(_) { source.get() + 1 })
  let target_reader = computed(fn(_) { target.get() + 1 })
  assert_eq(before_hover(fn() { source_reader.get() }), 3)
  assert_eq(before_hover(fn() { target_reader.get() }), 4)
  source.reading(fn() { hover_read() })
  source.lend(target)
  assert_true(source_reader.0.observes_hover)
  assert_true(target_reader.0.observes_hover)
}

///|
test "a paint reply owns its extra reads without tainting the computed that runs it" {
  let paint = watch(fn() { })
  defer { paint.stop() }
  let ink = signal(false)
  let owner = computed(fn(_) {
    let value = paint.read(fn() { true })
    paint.reply(fn() {
      hover_read()
      ink.set(value)
    })
    2
  })
  assert_eq(owner.get(), 2)
  assert_false(owner.0.observes_hover, msg="a binding's reply is its own computation")
  assert_true(ink.get())
  assert_true(ink.0.observes_hover, msg="the hover read in the reply still reaches its output")
}

///|
test "a nested reply still carries the hover that caused it" {
  let outer = watch(fn() { })
  let inner = watch(fn() { })
  defer { outer.stop(); inner.stop() }
  let relay = signal(false)
  outer.read(fn() { hover_read() })
  inner.read(fn() { })
  outer.reply(fn() {
    inner.reply(fn() { relay.set(true) })
  })
  assert_true(relay.get())
  assert_true(relay.0.observes_hover)
}
