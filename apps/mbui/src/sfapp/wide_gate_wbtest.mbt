// The page for a device waiting to be confirmed in the workspace's lock (sfpages' lock_wait.mbt; cloud/Security.tsx
// SecurityWaiting, mobile/Security.tsx SecurityWaitingScreen): in the page's place, beside the rail on the wide frame,
// under Home's bar laid out Small; the web's desktop page with keyboard and mouse, its mobile screen with touch.

///|
test "a waiting device enters a security code on the digits keyboard and approval puts it away" {
  new_run()
  let approved = @signals.signal(false)
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let base = fixture("lock-code")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "lock.pairCode" {
        answers.push(done)
      } else {
        (base.call)(name, params, done)
      }
    },
    topic: fn(name, params) {
      let topic = (base.topic)(name, params)
      if name == "lock" && approved.get() {
        {
          ..topic,
          value: Some({ "me": { "waiting": Json::boolean(false), "unsigned": Json::boolean(false) } }),
          version: topic.version + 1,
        }
      } else {
        topic
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  assert_true(t.find("等待批准此设备") is Some(_))
  assert_true(t.ime().0)
  assert_eq(t.ime_action(), @hostapi.ime_action_number)
  t.type_text("123456")
  assert_eq(answers.length(), 1)
  // Approval can reach the page before the call's answer.
  approved.set(true)
  t.frame()
  assert_true(t.find("等待批准此设备") is None)
  assert_false(t.ime().0)
  answers[0](Ok(Json::object({})))
}

///|
test "wide: a device waiting in the workspace's lock sees 等待批准此设备 in the page's place, centred in it, with 发送批准请求" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="lock-waiting")
  t.frame()
  let (x, y, w, _) = t.rect_of("等待批准此设备").unwrap()
  assert_true(t.find("发送批准请求") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // in the middle of what the rail leaves, 110 and the shield (40) and 14 down
  let mid = x + w / 2.0
  let page_mid = (@sfdesk.wide.page_from + 1280.0) / 2.0
  assert_true((mid - page_mid).abs() <= 1.0, msg="\{mid} \{page_mid}")
  assert_true(y >= 110.0 + 40.0, msg=y.to_string())
}

///|
test "a device waiting in the lock, every tier on a touch device and on a computer: one page, the web's mobile screen on touch (in the middle of its height), its desktop page on a computer (110 down)" {
  // (platform, the window, the size classes its host says ("": none))
  for p in [
    (2, 390.0, 844.0, "compact", "medium"),
    (0, 500.0, 800.0, "", ""),
    (2, 690.0, 840.0, "medium", "medium"),
    (0, 720.0, 800.0, "", ""),
    (2, 1024.0, 768.0, "expanded", "medium"),
    (0, 1280.0, 800.0, "", ""),
  ] {
    let (platform, w, h, width, height) = p
    let at = "platform \{platform} \{w}"
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="lock-waiting", w~, h~, platform~)
    if width != "" {
      say_room(t, width, height)
    }
    t.frame()
    let (_, y, _, th) = t.rect_of("等待批准此设备").unwrap()
    assert_true(t.find("发送批准请求") is Some(_), msg=at)
    if platform == 2 {
      // the column in the middle of the page's height: the title well down it
      assert_true(y + th / 2.0 > h * 0.3, msg="\{at}: \{y}")
    } else {
      // 110 down, then the shield (40) and 14
      assert_true(y >= 110.0 + 40.0 && y < h * 0.3, msg="\{at}: \{y}")
    }
  }
}
