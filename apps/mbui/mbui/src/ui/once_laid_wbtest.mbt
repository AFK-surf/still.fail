// What is to be done once things are laid out, a node's (View::once_laid_out): done once, every pass over and the sizes
// told; not done where its node is let go first.

///|
test "a node's once laid out: done once, its size told by then" {
  let sizes : Array[(Double, Double)?] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.width(Is(Some(120.0))).height(Is(Some(30.0))) |> ignore
      // (followed from before: told as of the first layout)
      @signals.untracked(fn() { n.laid_size_told() }) |> ignore
      n.once_laid_out(fn() { sizes.push(n.laid_size_told()) })
    })
    |> ignore
  })
  t.draw()
  t.draw()
  assert_eq(sizes, [Some((120.0, 30.0))])
}

///|
test "a node's once laid out is not done where the node is let go before" {
  let done = Ref(0)
  let shown = @signals.signal(true)
  let go = @signals.signal(false)
  let held : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(n) {
      n.height(Is(Some(10.0))) |> ignore
      held.val = Some(n)
    })
    // (said, and the node let go in the same change, before anything is laid out again)
    root.reacts(fn() { go.get() }, fn(now) {
      if now {
        match held.val {
          Some(n) => n.once_laid_out(fn() { done.val = done.val + 1 })
          None => ()
        }
        shown.set(false)
      }
    })
  })
  t.draw()
  go.set(true)
  t.draw()
  t.draw()
  assert_eq(done.val, 0)
}
