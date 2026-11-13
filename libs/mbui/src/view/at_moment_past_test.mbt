// A moment asked for (View::at_moment) that is gone by as it is asked is done at the moment it is asked, its cause's
// moment that one: time never goes back for what is committed with it. One between two frames is done at its own.

///|
test "at_moment: a moment gone by as it is asked (a way at its end as its node is made: 0) is done at the moment it was asked, what reacts to it with it as of then" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let fired = @signals.signal(0, same=fn(a, b) { a == b })
  let seen : Array[Double] = []
  let tree = @view.Tree::new(fn(root) {
    // (made by the change at 500, asking for 0: a way that never set out, its end 0)
    root.show(at_once=true, fn() { on.get() }, fn(v) {
      v.at_moment(0.0, fn() { fired.set(fired.untracked() + 1) }) |> ignore
    })
    root.reacts(fn() { fired.get() }, fn(_) { seen.push(root.cause_at()) }, at_start=false)
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.at(500.0)
  tree.frame(390.0, 844.0, now=500.0) |> ignore
  tree.event(500.0, fn() { on.set(true) })
  tree.at(516.0)
  tree.frame(390.0, 844.0, now=516.0) |> ignore
  assert_eq(seen, [500.0])
}

///|
test "at_moment: a moment between two frames, asked before it, is still done at its own moment" {
  let fired = @signals.signal(0, same=fn(a, b) { a == b })
  let seen : Array[Double] = []
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    node.val = Some(root)
    root.reacts(fn() { fired.get() }, fn(_) { seen.push(root.cause_at()) }, at_start=false)
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() {
    node.val.unwrap().at_moment(95.0, fn() { fired.set(fired.untracked() + 1) }) |> ignore
  })
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq(seen, [95.0])
}
