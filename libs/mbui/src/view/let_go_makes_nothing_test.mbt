// A tree let go makes nothing more (Tree::dispose): what the going of its nodes writes tells the structures of those
// not let go yet, which change nothing then. One that did made what a node already gone held, never let go, its
// bindings told on by what outlives the tree and read against nodes that are no more (a list's row made as its
// window's tree went: the next test's first change of the app's state stopped the program, 2026-11-13).

///|
test "a tree let go: a structure told by a node's going makes nothing more in it" {
  let shown = @signals.signal(false)
  let made = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(holder) {
      // (let go before the structure beside it: its going writes what that one reads)
      holder.box(fn(a) { a.owns(fn() { shown.set(true) }) |> ignore }) |> ignore
      holder.show(at_once=true, fn() { shown.get() }, fn(_) { made.val += 1 })
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(made.val, 0)
  t.dispose()
  assert_eq(made.val, 0)
  // (nor told on after: what outlives the tree changes, nothing of it made)
  shown.set(false)
  shown.set(true)
  assert_eq(made.val, 0)
}
