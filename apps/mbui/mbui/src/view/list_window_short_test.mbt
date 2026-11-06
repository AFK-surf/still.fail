// A virtual list's content may end above its viewport even though its holder fills that viewport.

///|
test "a windowed list reports short, exact and overflowing content" {
  let keys = @signals.signal([0, 1], same=fn(a, b) { a == b })
  let height = @signals.signal(40.0, same=fn(a, b) { a == b })
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    list.val = Some(root.box(fn(v) {
      v.height(Is(Some(100.0))).scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0,
        from_end=true, align_end=false, fn(row, _) {
          row.height(By(fn() { Some(height.get()) })) |> ignore
        }) |> ignore
    }))
  }, time=fn() { 0.0 })
  tree.frame(200.0, 200.0) |> ignore
  let id = list.val.unwrap().id()
  assert_true(tree.scroll_short(id))
  assert_false(tree.scrolls_now(id))
  height.set(50.0)
  tree.frame(200.0, 200.0) |> ignore
  assert_false(tree.scroll_short(id))
  assert_false(tree.scrolls_now(id))
  keys.set([0, 1, 2])
  tree.frame(200.0, 200.0) |> ignore
  assert_false(tree.scroll_short(id))
  assert_true(tree.scrolls_now(id))
  tree.dispose()
}

///|
test "short content of an ordinary vertical scroll is still measured by its holder" {
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    list.val = Some(root.box(fn(v) {
      v.height(Is(Some(100.0))).scrolls(@view.Scroll::new(), fn(held) {
        held.box(fn(row) { row.height(Is(Some(80.0))) |> ignore }) |> ignore
      }) |> ignore
    }))
  }, time=fn() { 0.0 })
  tree.frame(200.0, 200.0) |> ignore
  assert_true(tree.scroll_short(list.val.unwrap().id()))
  tree.dispose()
}
