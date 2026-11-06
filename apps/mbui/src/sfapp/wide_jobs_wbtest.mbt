// The desktop's services and jobs left up long (sfdesk open_jobs.mbt, OpenJobs.tsx): in 待处理's panel (the sidebar
// foot's count without the bell), each under its heading; a row leads to its chat.

///|
test "wide: 待处理's panel lists the jobs left up long under their heading, how long each has been up; a row goes to its chat" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home-jobs")
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  assert_true(t.find("开了很久的网页服务 · 1") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("Willow · 整理发布清单") is Some(_))
  assert_true(t.find("3 小时") is Some(_))
  t.tap_text("Willow · 整理发布清单")
  t.frame()
  let at = match app.nav.top() {
    Chat(r) => r.session
    _ => ""
  }
  assert_eq(at, "s-c1")
}

///|
test "wide: the jobs left up long light the bell until its panel has shown them: kept as it opens (prefs.set jobsSeen), still listed" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home-jobs")
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let seen = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "jobsSeen") is Some(_) })
  assert_eq(seen.length(), 1)
  assert_eq(field(field(Some(seen[0].params), "jobsSeen"), "ws1"), Some(Json::array([Json::string("ws1/st1/j-web")])))
  assert_true(t.find("开了很久的网页服务 · 1") is Some(_))
}

///|
test "wide: a long-running simulator and remote view can be stopped from the list" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home-jobs-screens", h=1000.0)
  t.host_says_finger(Some(true))
  t.frame()
  t.click(Button, label="待处理")
  t.frame()
  t.click(Button, label="关闭 Demo iPhone · iOS 27.2")
  assert_eq(named(calls, "screen.close").length(), 1)
  assert_eq(named(calls, "screen.close")[0].params, { "station": "ws1/st1", "screen": "simulator:A" })
  t.click(Button, label="断开 Willow 的桌面")
  assert_eq(named(calls, "screen.endView").length(), 1)
  assert_eq(named(calls, "screen.endView")[0].params, { "station": "ws1/st1", "screen": "desktop", "view": "v1" })
}
