///|
test "a 60 Hz cycle follows the frame clock, releases its request while parked and resumes when taken back" {
  let holder : Ref[View?] = Ref(None)
  let child : Ref[View?] = Ref(None)
  let hidden = @signals.signal(false)
  let t = Tree::new(fn(root) {
    holder.val = Some(root)
    root.box(fn(v) {
      child.val = Some(v)
      v.width(Is(Some(10.0))).height(Is(Some(10.0))).laid_nowhere(By(fn() { hidden.get() }))
      .alpha(By(fn() { v.cycle(1000.0, at_least_60=true) })) |> ignore
    }) |> ignore
  })
  t.frame(100.0, 100.0, now=250.0) |> ignore
  assert_true(t.cycle_read() && t.cycle_wants_60())
  assert_eq(t.drawn_of(child.val.unwrap().id()).unwrap().alpha, 0.25)
  hidden.set(true)
  t.frame(100.0, 100.0, now=260.0) |> ignore
  assert_false(t.cycle_wants_60(), msg="a cycle laid nowhere does not request the higher rate")
  hidden.set(false)
  t.frame(100.0, 100.0, now=270.0) |> ignore
  assert_true(t.cycle_wants_60(), msg="shown again")
  let wake : Ref[() -> Unit] = Ref(fn() {  })
  t.event(300.0, fn() { wake.val = holder.val.unwrap().park(child.val.unwrap()) })
  t.frame(100.0, 100.0, now=300.0) |> ignore
  assert_false(t.cycle_wants_60(), msg="a parked cycle no longer requests the higher rate")
  t.event(1750.0, fn() {
    holder.val.unwrap().take_in(child.val.unwrap())
    (wake.val)()
  })
  t.frame(100.0, 100.0, now=1750.0) |> ignore
  assert_true(t.cycle_read() && t.cycle_wants_60())
  assert_eq(t.drawn_of(child.val.unwrap().id()).unwrap().alpha, 0.75)
}

///|
test "a stopped cycle does not request the higher rate" {
  let period = @signals.signal(0.0)
  let t = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(10.0))).height(Is(Some(10.0))).alpha(By(fn() { v.cycle(period.get(), at_least_60=true) })) |> ignore
    }) |> ignore
  })
  t.frame(100.0, 100.0, now=100.0) |> ignore
  assert_false(t.cycle_wants_60())
  period.set(1000.0)
  t.frame(100.0, 100.0, now=200.0) |> ignore
  assert_true(t.cycle_wants_60())
  period.set(0.0)
  t.frame(100.0, 100.0, now=300.0) |> ignore
  assert_false(t.cycle_wants_60())
}
