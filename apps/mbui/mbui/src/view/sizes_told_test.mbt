// Sizes followed (View::laid_size_told) of nodes made as another's size is told: asked as they are made, told as they
// are laid out, as any other's.

///|
test "a size published inside an input batch finishes its dependent binding before hover is notified" {
  let width = @signals.signal(100.0)
  let follower : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    let source = root.box(fn(n) {
      n.width(By(fn() { Some(width.get()) })).height(Is(Some(10.0))) |> ignore
    })
    follower.val = Some(root.box(fn(n) {
      n.width(By(fn() { source.laid_size_told().map(fn(size) { size.0 }) }))
      .height(Is(Some(20.0))) |> ignore
    }))
  })
  defer { tree.dispose() }
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  @signals.start_batch()
  defer { @signals.end_batch() }
  width.set(200.0)
  tree.bring_to(10.0)
  assert_eq(follower.val.unwrap().rect(), (0.0, 10.0, 200.0, 20.0))
  assert_false(tree.layout_pending())
}

///|
test "laid_size_told: a node made as another's size is told, its own size asked as it is made: told once it is laid out" {
  let wide = @signals.signal(100.0, same=fn(a, b) { a == b })
  let told : Ref[(Double, Double)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        let a = o.box(fn(a) { a.width(By(fn() { Some(wide.get()) })).height(Is(Some(10.0))) |> ignore })
        // (made as A is told wider than 150, reading its own size as it is made)
        o.show(fn() { a.laid_size_told().map(fn(z) { z.0 }).unwrap_or(0.0) > 150.0 }, fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(20.0))) |> ignore
          b.reacts(fn() { b.laid_size_told() }, fn(z) { told.val = z })
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  wide.set(200.0)
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(told.val, Some((40.0, 20.0)))
}
