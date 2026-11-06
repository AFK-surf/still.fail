///|
test "a decision's closing room keeps its node when an earlier input reopens it after a predicted closing frame" {
  let results = []
  let pictures = []
  for hz in [0, 60, 120] {
    @sfbase.reset()
    let shown = @signals.signal(true)
    let made = Ref(0)
    let released = Ref(0)
    let presses : Array[Int] = []
    let actual : Array[(Double, Double)] = []
    let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0)
    @ui.set_view_app(fn(root) {
      root.box(fn(toggle) {
        toggle.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(80.0))).height(Is(Some(40.0)))
          .ground(Is(0x999999FFL)).on_press(fn() { shown.set(!shown.get()) }) |> ignore
      }) |> ignore
      root.box(fn(room) {
        room.over(Is(true)).offset(Is((20.0, 80.0))).width(Is(Some(120.0))) |> ignore
        under_node(room, fn() { shown.get() }, fn(button) {
          made.val += 1
          button.owns(fn() { released.val += 1 }) |> ignore
          let times = @signals.signal(0)
          button.width(Is(Some(120.0))).height(Is(Some(80.0)))
            .ground(By(fn() { if times.get() >= 2 { 0x1559C4FFL } else { 0xCC2222FFL } }))
            .on_press(fn() { times.set(times.get() + 1); presses.push(times.get()) }) |> ignore
        })
      }) |> ignore
    })
    t.draw()
    t.measure_as_host()
    t.frame()
    let start = t.time()
    let first_press = start + 50.0
    let close = start + 100.0
    let reopen = start + 200.0
    let room_ms = @motion.move(over=80.0).duration(1.0, 0.0, 0.0)
    let final = close + room_ms + options_out_ms
    let tap = fn(at : Double, x : Double, y : Double) {
      t.advance(at - t.time())
      t.touch_at(0, x, y, at)
      t.touch_at(2, x, y, at)
    }
    tap(first_press, 40.0, 100.0)
    tap(close, 40.0, 30.0)
    if hz > 0 {
      let step = 1000.0 / hz.to_double()
      let mut frame = 1
      while close + frame.to_double() * step < reopen {
        let now = close + frame.to_double() * step
        let shown_at = now + room_ms
        actual.push((now - start, shown_at - start))
        t.frame_shown_at(now, shown_at)
        frame += 1
      }
    }
    tap(reopen, 40.0, 30.0)
    tap(reopen + 10.0, 40.0, 100.0)
    t.frame_at(final)
    actual.push((final - start, final - start))
    println("decision presence \{hz} Hz: actual now/shown \{actual}, made \{made.val}, released \{released.val}, presses \{presses}")
    results.push((made.val, released.val, presses.copy()))
    pictures.push(t.drawn_instances())
    assert_true(shown.get())
  }
  for r in results {
    assert_eq(r, (1, 0, [1, 2]), msg="a predicted close cannot discard the state used by the earlier input")
  }
  assert_eq(pictures[0], pictures[1])
  assert_eq(pictures[0], pictures[2])
}

///|
test "a decision's room releases once on its logical deadline and stops following the drawing clock" {
  @sfbase.reset()
  let shown = @signals.signal(true)
  let released = Ref(0)
  let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(room) {
      room.width(Is(Some(120.0))) |> ignore
      under_node(room, fn() { shown.get() }, fn(body) {
        body.height(Is(Some(80.0))).ground(Is(0x1559C4FFL)) |> ignore
        body.owns(fn() { released.val += 1 }) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let close = t.time() + 100.0
  let end = close + @motion.move(over=80.0).duration(1.0, 0.0, 0.0)
  tree.event(close, fn() { shown.set(false) })
  t.frame_shown_at(close, end)
  assert_eq(released.val, 0, msg="the predicted picture must not release the body")
  tree.event(end, fn() { })
  assert_eq(released.val, 1, msg="the declared logical end releases without another picture")
  t.frame_at(end + options_out_ms)
  assert_eq(released.val, 1)
  t.assert_idle()
}
