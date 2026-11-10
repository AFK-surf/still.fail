// One laid out over what holds it (View::over) laid out nowhere (View::laid_nowhere), then in again: drawn again, it
// and what it holds, as one in its turn is.

///|
/// A layer over all of it holding a box (己) that is laid out nowhere as `nowhere` says, over what holds it as `over`
/// says, holding a box (提).
fn nowhere_over_tree(nowhere : @signals.Signal[Bool], over : Bool) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.box(fn(l) {
      l.over(Is(true)) |> ignore
      l.box(fn(h) {
        h.over(Is(over)).laid_nowhere(By(fn() { nowhere.get() })).words(Is("己")) |> ignore
        h.box(fn(k) { k.height(Is(Some(20.0))).width(Is(Some(30.0))).words(Is("提")) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
fn nowhere_drawn(t : @view.Tree) -> (Bool, Bool) {
  let d = t.drawn()
  (d.iter().any(fn(x) { x.words == "己" }), d.iter().any(fn(x) { x.words == "提" }))
}

///|
test "laid out nowhere and in again, over what holds it or in its turn: drawn again, it and what it holds" {
  for over in [true, false] {
    let nowhere = @signals.signal(false, same=fn(a, b) { a == b })
    let t = nowhere_over_tree(nowhere, over)
    t.frame(390.0, 844.0, now=0.0) |> ignore
    assert_eq(nowhere_drawn(t), (true, true), msg="drawn (over \{over})")
    nowhere.set(true)
    t.frame(390.0, 844.0, now=16.0) |> ignore
    assert_eq(nowhere_drawn(t), (false, false), msg="nowhere (over \{over})")
    nowhere.set(false)
    t.frame(390.0, 844.0, now=32.0) |> ignore
    assert_eq(nowhere_drawn(t), (true, true), msg="in again (over \{over})")
  }
}
