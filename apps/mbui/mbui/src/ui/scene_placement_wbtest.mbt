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

///|
test "the same parent and child inputs finish with the same picture and press target with or without intervening frames" {
  let pictures : Array[Array[Array[Double]]] = []
  let targets : Array[Array[String?]] = []
  let presses : Array[Array[Int]] = []
  for hz in [0, 60, 120] {
    let parent_x = @signals.signal(20.0)
    let child_y = @signals.signal(10.0)
    let pressed = Ref(0)
    let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
    set_view_app(fn(root) {
      root.box(fn(parent) {
        parent.over(Is(true)).offset(By(fn() { (parent_x.get(), 20.0) }))
          .width(Is(Some(100.0))).height(Is(Some(100.0))).ground(Is(0xDDDDDDFFL)) |> ignore
        parent.box(fn(child) {
          child.over(Is(true)).offset(Is((10.0, 0.0))).drawn_off(By(fn() { (0.0, child_y.get()) }))
            .width(Is(Some(18.0))).height(Is(Some(18.0))).ground(Is(0x1559C4FFL))
            .says(Is(Some(@view.said(Button, label="child")))).on_press(fn() { pressed.val += 1 }) |> ignore
        }) |> ignore
      }) |> ignore
    })
    t.draw()
    t.measure_as_host()
    t.clock_frame()
    t.record_host()
    let start = t.time()
    let tree = view_tree().unwrap()
    let period = if hz == 0 { 1000.0 } else { 1000.0 / hz.to_double() }
    let mut next = 1
    for (ms, y) in [(13.0, 20.0), (29.0, 30.0), (47.0, 40.0), (82.0, -1.0)] {
      while next.to_double() * period < ms {
        t.frame_at(start + next.to_double() * period)
        next += 1
      }
      t.advance(start + ms - t.time())
      tree.event(start + ms, fn() { if y < 0.0 { parent_x.set(40.0) } else { child_y.set(y) } })
    }
    while next.to_double() * period < 100.0 {
      t.frame_at(start + next.to_double() * period)
      next += 1
    }
    t.frame_at(start + 100.0)
    let frames = t.host_frames().map(fn(f) { f.at })
    println("placement schedule \{hz} Hz (0: direct): actual frames \{frames}, child \{placement_child_rect()}")
    assert_eq(placement_child_rect(), (50.0, 60.0))
    pictures.push(t.drawn_instances())
    // Compare the visual and layout positions across histories without requiring either hit policy.
    // The child must actually be found and pressed; an empty result in every history is not enough.
    let found = [t.press_target_at(59.0, 69.0).map(fn(s) { s.label }), t.press_target_at(59.0, 29.0).map(fn(s) { s.label })]
    assert_true(found[0] == Some("child") || found[1] == Some("child"))
    targets.push(found)
    let called : Array[Int] = []
    for (y, ms) in [(69.0, 101.0), (29.0, 103.0)] {
      let before = pressed.val
      t.touch_at(0, 59.0, y, start + ms)
      t.touch_at(2, 59.0, y, start + ms + 1.0)
      called.push(pressed.val - before)
    }
    assert_true(pressed.val > 0, msg="a real press reaches the child")
    presses.push(called)
    println("placement hits \{hz} Hz: visual/layout targets \{found}, callbacks \{called}")
  }
  assert_eq(pictures[0], pictures[1], msg="direct and 60 Hz")
  assert_eq(pictures[0], pictures[2], msg="direct and 120 Hz")
  assert_eq(targets[0], targets[1], msg="direct and 60 Hz targets")
  assert_eq(targets[0], targets[2], msg="direct and 120 Hz targets")
  assert_eq(presses[0], presses[1], msg="direct and 60 Hz presses")
  assert_eq(presses[0], presses[2], msg="direct and 120 Hz presses")
}

///|
test "a removed child layer is replaced at its new position before its parent is replayed" {
  let shown = @signals.signal(true)
  let parent_x = @signals.signal(20.0)
  let child_y = @signals.signal(10.0)
  let child_view : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(parent) {
      parent.over(Is(true)).offset(By(fn() { (parent_x.get(), 20.0) }))
        .width(Is(Some(150.0))).height(Is(Some(150.0))).ground(Is(0xDDDDDDFFL)) |> ignore
      parent.show(fn() { shown.get() }, fn(child) {
        child_view.val = Some(child)
        child.over(Is(true)).offset(Is((10.0, 0.0))).drawn_off(By(fn() { (0.0, child_y.get()) }))
          .width(Is(Some(18.0))).height(Is(Some(18.0))).ground(Is(0x1559C4FFL))
          .says(Is(Some(@view.said(Button, label="child")))).on_press(fn() { }) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  t.clock_frame()
  child_y.set(40.0)
  t.clock_frame()
  parent_x.set(40.0)
  t.clock_frame()
  let old = child_view.val.unwrap().id()
  assert_eq(placement_child_rect(), (50.0, 60.0))
  shown.set(false)
  t.clock_frame()
  assert_false(scene.layers.contains(old), msg="the removed layer really left the scene")
  child_y.set(60.0)
  shown.set(true)
  t.clock_frame()
  let fresh = child_view.val.unwrap().id()
  assert_true(fresh.at == old.at && fresh.gen != old.gen, msg="the node slot was reused with a new identity")
  assert_eq(placement_child_rect(), (50.0, 80.0))
  parent_x.set(70.0)
  t.clock_frame()
  assert_eq(placement_child_rect(), (80.0, 80.0))
  assert_true(t.press_target_at(89.0, 89.0).map(fn(s) { s.label }) == Some("child") ||
    t.press_target_at(89.0, 29.0).map(fn(s) { s.label }) == Some("child"))
  child_y.set(65.0)
  t.clock_frame()
  parent_x.set(90.0)
  t.clock_frame()
  assert_eq(placement_child_rect(), (100.0, 85.0))
  let kept = t.drawn_instances()
  t.check_looks(true)
  g().scene_check(-1)
  assert_eq(t.drawn_instances(), kept)
}

///|
test "a child layer left out of its row and drawn again keeps its current position when the parent replays" {
  let width = @signals.signal(40.0)
  let parent_x = @signals.signal(20.0)
  let child_y = @signals.signal(10.0)
  let child_view : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(parent) {
      parent.over(Is(true)).row(Is(true)).fits(Is(true)).offset(By(fn() { (parent_x.get(), 20.0) }))
        .width(By(fn() { Some(width.get()) })).height(Is(Some(100.0))).ground(Is(0xDDDDDDFFL)) |> ignore
      parent.box(fn(filler) { filler.width(Is(Some(20.0))).height(Is(Some(18.0))) |> ignore }) |> ignore
      parent.box(fn(child) {
        child_view.val = Some(child)
        child.drops(Is(1)).drawn_off(By(fn() { (0.0, child_y.get()) }))
          .width(Is(Some(18.0))).height(Is(Some(18.0))).ground(Is(0x1559C4FFL))
          .says(Is(Some(@view.said(Button, label="child")))).on_press(fn() { }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  t.clock_frame()
  child_y.set(40.0)
  t.clock_frame()
  parent_x.set(40.0)
  t.clock_frame()
  let id = child_view.val.unwrap().id()
  assert_eq(placement_child_rect(), (60.0, 60.0))
  width.set(20.0)
  t.clock_frame()
  assert_true(child_view.val.unwrap().owed_left_out())
  // A tree-only frame can keep an unseen layer's recording. A real window resize paints the old frame too,
  // so scene_end discards layers no longer seen; the live node will later acquire a fresh layer with revision zero.
  t.resize(401.0, 300.0)
  assert_false(scene.layers.contains(id), msg="the live node's unseen layer was discarded at scene_end")
  child_y.set(60.0)
  width.set(40.0)
  t.clock_frame()
  assert_true(scene.layers.contains(id), msg="the same node has a newly recorded layer")
  assert_eq(placement_child_rect(), (60.0, 80.0))
  parent_x.set(70.0)
  t.clock_frame()
  assert_eq(placement_child_rect(), (90.0, 80.0))
  assert_true(t.press_target_at(99.0, 89.0).map(fn(s) { s.label }) == Some("child") ||
    t.press_target_at(99.0, 29.0).map(fn(s) { s.label }) == Some("child"))
  let kept = t.drawn_instances()
  t.check_looks(true)
  g().scene_check(-1)
  assert_eq(t.drawn_instances(), kept)
}
