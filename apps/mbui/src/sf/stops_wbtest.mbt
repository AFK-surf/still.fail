// The stops (seg.mbt's `stops`): a few levels in order on one line, the one it is at named in its thumb.

///|
/// A phone's window with the stops of `labels` in it, at `chosen` as its caller says; what was picked in it, in order.
fn stops_run(labels : Array[String], chosen : Ref[Int], state : Stops, picks : Array[Int]) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() {
          stops(c, "depth", labels, chosen.val, state, said="思考深度", on_pick=fn(i) { picks.push(i) }) |> ignore
        })
        |> ignore
      })
    },
    w=360.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Which of `labels` are drawn.
fn stops_named(t : @ui.Tester, labels : Array[String]) -> Array[String] {
  labels.filter(fn(l) { t.words().iter().any(fn(w) { w.0 == l }) })
}

///|
test "stops: every level a stop on one line, the one it is at alone named; a stop tapped is picked, said once, and stays shown while its caller still says the level before" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (Ref(2), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let s = t.get(@ui.Role::Slider, label="思考深度")
  assert_eq(s.value, "高")
  assert_eq(stops_named(t, labels), ["高"])
  // (its name whole in its thumb, the thumb in its track)
  let (x, y, w, h) = s.rect
  let (nx, _, nw, _) = t.rect_of("高").unwrap()
  assert_true(nx >= x && nx + nw <= x + w, msg="\{Repr((nx, nw))} in \{Repr(s.rect)}")
  // its last stop tapped
  t.tap(x + w - w / 8.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [3])
  assert_eq(stops_named(t, labels), ["最高"])
  assert_eq(t.get(@ui.Role::Slider, label="思考深度").value, "最高")
  // (its caller's save answered before its value is told: it says the level before for a while yet)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["最高"], msg="taken back to what its caller still says")
  // said back, then another level from elsewhere: news, shown
  chosen.val = 3
  t.draw()
  chosen.val = 1
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["中"])
  assert_eq(picks, [3], msg="what its caller says is not a pick")
  assert_eq(t.squeeze_faults(), [])
}

///|
test "stops: a finger takes its thumb along the track, nothing picked on the way; let go, the level under the finger is picked" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (Ref(2), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  let at = fn(i : Int) { x + w * (i.to_double() + 0.5) / 4.0 }
  let mid = y + h / 2.0
  // down on the stop it is at, along to its first: the stop under the finger named as it goes, none picked
  t.touch(0, at(2), mid)
  t.frame()
  t.touch(1, at(1), mid)
  t.frame()
  assert_eq(picks, [])
  t.touch(1, at(0), mid)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [])
  assert_eq(stops_named(t, labels), ["低"])
  // let go there
  t.touch(2, at(0), mid)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [0])
  assert_eq(stops_named(t, labels), ["低"])
}

///|
test "stops: at none of its levels, a stop tapped stays shown while its caller still says none; its caller's reset takes it back to none" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (Ref(-1), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  assert_eq(stops_named(t, labels), [])
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  t.tap(x + w * 2.5 / 4.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [2])
  // (its caller's save answered before its value is told: it says none for a while yet)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["高"], msg="taken back to none while its save is on its way")
  // kept none of it
  state.reset()
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), [])
}

///|
test "stops: a pick that did not take (its caller's reset) shows what its caller says again" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (Ref(1), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  t.tap(x + w - w / 8.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["最高"])
  state.reset()
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["中"])
}

///|
test "stops: seven levels with long names on a narrow phone: still one line, the one it is at whole in its thumb" {
  let labels = ["Minimal", "Low", "Medium", "High", "Very high", "Maximum", "Ultra"]
  let (chosen, state, picks) = (Ref(4), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  t.resize(320.0, 200.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let (x, _, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  assert_eq(t.lines_of("Very high"), ["Very high"])
  let (nx, _, nw, _) = t.rect_of("Very high").unwrap()
  assert_true(nx >= x && nx + nw <= x + w, msg="\{Repr((nx, nw))} in \{Repr((x, w))}")
  assert_true(h <= 44.5, msg="\{h} high: more than a line")
  assert_eq(stops_named(t, labels), ["Very high"])
  assert_eq(t.squeeze_faults(), [])
}
