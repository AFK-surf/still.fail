///|
test "a visible row changing height does not rebuild historical row positions" {
  for count in [30, 3000] {
    let size = @signals.signal(40.0, same=fn(a, b) { a == b })
    let keys = Array::makei(count, fn(i) { i })
    let scroll = Scroll::list()
    let tree = Tree::new(fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        v.scrolls_window(scroll, fn() { keys }, est=40.0, from_end=true,
          kept_keys=fn() { [] }, fn(row, key) {
            row.height(By(fn() { Some(if key == count - 1 { size.get() } else { 40.0 }) })) |> ignore
          }) |> ignore
      }) |> ignore
    })
    defer { tree.dispose() }
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    let before = tree.work()
    size.set(80.0)
    tree.frame(390.0, 844.0, now=100.0) |> ignore
    assert_eq(scroll.at(tree), count.to_double() * 40.0 + 40.0 - 100.0)
    assert_eq(tree.work().list_rows - before.list_rows, 1)
  }
}
