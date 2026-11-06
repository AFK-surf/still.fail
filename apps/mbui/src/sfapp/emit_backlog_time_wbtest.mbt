// A retained page keeps the deadlines of replies already in flight while it is
// covered. Returning after several agents' turns expired must finish all of
// them at that input, even when there is no following display frame.

///|
fn backlog_window(width : Double, ended : Ref[Bool]) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard name == "chat" && got.value is Some(Object(chat)) else { return got }
      let agents = ["s-c1", "backlog-b", "backlog-c", "backlog-d"].map(fn(key) -> Json {
        {
          "session": {
            "key": Json::string(key),
            "runtime": "claude",
            "maker": { "id": "anthropic", "name": "Anthropic" },
            "agentText": Json::string(key),
            "statusText": Json::string(if ended.val { "已完成" } else { "进行中" }),
            "tone": "neutral",
          },
          "status": Json::string(if ended.val { "idle" } else { "running" }),
          "started": true,
          "since": 0,
        }
      })
      let changed = chat.copy()
      changed["agents"] = Json::array(agents)
      { ..got, value: Some(Json::object(changed)) }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform=if width < 600.0 { 2 } else { 0 })
  t.keep_parts(true)
  t.run_for(@ui.move_most_ms)
  t.ctx().blur()
  t.run_for(@sfpages.let_go_ms + @ui.move_most_ms + @sf.hint_back_ms)
  t
}

///|
test "returning to four agents' expired replies drains beyond one pose batch without another picture" {
  for width in [390.0, 1280.0] {
    let pictures : Array[String] = []
    let words : Array[Array[(String, Double, Double, Double, Double, Double)]] = []
    let hits : Array[Array[String]] = []
    for hz in [0, 60, 120] {
      let ended = Ref(false)
      let t = backlog_window(width, ended)
      let tree = @ui.view_tree().unwrap()
      let rd = reading_of(emit_chat)
      let shown = rd.shown_by.unwrap()
      assert_true(shown(), msg="the chat is visible before replies arrive")
      let agents = ["s-c1", "backlog-b", "backlog-c", "backlog-d"]
      let arrived_at = t.time() + 1.0
      fix_later(1.0, fn() {
        ended.val = true
        for i, key in agents {
          fix_chat("s-c1").sent.push(msg(171 + i, "agent", @sffixture.by_agent("anthropic", "claude", key), more_said, "刚刚", {
            "ts": Json::string("backlog\{i}"), "said": true,
          }))
        }
      })
      // This initial picture is common to every run: one agent in Float,
      // three different agents waiting, hence at least twelve expired poses
      // to finish after the page returns (the later Folds have already ended).
      t.frame_at(arrived_at + Pose::Fold.ms() + 1.0)
      let em = emits_of(emit_chat)
      assert_true(em.current is Some(turn) && turn.pose == Float && turn.agent == agents[0])
      assert_eq(em.queue.map(fn(q) { q.2 }), agents[1:].to_array())
      let held = em.current.unwrap()
      let start = t.time()
      let returned_at = start + agents.length().to_double() * (emit_all_ms() + @ui.move_most_ms)
      fix_later(1.0, fn() { @sfbase.open_page_over(Setting(About)) })
      fix_later(returned_at - start, fn() { @sfbase.back_pop() })
      t.record_host()
      let period = if hz == 0 { 1.0 } else { 1000.0 / hz.to_double() }
      let mut frame = 1
      for at in [returned_at - 1.0, returned_at + 1.0] {
        if hz > 0 {
          while start + frame.to_double() * period < at {
            t.frame_at(start + frame.to_double() * period)
            frame += 1
          }
        }
        t.touch_at(0, -100.0, -100.0, at)
        t.touch_at(2, -100.0, -100.0, at)
        if at < returned_at {
          assert_false(shown(), msg="the real chat page is covered")
          assert_true(physical_equal(em.current.unwrap(), held), msg="covering the page keeps its original phase and deadline")
          assert_eq(em.queue.length(), 3)
          assert_true(em.queue.iter().all(fn(q) { q.3.end() < at }))
        }
      }
      println("backlog returned \{width}, \{hz} Hz at \{returned_at}: current \{em.current.map(fn(turn) { (turn.seq, turn.pose, turn.clock.end()) })}, queue \{em.queue.map(fn(q) { q.0 })}, done \{em.done.length()}, revealing \{em.out_at.length()}, due \{tree.due_count()}, frames \{t.host_frames().length()}")
      if hz == 0 { assert_eq(t.host_frames().length(), 0) }
      assert_true(t.host_frames().iter().all(fn(frame) { frame.at < returned_at }), msg="returning has no following picture in any history")
      assert_true(shown() && physical_equal(rd.shown_by.unwrap(), shown), msg="returning keeps the same retained page")
      assert_true(em.current is None && em.queue.is_empty() && em.out_at.is_empty(), msg="every expired reply finishes before the next picture")
      for i in 0..<agents.length() { assert_true(em.done.contains("\{171 + i}")) }
      // The final common picture is after the page's return and the ended
      // activities' declared linger, not after another reply's running time.
      t.frame_at(returned_at + linger_ms + 2.0 * @ui.move_most_ms)
      t.assert_idle()
      assert_true(tree.wake_waited() is None && t.next_wake() is None, msg="no expired reply is waiting for another callback")
      // Compare glyphs by their content key, not the atlas positions assigned
      // by earlier frames; all instances and their clipping stay in the text.
      pictures.push(t.drawn_text())
      words.push(t.words_said())
      let targets : Array[String] = []
      for y in 0..<22 {
        for x in 0..<33 {
          let target = t.press_target_at(width * x.to_double() / 32.0, 844.0 * y.to_double() / 21.0)
          targets.push(target.map(fn(n) { "\{n.role}:\{n.label}:\{n.rect}" }).unwrap_or(""))
        }
      }
      hits.push(targets)
      assert_true(targets.iter().any(fn(s) { s != "" }), msg="the final picture has live input targets")
      tree.dispose()
      assert_true(rd.shown_by is None, msg="releasing the page removes its navigation reader")
      assert_eq((tree.alive(), tree.bindings_held(), tree.due_count()), (0, 0, 0))
    }
    if pictures[0] != pictures[1] {
      // Keep the complete comparison below, and name its first differing instances on CI instead of only the
      // assertion's message. Atlas slots have already been replaced by glyph content keys by drawn_text.
      let direct = pictures[0].split("\n").map(fn(s) { s.to_string() }).to_array()
      let framed = pictures[1].split("\n").map(fn(s) { s.to_string() }).to_array()
      let lines = if direct.length() > framed.length() { direct.length() } else { framed.length() }
      let mut different = 0
      for i in 0..<lines {
        if direct.get(i) != framed.get(i) {
          if different < 8 {
            println("backlog picture \{width} line \{i}: 0 Hz \{direct.get(i)}; 60 Hz \{framed.get(i)}")
          }
          different += 1
        }
      }
      println("backlog picture \{width}: lines \{direct.length()}/\{framed.length()}, different \{different}")
    }
    assert_eq(pictures[0], pictures[1], msg="all drawing instances at rest are independent of intermediate frames")
    assert_eq(pictures[0], pictures[2])
    assert_eq(words[0], words[1])
    assert_eq(words[0], words[2])
    assert_eq(hits[0], hits[1])
    assert_eq(hits[0], hits[2])
  }
}
