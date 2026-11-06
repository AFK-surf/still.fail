///|
test "a room callback can remove a sibling during a keyed removal's immediate layout" {
  let items = @signals.signal([1, 2, 3, 4])
  let slot : Ref[View?] = Ref(None)
  let third : Ref[View?] = Ref(None)
  let last : Ref[View?] = Ref(None)
  let armed = Ref(false)
  let fired = Ref(false)
  let seen = Ref(-1.0)
  let tree = Tree::new(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
      row.each(fn() { items.get() }, fn(k) { k }, fn(v, item) {
        let k = item.get()
        slot.val = v.parent()
        if k == 3 { third.val = Some(v) }
        if k == 4 {
          last.val = Some(v)
          v.width(Roomed(row, fn(_, _) {
            if armed.val {
              armed.val = false
              fired.val = true
              slot.val.unwrap().drop(third.val.unwrap())
            }
            Some(20.0)
          })) |> ignore
        } else {
          v.width(Is(Some(20.0))) |> ignore
        }
        v.height(Is(Some(20.0))).owns(fn() {
          if k == 2 {
            armed.val = true
            seen.val = last.val.unwrap().laid_window_now().0
          }
        }) |> ignore
      })
    }) |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.event(1.0, fn() { items.set([3, 4]) })
  assert_true(fired.val)
  assert_eq(seen.val, 20.0)
  tree.dispose()
}
