///|
test "parent allocation observes content changes without publishing geometry" {
  let rows = @signals.signal(2, same=fn(a, b) { a == b })
  let body_at : Ref[View?] = Ref(None)
  let foot_at : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let body = root.box(fn(_) { })
    let foot = root.box(fn(f) { f.height(By(fn() { Some(rows.get().to_double() * 20.0) })) |> ignore })
    body_at.val = Some(body)
    foot_at.val = Some(foot)
    root.layout(Is(()), fn(_, room) {
      let w = room.width().unwrap()
      let h = room.height().unwrap()
      let f = room.measure(foot, width=w)
      let b = room.measure(body, width=w, height=h - f.size().1)
      arrangement(w, h, [b.at(0.0, 0.0), f.at(0.0, b.size().1)])
    }) |> ignore
  })
  defer { tree.dispose() }
  for count in [2, 6, 1] {
    rows.set(count)
    tree.frame(300.0, 600.0, now=1000.0) |> ignore
    assert_eq(foot_at.val.unwrap().laid_size().1, count.to_double() * 20.0)
    assert_eq(body_at.val.unwrap().laid_size().1, 600.0 - count.to_double() * 20.0)
    assert_true(tree.sized.is_empty())
  }
}
