// Sizes followed (View::laid_size_told) of nodes made as another's size is told: asked as they are made, told as they
// are laid out, as any other's.

///|
test "laid_size_told: a node made as another's size is told, its own size asked as it is made: told once it is laid out" {
  let wide = @signals.signal(100.0, same=fn(a, b) { a == b })
  let told : Ref[(Double, Double)?] = Ref(None)
  let tree = Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        let a = o.box(fn(a) { a.width(By(fn() { Some(wide.get()) })).height(Is(Some(10.0))) |> ignore })
        // (made as A is told wider than 150, reading its own size as it is made)
        o.show(at_once=true, fn() { a.laid_size_told().map(fn(z) { z.0 }).unwrap_or(0.0) > 150.0 }, fn(b) {
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
