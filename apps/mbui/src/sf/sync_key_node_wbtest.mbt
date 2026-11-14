// The keys of a bar for what goes on by itself as nodes (sync_key_node.mbt).

///|
/// A sync key node said by `syncing`, in a Tester; whether it is read out (its Status) at each moment asked.
fn sync_key_tester(syncing : @signals.Signal[String?]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    let tips = TipLayer::new(fn() { Some(root) })
    root.box(fn(b) {
      b.row(Is(true)) |> ignore
      sync_key_node(b, tips, 34.0, 20.0, fn() { syncing.get() })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn sync_key_said(t : @ui.Tester, words : String) -> Bool {
  t.query(Status, label=words) is Some(_)
}

///|
test "sync key node: a moment's catching up shows nothing; once it has gone on, it turns; all here, it ticks, stands, then goes" {
  let syncing = @signals.signal(Some("正在同步 · 还剩 3 个对话"))
  let t = sync_key_tester(syncing)
  let words = "正在同步 · 还剩 3 个对话"
  // (not yet: nothing laid out or read out)
  let at_first = sync_key_said(t, words)
  t.run_for(later_ms + @kit.presence_in_ms)
  let after_wait = sync_key_said(t, words)
  // (turning by the clock: drawn otherwise a quarter turn on)
  let turning_a = t.drawn_instances_keyed()
  t.run_for(sync_turn_ms / 4.0)
  let turning_b = t.drawn_instances_keyed()
  syncing.set(None)
  t.draw()
  // (all here: still there, ticking, under the words it said last)
  let ticking = sync_key_said(t, words)
  t.run_for(sync_settle_most + sync_back_ms + sync_tick_ms + sync_done_ms / 2.0)
  let standing = sync_key_said(t, words)
  t.run_for(sync_done_ms / 2.0 + sync_out_ms)
  let gone = sync_key_said(t, words)
  assert_eq((at_first, after_wait, turning_a != turning_b, ticking, standing, gone), (false, true, true, true, true, false))
}

///|
test "sync key node: catching up ended before it showed, nothing; begun again, it waits its moment again" {
  let syncing = @signals.signal(Some("正在同步"))
  let t = sync_key_tester(syncing)
  t.run_for(later_ms / 2.0)
  syncing.set(None)
  t.draw()
  t.run_for(later_ms + sync_done_ms)
  let never = sync_key_said(t, "正在同步")
  syncing.set(Some("正在同步"))
  t.draw()
  t.run_for(later_ms / 2.0)
  let half = sync_key_said(t, "正在同步")
  t.run_for(later_ms / 2.0 + @kit.presence_in_ms)
  assert_eq((never, half, sync_key_said(t, "正在同步")), (false, false, true))
}

///|
/// The refresh mark's rotation as actually drawn (each of its shape bands has the same turn).
fn sync_drawn_angle(t : @ui.Tester) -> Double raise {
  let shapes = t.drawn_instances_keyed().filter(fn(i) { i[5] == 11.0 })
  assert_true(shapes.length() > 0, msg="the sync mark is drawn")
  shapes[0][32]
}

///|
/// Clockwise distance through the join between two turns.
fn sync_angle_step(from : Double, to : Double) -> Double {
  let d = to - from
  if d < 0.0 { d + 2.0 * 3.141592653589793 } else { d }
}

///|
test "sync key node: the drawn mark turns evenly through the join, with at least 60 frames a second requested" {
  let syncing = @signals.signal(Some("正在同步"))
  let t = sync_key_tester(syncing)
  t.run_for(later_ms + @kit.presence_in_ms)
  assert_eq(t.audit(), [])
  // Start on a turn's join, then inspect each eighth through two whole turns, including both joins.
  let start = (t.time() / sync_turn_ms).ceil() * sync_turn_ms
  t.frame_at(start)
  let mut before = sync_drawn_angle(t)
  for i in 1..=16 {
    t.frame_at(start + i.to_double() * sync_turn_ms / 8.0)
    let after = sync_drawn_angle(t)
    let step = sync_angle_step(before, after)
    assert_true((step - 3.141592653589793 / 4.0).abs() < 0.00001, msg="step \{i}: \{step}")
    before = after
  }
  // Follow it on a 120 Hz display: 0 means every display frame, otherwise the requested rate.
  let at = t.time()
  for i in 1..=192 {
    t.frame_at(at + i.to_double() * 1000.0 / 120.0)
    let rate = t.frames_paced()
    assert_true(rate == 0.0 || rate >= 60.0, msg="frame \{i}: \{rate} Hz")
  }
}

///|
test "sync key node: finishing at any point goes on from the drawn angle and speed before slowing to a tick" {
  let pi = 3.141592653589793
  for phase in [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 0.999] {
    let syncing = @signals.signal(Some("正在同步"))
    let t = sync_key_tester(syncing)
    t.run_for(later_ms + @kit.presence_in_ms)
    let at = (3.0 + phase) * sync_turn_ms
    t.frame_at(at)
    let before = sync_drawn_angle(t)
    syncing.set(None)
    t.frame_at(at)
    let finishing = sync_drawn_angle(t)
    t.frame_at(at + 1.0)
    let next = sync_drawn_angle(t)
    let delta = sync_angle_step(finishing, next)
    assert_true(sync_angle_step(before, finishing) < 0.00001, msg="phase \{phase}: angle jumped at completion")
    assert_true((delta - 2.0 * pi / sync_turn_ms).abs() < 0.0002, msg="phase \{phase}: first step \{delta}")
  }
}
