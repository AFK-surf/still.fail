// A made-up core's replies are inputs at their declared moments, even when
// no picture was requested between them. Drawing cannot deliver a reply late.

///|
test "fixture replies keep their cause times and order when the supplied clock skips frames" {
  for dense in [false, true] {
    new_run()
    let clock = Ref(1000.0)
    fix_clock.val = Some(fn() { clock.val })
    let seen : Array[(Int, Double)] = []
    // Registered out of order, with a reply that schedules another reply.
    fix_later(200.0, fn() { seen.push((2, clock.val)) })
    fix_later(100.0, fn() {
      seen.push((1, clock.val))
      fix_later(50.0, fn() { seen.push((3, clock.val)) })
    })
    if dense {
      for at in [1050.0, 1100.0, 1150.0, 1200.0] { fix_clock_set(clock, at) }
    }
    fix_clock_set(clock, 1300.0)
    assert_eq(seen, [(1, 1100.0), (3, 1150.0), (2, 1200.0)])
    assert_eq(clock.val, 1300.0)
  }
}

///|
test "a later input delivers due fixture replies at their own moments without a drawn frame" {
  let results : Array[Array[Double]] = []
  for hz in [0, 60, 120] {
    let t = wide_tester([], mode="chat", w=390.0, h=844.0, platform=2)
    let tree = @ui.view_tree().unwrap()
    let start = tree.logic_at()
    let first_at = start + 100.0
    let nested_at = first_at + 50.0
    let seen : Array[Double] = []
    fix_later(100.0, fn() {
      seen.push(tree.logic_at())
      fix_later(50.0, fn() { seen.push(tree.logic_at()) })
    })
    t.record_host()
    if hz > 0 {
      let period = 1000.0 / hz.to_double()
      let mut i = 1
      while i.to_double() * period < 300.0 {
        t.frame_at(start + i.to_double() * period)
        i += 1
      }
    }
    t.touch_at(0, -100.0, -100.0, start + 300.0)
    assert_eq(seen, [first_at, nested_at])
    let frames = t.host_frames().map(fn(f) { f.at - start })
    if hz == 0 { assert_eq(frames, []) }
    println("fixture schedule \{hz} Hz (0: direct): frames \{frames}, replies \{seen}")
    results.push(seen.copy())
    t.touch_at(2, -100.0, -100.0, start + 300.0)
  }
  assert_eq(results[0], results[1])
  assert_eq(results[0], results[2])
}

///|
test "fixture replies at the same moment keep registration order including a nested reply" {
  new_run()
  let clock = Ref(1000.0)
  fix_clock.val = Some(fn() { clock.val })
  let seen : Array[(String, Double)] = []
  fix_later(100.0, fn() {
    seen.push(("first", clock.val))
    fix_later(0.0, fn() { seen.push(("nested", clock.val)) })
  })
  fix_later(100.0, fn() { seen.push(("second", clock.val)) })
  fix_clock_set(clock, 1200.0)
  assert_eq(seen, [("first", 1100.0), ("second", 1100.0), ("nested", 1100.0)])
  fix_clock_set(clock, 1200.0)
  assert_eq(seen.length(), 3, msg="replies are delivered once")
}

///|
test "replies queued before the app is made join its timeline after construction, once" {
  let results : Array[Array[(String, Double)]] = []
  for hz in [0, 60, 120] {
    new_run()
    let base = fixture("chat")
    let seen : Array[(String, Double)] = []
    fix_later(100.0, fn() {
      seen.push(("first", @ui.view_tree().unwrap().logic_at()))
      fix_later(0.0, fn() { seen.push(("nested", @ui.view_tree().unwrap().logic_at())) })
    })
    fix_later(100.0, fn() { seen.push(("second", @ui.view_tree().unwrap().logic_at())) })
    let reads : Array[(String, Bool, Bool, Int, Int)] = []
    let handed_at = Ref(-1.0)
    let src : Source = {
      ..base,
      topic: fn(name, params) {
        let before = @sffixture.fix_unsaid.length()
        let context = @sffixture.fix_ctx.val is Some(_)
        let tree = @ui.view_tree()
        let answer = (base.topic)(name, params)
        if before > 0 {
          reads.push((name, context, tree is Some(_), before, @sffixture.fix_unsaid.length()))
          if @sffixture.fix_unsaid.is_empty() {
            handed_at.val = tree.map(fn(t) { t.logic_at() }).unwrap_or(-1.0)
          }
        }
        answer
      },
    }
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    assert_true(reads.any(fn(r) { !r.1 && !r.2 && r.3 == r.4 }), msg="the real app reads the fixture while its tree is being made, before a frame's context exists")
    assert_true(reads.any(fn(r) { r.1 && r.2 && r.4 == 0 }), msg="the first frame hands the queued replies to its already published tree")
    assert_false(reads.any(fn(r) { r.1 && !r.2 }), msg="the app's startup never gives a context before its tree exists")
    assert_true(handed_at.val >= 0.0)
    assert_true(@sffixture.fix_unsaid.is_empty())
    assert_true(@sffixture.fix_timers.is_empty(), msg="the window is not using the manual fixture clock")
    let start = t.time()
    t.record_host()
    if hz > 0 {
      let period = 1000.0 / hz.to_double()
      let mut i = 1
      while i.to_double() * period < 300.0 {
        t.frame_at(start + i.to_double() * period)
        i += 1
      }
    }
    t.touch_at(0, -100.0, -100.0, start + 300.0)
    let due = handed_at.val + 100.0
    assert_eq(seen, [("first", due), ("second", due), ("nested", due)])
    t.touch_at(2, -100.0, -100.0, start + 400.0)
    assert_eq(seen.length(), 3, msg="the startup handoff and later input deliver each reply once")
    let frames = t.host_frames().map(fn(f) { f.at })
    if hz == 0 { assert_eq(frames, []) }
    println("fixture startup \{hz} Hz: reads \{reads}, handed \{handed_at.val}, frames \{frames}, replies \{seen}")
    results.push(seen.copy())
  }
  assert_eq(results[0], results[1])
  assert_eq(results[0], results[2])
}

///|
test "the window's fixture timeline keeps equal-time and nested registration order" {
  let t = wide_tester([], mode="chat", w=390.0, h=844.0, platform=2)
  let tree = @ui.view_tree().unwrap()
  let start = tree.logic_at()
  let seen : Array[(String, Double)] = []
  fix_later(100.0, fn() {
    seen.push(("first", tree.logic_at()))
    fix_later(0.0, fn() { seen.push(("nested", tree.logic_at())) })
  })
  fix_later(100.0, fn() { seen.push(("second", tree.logic_at())) })
  t.record_host()
  t.touch_at(0, -100.0, -100.0, start + 200.0)
  let due = start + 100.0
  assert_eq(seen, [("first", due), ("second", due), ("nested", due)])
  t.touch_at(2, -100.0, -100.0, start + 300.0)
  assert_eq(seen.length(), 3)
  assert_eq(t.host_frames().length(), 0)
  println("fixture tree order: \{seen}")
}
