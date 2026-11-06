///|
test "a node leaves for the duration its size says at the closing event, with no frame in between" {
  let open = @signals.signal(true)
  let tall = @signals.signal(120.0)
  let card : Ref[@view.View?] = Ref(None)
  let gone = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { open.get() }, leave_by=fn(v) { v.laid_size().1 }, fn(v) {
      card.val = Some(v)
      v.height(By(fn() { Some(tall.get()) })) |> ignore
      v.owns(fn() { gone.val += 1 }) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { tall.set(200.0) })
  tree.event(20.0, fn() { open.set(false) })
  assert_eq(card.val.unwrap().leaves_at(), 220.0)
  let end = 300.0
  let progress = Ref((0.0, 0.0))
  tree.event(100.0, fn() {
    let before = card.val.unwrap().going()
    card.val.unwrap().leaves_no_earlier_than(end) |> ignore
    progress.val = (before, card.val.unwrap().going())
  })
  assert_eq(progress.val.0, progress.val.1)
  tree.advance(end - 1.0)
  assert_eq(gone.val, 0)
  tree.advance(end)
  assert_eq(gone.val, 1)
}
