///|
test "a host's predicted frame leaves a later touch able to cancel its deadline at any frame cadence" {
  let pictures : Array[Array[Array[Double]]] = []
  let outcomes : Array[(Array[(String, Double)], Array[Double])] = []
  for hz in [0, 60, 120] {
    let page : Ref[@view.View?] = Ref(None)
    let cancel : Ref[() -> Unit] = Ref(fn() { })
    let epoch = Ref(0.0)
    let fired : Array[(String, Double)] = []
    let pressed : Array[Double] = []
    let color = @signals.signal(0x1559C4FFL)
    let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
    set_view_app(fn(root) {
      page.val = Some(root)
      root.box(fn(v) {
        v.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(40.0)))
          .offset(By(fn() { (20.0 + (v.drawn_at() - epoch.val) * 2.0, 20.0) }))
          .ground(By(fn() { color.get() }))
          .says(Is(Some(@view.said(Button, label="cancel"))))
          .on_press(fn() { pressed.push(v.cause_at() - epoch.val); (cancel.val)() }) |> ignore
        v.reacts(fn() { v.owed_laid_window() }, fn(_) { })
      }) |> ignore
    })
    t.draw()
    t.measure_as_host()
    t.clock_frame()
    let start = t.time()
    epoch.val = start
    let v = page.val.unwrap()
    v.reacts(fn() { v.drawn_past(start + 95.0) }, fn(_) { })
    cancel.val = v.at_moment(start + 100.0, fn() {
      fired.push(("cancelled", v.cause_at() - start))
      color.set(0xCC2222FFL)
    })
    v.at_moment(start + 105.0, fn() { fired.push(("other", v.cause_at() - start)) }) |> ignore
    t.record_host()
    let actual : Array[(Double, Double)] = []
    t.each_frame(Some(fn() { actual.push((t.time() - start, g().clock - start)) }))
    if hz > 0 {
      let period = 1000.0 / hz.to_double()
      let mut i = 1
      while i.to_double() * period < 90.0 {
        let now = start + i.to_double() * period
        t.frame_shown_at(now, now + 20.0)
        i += 1
      }
    }
    t.frame_shown_at(start + 90.0, start + 110.0)
    if hz == 0 {
      println("DLBEGIN prediction-before-deadline")
      println(t.drawlist())
      println("DLEND")
    }
    assert_eq(fired, [], msg="prediction cannot take an input deadline")
    assert_eq(view_tree().unwrap().logic_at(), start + 90.0)
    // At the predicted time the box occupies x=240..320; at these events x=208..290.
    // First press only the predicted picture, then only the event-time target.
    let miss_down_at = start + 94.0
    let miss_up_at = start + 94.5
    t.advance(miss_down_at - t.time())
    t.touch_at(0, 310.0, 30.0, miss_down_at)
    t.advance(miss_up_at - t.time())
    t.touch_at(2, 310.0, 30.0, miss_up_at)
    assert_eq(pressed, [], msg="the predicted picture cannot take the earlier touch")
    let down_at = start + 94.75
    let up_at = start + 95.0
    t.advance(down_at - t.time())
    t.touch_at(0, 220.0, 30.0, down_at)
    t.advance(up_at - t.time())
    t.touch_at(2, 220.0, 30.0, up_at)
    assert_eq(pressed, [95.0], msg="the actual touch callback keeps its event time")
    t.frame_shown_at(start + 120.0, start + 120.0)
    assert_eq(fired, [("other", 105.0)])
    let frames = t.host_frames()
    println("prediction schedule \{hz} Hz (0: direct): actual now/shown \{actual}, host frames \{frames.map(fn(f) { f.at - start })}, pressed \{pressed}, deadlines \{fired}")
    pictures.push(t.drawn_instances())
    outcomes.push((fired, pressed))
  }
  assert_eq(pictures[0], pictures[1], msg="direct and 60 Hz final drawing")
  assert_eq(pictures[0], pictures[2], msg="direct and 120 Hz final drawing")
  assert_eq(outcomes[0], outcomes[1])
  assert_eq(outcomes[0], outcomes[2])
}

///|
test "predicted visual hiding preserves a live node and its stateful observer until the input timeline removes it" {
  let pictures : Array[Array[Array[Double]]] = []
  let results : Array[(Int, Int, Array[Double], Bool)] = []
  for hz in [0, 60, 120] {
    let page : Ref[@view.View?] = Ref(None)
    let t = Tester::new(fn(_) { }, w=400.0, h=300.0)
    set_view_app(fn(root) { page.val = Some(root) })
    t.draw()
    t.measure_as_host()
    t.clock_frame()
    let start = t.time()
    let root = page.val.unwrap()
    let shown = @signals.signal(true)
    let past = @signals.signal(false)
    let made = Ref(0)
    let dropped = Ref(0)
    let pressed : Array[Double] = []
    let observed : Array[(Double, Bool)] = []
    let child : Ref[@view.View?] = Ref(None)
    root.show(fn() { shown.get() }, fn(slot) {
      slot.box(fn(v) {
        made.val += 1
        child.val = Some(v)
        v.owns(fn() { dropped.val += 1 }) |> ignore
        v.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(40.0)))
          .offset(Is((20.0, 20.0)))
          // The composer's leaving choices use this visual binding; hiding is not releasing a node.
          .laid_nowhere(By(fn() { v.drawn_past(start + 100.0) }))
          .ground(By(fn() { if past.get() { 0xCC2222FFL } else { 0x1559C4FFL } }))
          .says(Is(Some(@view.said(Button, label="kept"))))
          .on_press(fn() { pressed.push(v.cause_at() - start) }) |> ignore
        v.reacts(fn() { v.drawn_past(start + 100.0) }, fn(value) {
          past.set(value)
          observed.push((v.drawn_at() - start, value))
        })
      }) |> ignore
    })
    let id = child.val.unwrap().id()
    root.at_moment(start + 120.0, fn() { shown.set(false) }) |> ignore
    t.frame_shown_at(start, start)
    t.record_host()
    let actual : Array[(Double, Double)] = []
    t.each_frame(Some(fn() { actual.push((t.time() - start, g().clock - start)) }))
    if hz > 0 {
      let period = 1000.0 / hz.to_double()
      let mut i = 1
      while i.to_double() * period < 90.0 {
        let now = start + i.to_double() * period
        t.frame_shown_at(now, now + 40.0)
        i += 1
      }
    }
    t.frame_shown_at(start + 90.0, start + 130.0)
    assert_true(past.get(), msg="the stateful visual observer saw the predicted threshold")
    assert_true(shown.get(), msg="a visual prediction cannot remove the node at its later input deadline")
    assert_eq((made.val, dropped.val), (1, 0))
    assert_true(child.val.unwrap().id() == id)
    let down_at = start + 94.0
    let up_at = start + 95.0
    t.advance(down_at - t.time())
    t.touch_at(0, 50.0, 30.0, down_at)
    t.advance(up_at - t.time())
    t.touch_at(2, 50.0, 30.0, up_at)
    assert_eq(pressed, [95.0], msg="the earlier input sees the same live node before it hides")
    assert_eq((made.val, dropped.val), (1, 0))
    t.frame_shown_at(start + 96.0, start + 130.0)
    assert_true(past.get())
    assert_true(child.val.unwrap().id() == id)
    assert_eq((made.val, dropped.val), (1, 0))
    pictures.push(t.drawn_instances())
    t.frame_shown_at(start + 140.0, start + 140.0)
    assert_false(shown.get())
    assert_eq((made.val, dropped.val), (1, 1), msg="the actual deadline releases the original node once")
    results.push((made.val, dropped.val, pressed.copy(), past.get()))
    println("prediction lifecycle \{hz} Hz: actual now/shown \{actual}, observations \{observed}, created \{made.val}, released \{dropped.val}, presses \{pressed}")
  }
  assert_eq(pictures[0], pictures[1])
  assert_eq(pictures[0], pictures[2])
  assert_eq(results[0], results[1])
  assert_eq(results[0], results[2])
}
