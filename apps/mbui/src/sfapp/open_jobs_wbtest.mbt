// What is left up long at the top of Home's list (sheets.mbt open_jobs_node): a finger that goes on to scroll from a
// row presses nothing on its way, as a chat's row; a row tapped leads to its chat, its stop asks the core; a group of
// more than four folded under 还有 N 个 until that is pressed.

///|
/// Home on a phone (390 by 844, touch) over the home fixture's chats, with `long` what is left up long; the calls asked
/// of the core into `calls`, none answered.
fn open_jobs_tester(long : Json, calls? : Array[(String, Json)] = []) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      if name == "longJobs" {
        { ..got, value: Some(long) }
      } else {
        got
      }
    },
    call: fn(name, params, _) { calls.push((name, params)) },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
/// The ripples over the row of `words` (its last drawn) as a finger goes down on it and slowly on up the list, 6 a move
/// (past the slop at the second), each move drawn as it comes; with where the words are then.
fn scrolled_from(words : String) -> Array[(Int, Double)] {
  let t = open_jobs_tester(@sffixture.long_screens_view())
  let (x, y) = t.find_last(words).unwrap()
  let seen = []
  t.touch(0, x, y)
  t.draw()
  seen.push((ripples_at(t, x, y), y))
  for i in 1..=8 {
    t.advance(@ui.input_step_ms)
    t.touch(1, x, y - i.to_double() * 6.0)
    t.draw()
    let (_, now) = t.find_last(words).unwrap()
    seen.push((ripples_at(t, x, now), now))
  }
  t.touch(2, x, y - 48.0)
  t.draw()
  seen
}

///|
test "a finger that goes on to scroll from what is left up long ripples nothing on its way, as from a chat's row" {
  for words in ["Willow · 整理发布清单 · 3 小时", "整理发布清单"] {
    let seen = scrolled_from(words)
    // (the list went with the finger)
    assert_true(seen[seen.length() - 1].1 < seen[0].1 - 20.0)
    assert_eq(seen.map(fn(s) { s.0 }), Array::make(9, 0))
  }
}

///|
test "what is left up long, a row tapped: its chat, the service's page over it" {
  let t = open_jobs_tester(@sffixture.long_screens_view())
  t.tap_text("Willow · 整理发布清单 · 3 小时")
  match app.nav.top() {
    Service(station, id) => assert_eq((station, id), ("ws1/st1", "j-web"))
    _ => fail("no service's page")
  }
}

///|
test "what is left up long, a task run here for another station's chat: that chat, on its own station" {
  // (Studio running a task for a chat of another station: its row opened Studio's chat by that one's id, a chat Studio
  // has not, and the page waited for good; 2026-11-12)
  let job = match @sffixture.long_job() {
    Object(m) => m.copy()
    _ => {}
  }
  job["service"] = Json::boolean(false)
  job["chat"] = { "id": "s-elsewhere", "title": "修登录", "archived": false, "station": "ws1/st2" }
  job["whereText"] = Json::string("Studio · 修登录 · 来自 Willow")
  let t = open_jobs_tester({ "groups": [{ "key": "jobs", "head": "长时间运行的后台任务 · 1", "jobs": [Json::object(job)] }], "lit": false, "ids": [] })
  t.tap_text("Studio · 修登录 · 来自 Willow · 3 小时")
  match app.nav.top() {
    Chat(r) => assert_eq((r.station, r.session, r.title), ("ws1/st2", "s-elsewhere", "修登录"))
    _ => fail("no chat")
  }
}

///|
test "what is left up long, a row's stop: the core asked, its row not opened" {
  let calls = []
  let t = open_jobs_tester(@sffixture.long_screens_view(), calls~)
  guard t.query(Button, label="停止") is Some(s) else { fail("no stop") }
  let (x, y, w, h) = s.rect
  calls.clear()
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(calls.map(fn(c) { c.0 }), ["job.stop"])
  assert_true(@sfbase.doing("job-stop/ws1/st1/j-web"))
  assert_eq(app.nav.depth(), 1)
}

///|
test "what is left up long, a group of five: three shown, the rest under 还有 2 个 until it is pressed" {
  let jobs : Array[Json] = []
  for i in 0..<5 {
    jobs.push(
      @sffixture.long_screen("screen:simulator:" + i.to_string(), "模拟器 " + i.to_string(), "Willow · iOS 模拟器", "5 小时", "screen.close", "simulator:" + i.to_string(), "", "关闭"),
    )
  }
  let t = open_jobs_tester({ "groups": [{ "key": "simulators", "head": "长时间开着的模拟器 · 5", "jobs": Json::array(jobs) }], "lit": true })
  assert_true(t.find("模拟器 2") is Some(_))
  assert_true(t.find("模拟器 3") is None)
  t.tap_text("还有 2 个")
  assert_true(t.find("模拟器 4") is Some(_))
  assert_true(t.find("还有 2 个") is None)
}

///|
test "what is left up long, a long name and where it is: cut short on their lines, the row and its stop within the window" {
  let job = match @sffixture.long_job() {
    Object(m) => m.copy()
    _ => {}
  }
  job["name"] = Json::string("CFT local stack for mail mode screenshots and the rest of a long name")
  job["whereText"] = Json::string("tokyo-mac-studio-0-vm · Review 邮件权限 PR #5033 · and more of where it is")
  let t = open_jobs_tester({ "groups": [{ "key": "services", "head": "长时间运行的网页服务 · 1", "jobs": [Json::object(job)] }], "lit": true })
  guard t.query(Button, label="停止") is Some(stop) else { fail("no stop") }
  let (sx, _, sw, _) = stop.rect
  // (its stop in the window, at the row's end)
  assert_true(sx + sw <= 390.0)
  // (no glyph of its words past where its stop begins)
  let past = t.glyph_clips().filter(fn(g) { g.0.1 > 40.0 && g.0.1 < 200.0 && g.0.2 > sx && g.0.0 < sx + sw && g.0.0 > 40.0 })
  assert_eq(past.length(), 0)
}

///|
test "what is left up long is waited for by the first page: there with the list, not slid in under it" {
  new_run()
  let client = @core.Client::new(fn(_) { () })
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name != "longJobs" {
        return (base.topic_read)(name, params)
      }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "longJobs" {
        client.follow_topic(name, params~).waiting
      } else {
        (base.waits)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  t.run_for(@sf.local_ms)
  // (the list answered, what is under it not yet: the page not shown)
  assert_true(!words_seen(t, "整理发布清单"))
  guard client.peek_topic("longJobs", params={ "scope": "ws1" }) is Some(sub) else { fail("no longJobs reader") }
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": @sffixture.long_screens_view() })
  t.draw()
  let row = "Willow · 整理发布清单 · 3 小时"
  assert_true(words_seen(t, row), msg="shown with the list")
  let (_, y0) = t.drawn_of(row).unwrap()
  t.run_for(@ui.move_most_ms)
  let (_, y1) = t.drawn_of(row).unwrap()
  assert_true((y1 - y0).abs() < 0.5, msg="moved from \{y0} to \{y1}")
}
