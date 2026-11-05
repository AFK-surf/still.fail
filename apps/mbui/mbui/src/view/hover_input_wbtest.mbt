///|
test "publishing hover during a frame does not taint the frame's later model writes" {
  for source in 0..<3 {
    let model = @signals.signal(0)
    let frame = @signals.watch(fn() { })
    let t = Tree::new(fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(100.0))).height(Is(Some(40.0)))
        .alpha(By(fn() {
          let lit = match source {
            0 => v.bar_near(20.0)
            1 => v.pointer_within()
            _ => v.pointer_here_told() is Some(_)
          }
          if lit { 1.0 } else { 0.5 }
        })) |> ignore
      }) |> ignore
    })
    frame.read(fn() {
      t.frame(300.0, 300.0, now=0.0) |> ignore
      model.set(1)
    })
    assert_eq(@signals.before_hover(fn() { model.get() }), 1)
    frame.stop()
    t.dispose()
  }
}

///|
test "a hover input can move its node away without a feedback loop or a delayed layout" {
  let now = Ref(0.0)
  let box : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    box.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(20.0)))
      .offset(By(fn() { (0.0, if v.pointer_within_on_input() { 100.0 } else { 0.0 }) }))
      .alpha(By(fn() { if v.pointer_within() { 1.0 } else { 0.5 } })) |> ignore
    }))
  }, time=fn() { now.val })
  defer { t.dispose() }
  t.frame(300.0, 300.0, now=0.0) |> ignore
  let v = box.val.unwrap()
  now.val = 10.0
  t.point_at(10.0, 10.0)
  for at in [10.0, 20.0, 100.0] {
    t.work.computes = 0
    t.frame(300.0, 300.0, now=at) |> ignore
    assert_eq(v.rect().1, 100.0, msg="the input stays true after moving out from under the pointer")
    assert_eq(t.drawn_of(v.id()).unwrap().alpha, 0.5, msg="paint follows the current position")
    assert_true(v.pointer_within_on_input())
    assert_false(v.pointer_within())
    assert_true(t.work.computes <= 1)
    assert_false(t.due || t.layout_due)
  }
  now.val = 110.0
  t.point_at(11.0, 10.0)
  t.frame(300.0, 300.0, now=110.0) |> ignore
  assert_eq(v.rect().1, 0.0, msg="the next actual move samples the moved tree once")
  assert_false(v.pointer_within_on_input())
  assert_true(v.pointer_within())
  t.point_at(-1.0, -1.0)
  assert_false(v.pointer_within_on_input())
  now.val = 120.0
  t.point_at(11.0, 10.0)
  assert_true(v.pointer_within_on_input(), msg="reentering at the same position is a new input")
}

///|
test "each wheel input samples the rows it moved beneath a stationary pointer" {
  let scroll = Scroll::new()
  let rows : Array[View] = []
  let t = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(scroll, fn(held) {
        for _ in 0..<8 {
          rows.push(held.box(fn(row) {
            row.width(Is(Some(200.0))).height(Is(Some(40.0))).on_press(fn() { }) |> ignore
            row.pointed_in_on_input() |> ignore
          }))
        }
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  defer { t.dispose() }
  t.frame(300.0, 300.0, now=0.0) |> ignore
  t.point_at(10.0, 10.0)
  assert_true(rows[0].pointed_in_on_input())
  for i in 1..<4 {
    assert_true(t.wheel_at(10.0, 10.0, 0.0, 40.0, 0, i.to_double() * 10.0))
    assert_false(rows[i - 1].pointed_in_on_input())
    assert_true(rows[i].pointed_in_on_input(), msg="wheel \{i}: no display frame needed")
  }
  assert_true(t.wheel_at(10.0, 70.0, 0.0, 40.0, 0, 40.0))
  assert_false(rows[3].pointed_in_on_input())
  assert_true(rows[4].pointed_in_on_input(), msg="a wheel routed elsewhere resamples the still pointer without moving it")
}

///|
test "release inertia preserves structural hover until its exact end with dense or missing frames" {
  for dense in [false, true] {
    let now = Ref(0.0)
    let scroll = Scroll::new()
    let port : Ref[View?] = Ref(None)
    let rows : Array[View] = []
    let t = Tree::new(fn(root) {
      port.val = Some(root.box(fn(v) {
        v.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(scroll, fn(held) {
          for _ in 0..<8 {
            rows.push(held.box(fn(row) {
              row.width(Is(Some(200.0))).height(Is(Some(40.0))).on_press(fn() { }) |> ignore
              row.pointed_in_on_input() |> ignore
            }))
          }
        }) |> ignore
      }))
    }, time=fn() { now.val })
    t.frame(300.0, 300.0, now=0.0) |> ignore
    t.point_at(10.0, 10.0)
    scroll.hand_v = 1.0
    scroll.flung(port.val.unwrap(), 0.0)
    let end = @signals.untracked(fn() { scroll.fling.get().unwrap().end_t })
    if dense {
      let mut at = 10.0
      while at < end {
        now.val = at
        t.work.computes = 0
        t.frame(300.0, 300.0, now=at) |> ignore
        assert_true(rows[0].pointed_in_on_input(), msg="inertial frames do not resample structural hover")
        assert_true(t.work.computes <= 1)
        assert_false(t.due || t.layout_due)
        at += 10.0
      }
    }
    now.val = end
    t.advance(end)
    assert_false(rows[0].pointed_in_on_input(), msg="the exact end samples once, even without a frame")
    assert_true(rows.any(fn(row) { row.pointed_in_on_input() }))
    t.dispose()
  }
}
