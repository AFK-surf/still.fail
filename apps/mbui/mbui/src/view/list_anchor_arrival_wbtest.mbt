// A fresh row's following decision depends on the tail in the viewport, not on an estimate of all history.

///|
test "a tall measured row outside the window does not stop following a short arrival near the end" {
  for old_height in [40.0, 800.0] {
    let keys = @signals.signal(Array::makei(100, fn(i) { i }))
    let follows = @signals.signal(true)
    let scroll = Scroll::list()
    let visible : Map[Int, View] = {}
    let tree = Tree::new(fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(300.0))).height(Is(Some(100.0)))
        .scrolls_anchored(
          scroll,
          fn() { keys.get() },
          follows~,
          fresh=fn(k) { k == 100 },
          kept_keys=fn() { [0] },
          fn(row, k) {
            visible[k] = row
            let height = if k == 0 { old_height } else if k == 100 { 20.0 } else { 40.0 }
            row.owns(fn() { visible.remove(k) }).height(Is(Some(height))) |> ignore
          },
        )
        |> ignore
      }) |> ignore
    })
    tree.frame(300.0, 100.0, now=0.0) |> ignore
    // The new row is inserted before the last row, as an answer before its local activity tail.
    keys.set(Array::makei(99, fn(i) { i }) + [100, 99])
    tree.frame(300.0, 100.0, now=10.0) |> ignore
    assert_true(follows.get(), msg="off-screen row height \{old_height} must not change the following decision")
    tree.frame(300.0, 100.0, now=2000.0) |> ignore
    assert_true(follows.get())
    assert_eq(visible[99].rect().1 + visible[99].rect().3, 100.0)
    tree.dispose()
  }
}
