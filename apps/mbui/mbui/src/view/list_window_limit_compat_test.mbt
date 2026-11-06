// An unrelated natural-sized child must see the same room when no window opts into natural sizing.

///|
test "an unrelated Roomed child in a capped column inside a scroll keeps its unbounded room" {
  let child : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.height(Is(Some(300.0))).scrolls(@view.Scroll::new(), fn(held) {
      held.box(fn(body) {
        body.max_height(Is(Some(120.0))) |> ignore
        body.box(fn(header) { header.height(Is(Some(20.0))) |> ignore }) |> ignore
        body.box(fn(holder) {
          child.val = Some(holder.box(fn(v) {
            v.height(Roomed(holder, fn(_, h) { Some(if h == h { h / 2.0 } else { 40.0 }) })) |> ignore
          }))
        }) |> ignore
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(child.val.unwrap().rect().3, 20.0)
  tree.dispose()
}
