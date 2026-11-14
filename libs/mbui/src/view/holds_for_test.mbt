// View::holds_for: what holds from each event till a declared length after it, its end set again in place by the next,
// told as it starts and ends only, let go with its node.

///|
test "holds_for: from an event till ms after it, a second mid-way ending it ms after that one; told at its start and end alone" {
  let held : Ref[(() -> Unit, () -> Bool)?] = Ref(None)
  let seen : Array[Bool] = []
  let tree = @view.Tree::new(fn(root) {
    let (event, on) = root.holds_for(100.0)
    held.val = Some((event, on))
    root.reacts(on, fn(b) { seen.push(b) })
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let (event, on) = held.val.unwrap()
  assert_false(on())
  assert_eq(tree.wake(), None)
  // the event at 10: holds from it, its end at 110
  tree.event(10.0, fn() { event() })
  assert_true(on())
  assert_eq(tree.wake(), Some(110.0))
  assert_false(tree.clock_read(), msg="the clock not followed while it holds")
  // again at 60: its end at 160, the one at 110 off the timeline
  tree.frame(400.0, 800.0, now=60.0) |> ignore
  assert_true(on())
  tree.event(60.0, fn() { event() })
  assert_eq(tree.wake(), Some(160.0))
  assert_eq(tree.due_count(), 1)
  tree.frame(400.0, 800.0, now=110.0) |> ignore
  assert_true(on(), msg="not ended at the first event and its ms")
  tree.frame(400.0, 800.0, now=160.0) |> ignore
  assert_false(on(), msg="ended at the second and its ms")
  // idle afterwards: nothing due, the clock not followed
  assert_eq(tree.wake(), None)
  assert_eq(tree.due_count(), 0)
  assert_false(tree.clock_read())
  // told as it started and as it ended alone (the first as it was made)
  assert_eq(seen, [false, true, false])
  // after it ended, an event holds again from its own moment
  tree.event(200.0, fn() { event() })
  assert_true(on())
  assert_eq(tree.wake(), Some(300.0))
}

///|
test "holds_for: its node let go takes its end off the timeline" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let held : Ref[(() -> Unit, () -> Bool)?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(at_once=true, fn() { there.get() }, fn(v) { held.val = Some(v.holds_for(100.0)) })
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let (event, _) = held.val.unwrap()
  tree.event(10.0, fn() { event() })
  assert_eq(tree.wake(), Some(110.0))
  tree.event(20.0, fn() { there.set(false) })
  assert_eq(tree.wake(), None)
  assert_eq(tree.due_count(), 0)
  // told after it is let go: nothing due
  tree.event(30.0, fn() { event() })
  assert_eq(tree.wake(), None)
}
