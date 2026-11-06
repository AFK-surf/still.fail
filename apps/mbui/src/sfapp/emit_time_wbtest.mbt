// Replies are inputs. Their declared phases advance on the window's input
// timeline even when no intervening picture is requested.

///|
test "an arriving answer starts and advances its phases at the same causes across frame histories" {
  let results : Array[Array[(Int, Pose?, Double)]] = []
  let endings : Array[Double?] = []
  for hz in [0, 60, 120] {
    let t = emit_window(390.0)
    t.tap_text("发消息")
    t.type_text("看一下列表")
    tap_send(t)
    let sent_at = t.time()
    let replied_at = sent_at + fix_deliver_ms + fix_answer_ms
    // The same initial history in every run: the station has the sent words
    // and its activity is present, before the reply arrives.
    t.frame_at(sent_at + fix_deliver_ms + @ui.move_most_ms)
    let start = t.time()
    t.record_host()
    let em = emits_of(emit_chat)
    let seen : Array[(Int, Pose?, Double)] = []
    let period = if hz == 0 { 1.0 } else { 1000.0 / hz.to_double() }
    let mut frame = 1
    for at in [replied_at + 1.0, replied_at + Pose::Fold.ms() + 1.0, replied_at + Pose::Fold.ms() + Pose::Float.ms() + 1.0, replied_at + Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() + 1.0, replied_at + emit_all_ms() + @ui.move_most_ms] {
      if hz > 0 {
        while start + frame.to_double() * period < at {
          t.frame_at(start + frame.to_double() * period)
          frame += 1
        }
      }
      t.touch_at(0, -100.0, -100.0, at)
      seen.push((em.queue.length(), em.current.map(fn(p) { p.pose }), em.current.map(fn(p) { p.clock.end() }).unwrap_or(-1.0)))
      t.touch_at(2, -100.0, -100.0, at)
    }
    let frames = t.host_frames().map(fn(f) { f.at })
    println("answer timeline \{hz} Hz: reply \{replied_at}, phases \{seen}, frames \{frames}")
    if hz == 0 { assert_eq(frames, []) }
    results.push(seen)
    endings.push(em.ended.get("s-c1"))
  }
  assert_true(results[0] == results[1], msg="the same replies and touches keep the same phases without output frames")
  assert_true(results[0] == results[2], msg="display cadence cannot start or advance a reply")
  assert_true(results[0].map(fn(s) { (s.0, s.1) }) == [(0, Some(Fold)), (0, Some(Float)), (0, Some(Spit)), (0, Some(Return)), (0, None)])
  assert_eq(endings[0], endings[1])
  assert_eq(endings[0], endings[2])
}

///|
test "two queued answers of one agent keep their handoff and return with no intervening pictures" {
  let results : Array[Array[(Double?, Pose?, Double, (Double, Double)?)]] = []
  for hz in [0, 60, 120] {
    let t = emit_window(390.0)
    t.tap_text("发消息")
    t.type_text("看一下列表")
    tap_send(t)
    let sent_at = t.time()
    let replied_at = sent_at + fix_deliver_ms + fix_answer_ms
    t.frame_at(sent_at + fix_deliver_ms + @ui.move_most_ms)
    let start = t.time()
    fix_later(replied_at + 50.0 - start, fn() {
      fix_chat("s-c1").sent.push(
        msg(171, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), more_said, "刚刚", {
          "ts": Json::string("more171"),
          "said": true,
        }),
      )
    })
    t.record_host()
    let em = emits_of(emit_chat)
    let seen : Array[(Double?, Pose?, Double, (Double, Double)?)] = []
    let period = if hz == 0 { 1.0 } else { 1000.0 / hz.to_double() }
    let mut frame = 1
    let handed_at = replied_at + Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms()
    for at in [handed_at + 1.0, handed_at + @sfbase.emit_drop_ms + 1.0, handed_at + @sfbase.emit_drop_ms + Pose::Spit.ms() + 1.0, handed_at + emit_all_ms() + @ui.move_most_ms] {
      if hz > 0 {
        while start + frame.to_double() * period < at {
          t.frame_at(start + frame.to_double() * period)
          frame += 1
        }
      }
      t.touch_at(0, -100.0, -100.0, at)
      seen.push((em.current.map(fn(p) { p.seq }), em.current.map(fn(p) { p.pose }), em.current.map(fn(p) { p.clock.end() }).unwrap_or(-1.0), em.current.bind(fn(p) { p.from })))
      t.touch_at(2, -100.0, -100.0, at)
    }
    println("queued answer timeline \{hz} Hz: handoff \{handed_at}, phases \{seen}, frames \{t.host_frames().map(fn(f) { f.at })}")
    if hz == 0 { assert_eq(t.host_frames().length(), 0) }
    assert_true(em.current is None && em.queue.is_empty())
    assert_true(em.done.contains("171"))
    results.push(seen)
  }
  assert_true(results[0] == results[1], msg="a drawn landing cannot decide the next answer's phase or return")
  assert_true(results[0] == results[2], msg="the same queued replies must hand off at the same moment and place")
  assert_true(results[0].map(fn(s) { (s.0, s.1) }) == [(Some(171.0), Some(Float)), (Some(171.0), Some(Spit)), (Some(171.0), Some(Return)), (None, None)])
}
