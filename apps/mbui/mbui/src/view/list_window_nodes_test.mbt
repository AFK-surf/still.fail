// A long column held by its blocks in sight (View::scrolls_window): the tree as big as what shows, not as all it holds;
// a block kept far from those in sight (a send's landing while the list glides to it) one more slot, not every block
// between it and them.

///|
test "scrolls_window: a long column's tree is as big as what shows; one kept far from it adds itself, not what is between" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(2000, fn(i) { i }), same=fn(a, b) { a == b })
  let kept = @signals.signal(-1)
  let live : Map[Int, Bool] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end=true, kept=fn(k) { kept.get() == k }, fn(b, k) {
        live[k] = true
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  let at_end = tree.alive()
  assert_true(at_end < 60, msg="nodes at its end: \{at_end}")
  assert_true(live.contains(1999), msg="its last block made")
  assert_false(live.contains(0))
  kept.set(5)
  tree.frame(390.0, 844.0) |> ignore
  assert_true(live.contains(5), msg="the block kept made")
  let with_kept = tree.alive()
  assert_true(with_kept - at_end < 8, msg="nodes with one kept far off: \{with_kept}, at its end \{at_end}")
  kept.set(-1)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(live.contains(5), msg="let go once not kept")
}

///|
test "scrolls_window: a block's row known by one name as its slot is made anew; its key gone and come again, another" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(200, fn(i) { i }), same=fn(a, b) { a == b })
  let views : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end=true, fn(b, k) {
        views[k] = b
        b.owns(fn() { views.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  let first = views[199].row_place().0
  let made_in = views[199].id()
  // (its slot let go as it leaves the window and made anew as it comes back: the same name, found as the row now)
  keys.set(Array::makei(199, fn(i) { i }))
  tree.frame(390.0, 844.0) |> ignore
  assert_false(views.contains(199))
  assert_true(tree.view_of(first) is None, msg="no row while its key is gone")
  assert_true(tree.view_of(made_in) is None, msg="the node it was made in not alive again")
  keys.set(Array::makei(200, fn(i) { i }))
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_true(views.contains(199))
  let again = views[199].row_place().0
  assert_true(again != first, msg="its key gone and come again: another row")
  assert_true(tree.view_of(again) is Some(_))
}
