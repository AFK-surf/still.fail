// Card limits are constraints of this layout, never a publication of the preceding layout's width.

///|
test "a card's minimum and maximum follow its current content and available width in one layout" {
  let wanted = @signals.signal(200.0, same=fn(a, b) { a == b })
  let card : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.padding(Is((20.0, 0.0, 20.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
    card.val = Some(root.box(fn(c) {
      c.min_width(Is(Some(360.0)), within=true).max_width(Is(Some(560.0)), within=true)
      .measured(By(fn() { wanted.get() }), fn(wanted, width) {
        (dmin(wanted, width.unwrap_or(wanted)), 40.0)
      }) |> ignore
    }))
  })
  for (width, content, expected) in [(800.0, 200.0, 360.0), (800.0, 480.0, 480.0),
    (800.0, 800.0, 560.0), (340.0, 800.0, 300.0), (800.0, 200.0, 360.0)] {
    wanted.set(content)
    let before = t.work.computes
    t.frame(width, 300.0) |> ignore
    assert_eq(t.nodes[card.val.unwrap().at].lw, expected)
    assert_eq(t.work.computes - before, 1, msg="the first layout already has the final card width")
  }
  t.dispose()
}
