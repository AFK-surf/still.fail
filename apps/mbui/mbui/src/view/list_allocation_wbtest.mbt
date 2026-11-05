///|
test "a short end-aligned list receives a resized viewport in one parent layout" {
  let height = @signals.signal(100.0)
  let last : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(240.0))).height(By(fn() { Some(height.get()) })) |> ignore
      v.scrolls_window(Scroll::list(), fn() { [0, 1] }, est=20.0, from_end=true, fn(row, key) {
        row.height(Is(Some(20.0))) |> ignore
        if key == 1 { last.val = Some(row) }
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(300.0, 400.0, now=0.0) |> ignore
  for h in [200.0, 80.0, 160.0] {
    height.set(h)
    tree.work.computes = 0
    tree.frame(300.0, 400.0, now=0.0) |> ignore
    let (_, y, _, rh) = last.val.unwrap().rect()
    assert_eq(y + rh, h)
    assert_eq(tree.work.computes, 1,
      msg="the list's minimum content height must come from the current parent constraint")
  }
}
