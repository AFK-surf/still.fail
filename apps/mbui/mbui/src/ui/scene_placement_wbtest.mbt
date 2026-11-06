// A child drawn alone has a new position even though the entry in its parent's recording has not been visited.

///|
fn placement_child_rect() -> (Double, Double) raise {
  let c = g()
  let found : Array[(Double, Double)] = []
  for k in 0..<c.ninst {
    let at = k * inst_size
    if c.inst[at + 2] == 18.0 && c.inst[at + 3] == 18.0 {
      found.push((c.inst[at], c.inst[at + 1]))
    }
  }
  assert_eq(found.length(), 1)
  found[0]
}

///|
fn placement_after_child_moves(moves : Array[Double], name : String) -> Unit raise {
  let parent_x = @signals.signal(20.0)
  let child_y = @signals.signal(10.0)
  let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(parent) {
      parent.over(Is(true)).offset(By(fn() { (parent_x.get(), 20.0) }))
        .width(Is(Some(100.0))).height(Is(Some(100.0))).ground(Is(0xDDDDDDFFL)) |> ignore
      parent.box(fn(child) {
        child.over(Is(true)).offset(Is((10.0, 0.0))).drawn_off(By(fn() { (0.0, child_y.get()) }))
          .width(Is(Some(18.0))).height(Is(Some(18.0))).ground(Is(0x1559C4FFL)) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(placement_child_rect(), (30.0, 30.0))
  t.measure_as_host()
  // Do not let the check's full walk refresh the parent's recording between these real frames. The paint
  // following the initial build comes before either placement input (looks_base.settled).
  t.clock_frame()
  t.record_host()
  let frames : Array[Double] = []
  let mut before = (30.0, 30.0)
  for y in moves {
    child_y.set(y)
    t.clock_frame()
    let drawn = t.host_frames()
    assert_eq(drawn.length(), 1)
    let frame = drawn[0]
    frames.push(frame.at)
    assert_true(frame.tree_alone, msg="the child moves without the old frame painting its parent: \{frame}")
    let after = placement_child_rect()
    assert_eq(after, (30.0, 20.0 + y))
    assert_true(paint_damage_covers(frame, (before.0, before.1, before.0 + 18.0, before.1 + 18.0)))
    assert_true(paint_damage_covers(frame, (after.0, after.1, after.0 + 18.0, after.1 + 18.0)))
    before = after
  }
  paint_damage_print(t, "\{name}-before")
  parent_x.set(40.0)
  t.clock_frame()
  paint_damage_print(t, "\{name}-after")
  let drawn = t.host_frames()
  assert_eq(drawn.length(), 1)
  let frame = drawn[0]
  frames.push(frame.at)
  assert_true(frame.tree_alone, msg="the parent is replayed where it moved: \{frame}")
  assert_true(paint_damage_covers(frame, (20.0, 20.0, 120.0, 120.0)))
  assert_true(paint_damage_covers(frame, (40.0, 20.0, 140.0, 120.0)))
  println("placement \{name}: actual frames \{frames}, child \{placement_child_rect()}")
  assert_eq(placement_child_rect(), (50.0, before.1))
  let kept = t.drawn_instances_keyed()
  t.check_looks(true)
  g().scene_check(-1)
  assert_eq(t.drawn_instances_keyed(), kept, msg="the kept parent agrees with a fresh walk")
}

///|
test "a child moved alone stays where it moved when its parent's recording is replayed later" {
  placement_after_child_moves([10.5], "placement-half")
}

///|
test "several child-only frames retain the latest position when their parent is replayed" {
  placement_after_child_moves([20.0, 30.0, 40.0], "placement-many")
}
