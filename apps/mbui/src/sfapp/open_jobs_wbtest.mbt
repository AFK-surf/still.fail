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
fn scrolled_from(words : String) -> Array[(Int, Double)] raise {
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
