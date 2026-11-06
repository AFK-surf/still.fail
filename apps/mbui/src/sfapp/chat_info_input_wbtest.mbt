///|
fn info_release(t : @ui.Tester, label : String, hz : Int, role? : @ui.Role = Button) -> Double raise {
  let (left, top, width, height) = t.get(role, label~).rect
  let x = left + width / 2.0
  let y = top + height / 2.0
  let start = t.time()
  let press_ms = 50.0
  let release_at = start + press_ms
  let frames : Array[Double] = []
  t.record_host()
  t.touch_at(0, x, y, start)
  if hz > 0 {
    let period = 1000.0 / hz.to_double()
    let mut i = 1
    while i.to_double() * period < press_ms {
      let at = start + i.to_double() * period
      t.frame_at(at)
      frames.push(at)
      i += 1
    }
  }
  t.advance(release_at - t.time())
  t.touch_at(2, x, y, release_at)
  assert_eq(t.host_frames().map(fn(f) { f.at }), frames)
  println("info input \{label} at \{start}/\{release_at}, \{hz} Hz: actual frames \{frames}")
  release_at
}

///|
test "a chat info action opens its tab and closes the info at release, once, with no following frame" {
  for (label, tab) in [("Station 文件", "files"), ("图片、文件和链接", "things"), ("全部 4 个 PR", "things"), ("agent 往来", "letters")] {
    let release_times : Array[Double] = []
    for hz in [0, 60, 120] {
      new_run()
      let calls : Array[Made] = []
      let opened_at : Array[Double] = []
      let base = fixture("chat")
      let src : Source = {
        ..base,
        topic: fn(name, params) {
          let answer = (base.topic)(name, params)
          match (tab, name, answer.value) {
            ("letters", "chat", Some(v)) => { ..answer, value: Some(fix_with_letters(v)) }
            ("letters", "chatLetters", _) => { ..answer, value: Some(fix_letters()) }
            _ => answer
          }
        },
        call: fn(name, params, done) {
          calls.push({ name, params, bytes: None, done, heard: None })
          if name == "chat.tabs.open" {
            opened_at.push(@ui.view_tree().unwrap().logic_at())
          }
          (base.call)(name, params, done)
        },
      }
      let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
      open_chat(r)
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
      t.run_for(@ui.move_most_ms)
      t.click(Button, label="对话信息")
      t.run_for(@kit.pop_ms)
      let release_at = info_release(t, label, hz)
      release_times.push(release_at)
      assert_eq(@sfdesk.chat_pops_open().0, false, msg=label)
      assert_eq(side_now(r), ([tab], tab), msg=label)
      let opened = named(calls, "chat.tabs.open")
      assert_eq(opened.length(), 1, msg=label)
      assert_eq(text(Some(opened[0].params), "chat"), "ws1/st1:s-c1")
      assert_eq(opened_at, [release_at], msg="the action belongs to the release's input time")
      t.run_for(dmax(@kit.presence_out_ms, @ui.move_most_ms))
      assert_eq(named(calls, "chat.tabs.open").length(), 1, msg="drawing does not repeat the action")
      if tab == "files" {
        let arrivals = named(calls, "drive.browse").filter(fn(call) {
          text(Some(call.params), "act") == "at"
        })
        assert_eq(arrivals.length(), 1, msg="rebuilding or retaining the tab tells its directory once")
      }
    }
    assert_eq(release_times[0], release_times[1])
    assert_eq(release_times[0], release_times[2])
  }
}

///|
test "a chat info opener changes the page at release with the same inputs at any frame cadence" {
  let release_times : Array[Double] = []
  for hz in [0, 60, 120] {
    let t = wide_tester([], mode="chat-opener")
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="对话信息")
    t.run_for(@kit.pop_ms)
    let depth = app.nav.depth()
    release_times.push(info_release(t, "由「和 Ana 一起看新版的引导页」创建", hz, role=Link))
    assert_false(@sfdesk.chat_pops_open().0)
    opener_open(t)
    assert_eq(app.nav.depth(), depth)
    assert_eq(t.focused().map(fn(n) { (n.role, n.label) }), Some((TextField, "发消息")),
      msg="the opened chat receives its writing cursor at release")
    t.run_for(@ui.move_most_ms)
    opener_open(t)
    assert_eq(t.focused().map(fn(n) { (n.role, n.label) }), Some((TextField, "发消息")),
      msg="closing the info must not take the new chat's cursor away")
    assert_eq(app.nav.depth(), depth, msg="drawing does not add another page")
  }
  assert_eq(release_times[0], release_times[1])
  assert_eq(release_times[0], release_times[2])
}

///|
test "a chat info pull opens its URL at release once without waiting for a frame" {
  let release_times : Array[Double] = []
  for hz in [0, 60, 120] {
    let t = wide_tester([], mode="chat")
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="对话信息")
    t.run_for(@kit.pop_ms)
    release_times.push(info_release(t, "列表里的图片按需解码", hz, role=Link))
    assert_false(@sfdesk.chat_pops_open().0)
    assert_eq(t.opened(), ["https://github.com/acme/shop/pull/131"])
    t.run_for(@ui.move_most_ms)
    assert_eq(t.opened(), ["https://github.com/acme/shop/pull/131"], msg="drawing does not open the URL again")
  }
  assert_eq(release_times[0], release_times[1])
  assert_eq(release_times[0], release_times[2])
}
