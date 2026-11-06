// A Float chooses its duration at the phase cause. Use real placed views as its two endpoints, while the
// Tester's host either draws on the way or advances through the same deadlines without any output frames.

///|
fn float_cause_history(
  distance : Double,
  hz : Int,
  landing_late : Bool,
  drop : Bool,
  dispatch_late : Bool,
) -> Array[(Double, String, Double, Double, Double)] raise {
  let key = "float-cause-test"
  let avatar_key = "emit-avatar/" + key + "/agent"
  let first_key = "emit-landing/" + key + "/1"
  let next_key = "emit-landing/" + key + (if drop { "/2" } else { "/1" })
  let owner : Ref[@view.View?] = Ref(None)
  let landing : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=390.0, h=844.0, platform=2)
  @ui.set_view_app(fn(root) {
    owner.val = Some(root)
    let avatar = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Is((0.0, 100.0))) |> ignore
    })
    emit_places[avatar_key] = { node: avatar, dy: 0.0 }
    if drop {
      let first = root.box(fn(v) {
        v.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Is((0.0, 97.0))) |> ignore
      })
      emit_places[first_key] = { node: first, dy: 0.0 }
    }
    let target = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Is((0.0, 97.0 + distance))) |> ignore
    })
    landing.val = Some(target)
    if !landing_late { emit_places[next_key] = { node: target, dy: 0.0 } }
  })
  t.draw()
  let root = owner.val.unwrap()
  root.tree.laid_as_now()
  let from = emit_place_now(root, if drop { first_key } else { avatar_key }).unwrap()
  let target = landing.val.unwrap().placed_window_now(drawing=true)
  let from_y = from.1 + (if drop { 3.0 } else { 0.0 })
  assert_true((target.1 + 3.0 - from_y - distance).abs() < 0.01, msg="the placed endpoints are \{distance} points apart")
  let place = fn(k) { emit_place_now(root, k) }
  let e = emits_of(key)
  e.watched = true
  let start = t.time()
  let initial = if drop { Spit } else { Fold }
  let initial_span = initial.ms()
  e.current = Some({
    seq: 1.0, ts: "one", agent: "agent", pose: initial, from: None, from_at: None,
    clock: pose_clock(initial_span, Some(start)), span: initial_span, warp: None, timed: true,
  })
  if drop { e.queue.push((2.0, "two", "agent", pose_clock(Fold.ms(), Some(start)))) }
  let snapshots : Array[(Double, String, Double, Double, Double)] = []
  let capture = fn() {
    match e.current {
      Some(turn) => snapshots.push((turn.seq, turn.pose.to_string(), turn.clock.starts_at() - start, turn.clock.end() - start, turn.span))
      None => ()
    }
  }
  let due = start + initial_span + (if dispatch_late { 100.0 } else { 0.0 })
  root.at_moment(due, fn() {
    root.tree.laid_as_now()
    emit_step(t.ctx(), key, e, ["agent"], turns_of(key), -1.0, place~, one_phase=true, at=due)
    capture()
    // Mounting or changing the landing at the same cause must not revise a route already declared.
    if landing_late { emit_places[next_key] = { node: landing.val.unwrap(), dy: 0.0 } }
    emit_step(t.ctx(), key, e, ["agent"], turns_of(key), -1.0, place~, one_phase=true, at=due)
    capture()
    match e.current {
      Some(turn) => {
        let end = turn.clock.end()
        root.at_moment(end, fn() {
          emit_step(t.ctx(), key, e, ["agent"], turns_of(key), -1.0, place~, one_phase=true, at=end)
          capture()
        }) |> ignore
      }
      None => ()
    }
  }) |> ignore
  t.record_host()
  let finish = start + 1200.0
  if hz > 0 {
    let period = 1000.0 / hz.to_double()
    let mut frame = 1
    while start + frame.to_double() * period < finish {
      t.frame_at(start + frame.to_double() * period)
      frame += 1
    }
  }
  t.touch_at(0, -100.0, -100.0, finish)
  t.touch_at(2, -100.0, -100.0, finish)
  if hz == 0 { assert_eq(t.host_frames().length(), 0) }
  root.tree.dispose()
  emits.remove(key) |> ignore
  turns_by.remove(key) |> ignore
  emit_places.remove(avatar_key)
  emit_places.remove(first_key)
  emit_places.remove(next_key)
  snapshots
}

///|
test "Float uses the two endpoints at its cause and keeps that choice across host frame histories" {
  // move_ms(25)=250, move_ms(400)=350 and move_ms(100)=300. Float's 440 ms is scaled by those moves.
  for (distance, expected) in [(25.0, 367.0), (400.0, 513.0)] {
    let no_frames = float_cause_history(distance, 0, false, false, false)
    assert_eq(no_frames.length(), 3)
    assert_eq((no_frames[0].1, no_frames[0].4), ("Float", expected))
    assert_eq(no_frames[0], no_frames[1])
    assert_eq((no_frames[2].1, no_frames[2].2), ("Spit", no_frames[0].3))
    assert_eq(no_frames, float_cause_history(distance, 60, false, false, false))
    assert_eq(no_frames, float_cause_history(distance, 120, false, false, false))
  }
}

///|
test "a missing landing or a late phase dispatch keeps the usual route" {
  for (late, missing) in [(false, true), (true, true), (true, false)] {
    let no_frames = float_cause_history(25.0, 0, missing, false, late)
    assert_eq(no_frames.length(), 3)
    assert_eq((no_frames[0].1, no_frames[0].4), ("Float", 440.0))
    assert_eq(no_frames[0], no_frames[1])
    assert_eq((no_frames[2].1, no_frames[2].2), ("Spit", no_frames[0].3))
    assert_eq(no_frames, float_cause_history(25.0, 60, missing, false, late))
    assert_eq(no_frames, float_cause_history(25.0, 120, missing, false, late))
  }
}

///|
test "the same agent's next answer chooses its drop from the two placed landings at handoff" {
  for (distance, expected) in [(25.0, 233.0), (400.0, 327.0)] {
    let no_frames = float_cause_history(distance, 0, false, true, false)
    assert_eq(no_frames.length(), 3)
    assert_eq((no_frames[0].0, no_frames[0].1, no_frames[0].4), (2.0, "Float", expected))
    assert_eq(no_frames[0], no_frames[1])
    assert_eq((no_frames[2].1, no_frames[2].2), ("Spit", no_frames[0].3))
    assert_eq(no_frames, float_cause_history(distance, 60, false, true, false))
    assert_eq(no_frames, float_cause_history(distance, 120, false, true, false))
  }
}
