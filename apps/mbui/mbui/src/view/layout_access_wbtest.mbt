///|
test "panic a custom layout cannot read a signal outside its captured content" {
  let offset = @signals.signal(20.0)
  let t = Tree::new(fn(root) {
    root.layout_box(Is(0), fn(_, _) { offset.get() |> ignore }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}

///|
test "panic a custom layout cannot write an unobserved signal" {
  let offset = @signals.signal(20.0)
  let t = Tree::new(fn(root) {
    root.layout_box(Is(0), fn(_, _) { offset.set(30.0) }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}

