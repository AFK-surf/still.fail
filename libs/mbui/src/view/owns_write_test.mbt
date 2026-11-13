// What a node does as it is let go (View::owns) is told like any other change: a signal written there, what reads it
// elsewhere in the tree (another layer's show) follows it, as it does a write from a handler.

///|
test "a signal written as a node is let go (its owns): a show elsewhere that reads it goes" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    // (node A, there while `here` says so; as it is let go it writes `open`)
    root.show(at_once=true, fn() { here.get() }, fn(a) {
      a.words(Is("甲")) |> ignore
      a.owns(fn() { open.set(false) }) |> ignore
    })
    // (another layer: what it shows there while `open` says so)
    root.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      layer.show(at_once=true, fn() { open.get() }, fn(m) { m.words(Is("甲一")) |> ignore })
    })
    |> ignore
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(t.drawn().iter().any(fn(d) { d.words == "甲一" }), msg="shown at first")
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_false(t.drawn().iter().any(fn(d) { d.words == "甲" }), msg="A let go")
  assert_false(open.get(), msg="its owns wrote the signal")
  assert_false(t.drawn().iter().any(fn(d) { d.words == "甲一" }), msg="the show that reads it gone")
}

///|
test "the same signal written in a handler: the show elsewhere that reads it goes" {
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(a) {
      a.width(Is(Some(100.0))).height(Is(Some(40.0))).presses(Is(true)).on_press(fn() { open.set(false) }) |> ignore
    })
    |> ignore
    root.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      layer.show(at_once=true, fn() { open.get() }, fn(m) { m.words(Is("甲一")) |> ignore })
    })
    |> ignore
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(t.drawn().iter().any(fn(d) { d.words == "甲一" }), msg="shown at first")
  open.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_false(t.drawn().iter().any(fn(d) { d.words == "甲一" }), msg="the show that reads it gone")
}
