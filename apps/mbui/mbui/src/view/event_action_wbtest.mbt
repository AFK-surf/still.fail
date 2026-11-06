///|
fn nested_before_removal_event(after : Bool) -> Unit {
  let shown = @signals.signal(true)
  let host : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    host.val = Some(root)
    let victim = root.box(fn(v) {
      v.height(Is(Some(30.0))) |> ignore
      v.before_removed(fn() {
        if after {
          root.after_event_action(fn() { v.laid_size() |> ignore })
        } else {
          root.event_action(fn() { v.laid_size() |> ignore })
        }
      }) |> ignore
    })
    root.box(fn(parent) {
      parent.height(Is(Some(20.0))).layout_box(By(fn() { shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("owner", fn(v) { v.owns(fn() { root.drop(victim) }) |> ignore })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  tree.event(10.0, fn() { shown.set(false); host.val.unwrap().laid_size() |> ignore })
}

///|
test "panic a nested before-removal callback cannot take geometry through an owner cleanup" {
  nested_before_removal_event(false)
}

///|
test "panic a nested before-removal callback cannot defer geometry through an owner cleanup" {
  nested_before_removal_event(true)
}
