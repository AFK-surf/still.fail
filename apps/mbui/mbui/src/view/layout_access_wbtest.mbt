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

///|
test "panic measuring a child does not permit its parent to read uncaptured inputs afterwards" {
  let offset = @signals.signal(20.0)
  let t = Tree::new(fn(root) {
    let child = root.box(fn(n) { n.height(Is(Some(20.0))) |> ignore })
    root.layout_box(Is(0), fn(l, _) {
      l.measure(child, l.width) |> ignore
      l.place(child, 0.0, offset.get())
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}
