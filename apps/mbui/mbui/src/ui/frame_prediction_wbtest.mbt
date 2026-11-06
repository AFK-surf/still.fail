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
          .offset(By(fn() { (20.0 + (v.drawn_at() - epoch.val) / 10.0, 20.0) }))
          .ground(By(fn() { color.get() }))
          .says(Is(Some(@view.said(Button, label="cancel"))))
          .on_press(fn() { pressed.push(v.cause_at() - epoch.val); (cancel.val)() }) |> ignore
        v.reacts(fn() { v.laid_window_told() }, fn(_) { })
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
    t.advance(start + 94.0 - t.time())
    t.touch_at(0, 50.0, 30.0, start + 94.0)
    t.advance(1.0)
    t.touch_at(2, 50.0, 30.0, start + 95.0)
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
