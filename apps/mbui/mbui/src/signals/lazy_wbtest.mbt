///|
test "a deferred signal keeps its value's source, not its first reader's" {
  let input = lazy_signal(false)
  let paint = watch(fn() { })
  defer { paint.stop() }
  assert_false(input.is_read())
  paint.read(fn() { hover_read(); input.get() }) |> ignore
  assert_true(input.is_read())
  assert_false(before_hover(fn() { input.get() }))
  assert_true(paint.node.observes_hover)
  input.set(true)
  assert_true(before_hover(fn() { input.get() }))
}

///|
test "a deferred signal preserves hover from its initialization and writes, before or after its first read" {
  let w = watch(fn() { })
  defer { w.stop() }
  let made = w.read(fn() { hover_read(); lazy_signal(false) })
  made.get() |> ignore
  assert_true(made.cell.unwrap().0.observes_hover)
  for read_first in [false, true] {
    let relay = lazy_signal(false, same=fn(a, b) { a == b })
    if read_first { relay.get() |> ignore }
    w.read(fn() { hover_read() })
    w.reply(fn() { relay.set(false) })
    relay.get() |> ignore
    assert_true(relay.cell.unwrap().0.observes_hover)
    relay.set(false)
    assert_false(before_hover(fn() { relay.get() }))
    assert_false(relay.cell.unwrap().0.observes_hover)
  }
}
