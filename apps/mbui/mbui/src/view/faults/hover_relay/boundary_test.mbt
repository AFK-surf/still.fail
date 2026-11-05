///|
test "panic relaying hover through model state cannot hide it from a layout binding" {
  let tree = @view.Tree::new(fn(root) {
    let hovered = @signals.signal(false, same=fn(a, b) { a == b })
    root.reacts(fn() { root.pointer_within() }, fn(on) { hovered.set(on) })
    root.width(By(fn() { Some(if hovered.get() { 80.0 } else { 100.0 }) })) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
