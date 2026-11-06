// The lock waiting page in Home's place: its state follows the lock topic, and its actions belong to the workspace
// in view. These tests exercise the page through the shell on each screen, with either native input.

///|
test "the lock waiting page follows its pair state on each screen and with either input" {
  for case in [
    (390.0, 844.0, 2), (690.0, 840.0, 2), (1024.0, 768.0, 2),
    (390.0, 844.0, 0), (690.0, 840.0, 0), (1280.0, 800.0, 0),
  ] {
    let (w, h, platform) = case
    let at = "\{w} platform \{platform}"
    new_run()
    let state = @signals.signal("")
    let error = @signals.signal("")
    let asking = @signals.signal(false)
    let calls : Array[(String, Json)] = []
    let base = fixture("lock-waiting")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        if name == "lock.pair" || name == "lock.pairCode" {
          calls.push((name, params))
        } else {
          (base.call)(name, params, done)
        }
      },
      topic: fn(name, params) {
        let topic = (base.topic)(name, params)
        if name == "lock" {
          {
            ..topic,
            value: Some({
              "me": {
                "waiting": Json::boolean(true),
                "unsigned": Json::boolean(false),
                "pair": {
                  "state": Json::string(state.get()),
                  "left": Json::number(2.0),
                  "untilText": Json::string("14:05 前有效"),
                  "error": Json::string(error.get()),
                },
              },
            }),
            version: topic.version + 1,
          }
        } else if name == "doing" && asking.get() {
          {
            ..topic,
            value: Some({ "doing": [{ "call": "lock.pair", "stage": "running", "params": { "workspace": "ws1" } }] }),
            version: topic.version + 1,
          }
        } else {
          topic
        }
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
    t.frame()
    assert_true(t.find("等待批准此设备") is Some(_), msg=at)
    assert_true(t.find("发送批准请求") is Some(_), msg=at)
    t.tap_text("发送批准请求")
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(text(Some(calls[0].1), "workspace"), "ws1", msg=at)

    state.set("finding")
    asking.set(true)
    t.frame()
    assert_true(t.find("正在联系你的受信任设备") is Some(_), msg=at)
    assert_true(t.find("没收到？重新申请") is None, msg=at)
    asking.set(false)
    t.frame()
    assert_true(t.find("没收到？重新申请") is Some(_), msg=at)
    t.tap_text("没收到？重新申请")
    assert_eq(calls.length(), 2, msg=at)

    state.set("none")
    t.frame()
    assert_true(t.find("未找到在线的受信任设备：在你已获批的设备上打开 still.fail 后重试") is Some(_), msg=at)
    assert_true(t.find("发送批准请求") is Some(_), msg=at)

    error.set("配对超时")
    state.set("failed")
    t.frame()
    assert_true(t.find("配对超时") is Some(_), msg=at)
    assert_true(t.find("发送批准请求") is Some(_), msg=at)

    state.set("checking")
    t.frame()
    assert_true(t.find("输入你的受信任设备上显示的安全码") is Some(_), msg=at)
    assert_true(t.find("正在验证") is Some(_), msg=at)
    assert_true(t.find("重新获取安全码") is None, msg=at)
    t.type_text("123456")
    assert_eq(calls.length(), 2, msg=at)

    error.set("")
    state.set("wrong")
    t.frame()
    assert_true(t.find("安全码不对，还可以试 2 次") is Some(_), msg=at)
    assert_true(t.find("14:05 前有效") is Some(_), msg=at)
    assert_true(t.find("重新获取安全码") is Some(_), msg=at)
    error.set("显示安全码的设备已断开")
    t.frame()
    assert_true(t.find("显示安全码的设备已断开") is Some(_), msg=at)
  }
}

///|
test "the lock waiting page can retry a rejected code on each screen and with either input" {
  for case in [
    (390.0, 844.0, 2), (690.0, 840.0, 2), (1024.0, 768.0, 2),
    (390.0, 844.0, 0), (690.0, 840.0, 0), (1280.0, 800.0, 0),
  ] {
    let (w, h, platform) = case
    let at = "\{w} platform \{platform}"
    new_run()
    let attempts : Array[Json] = []
    let requests : Array[Json] = []
    let answers : Array[(Result[Json, Json]) -> Unit] = []
    let base = fixture("lock-code")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        if name == "lock.pairCode" {
          attempts.push(params)
          answers.push(done)
        } else if name == "lock.pair" {
          requests.push(params)
        } else {
          (base.call)(name, params, done)
        }
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
    assert_true(t.ime().0, msg=at)
    assert_eq(t.ime_action(), @hostapi.ime_action_number, msg=at)
    t.type_text("12-3 456")
    assert_eq(attempts.length(), 1, msg=at)
    assert_eq(text(Some(attempts[0]), "workspace"), "ws1", msg=at)
    assert_eq(text(Some(attempts[0]), "code"), "123456", msg=at)
    t.frame()
    assert_eq(attempts.length(), 1, msg=at)
    answers[0](Err(Json::string("rejected")))
    t.frame()
    assert_eq(t.ime().1, "", msg=at)
    t.type_text("123456")
    assert_eq(attempts.length(), 2, msg=at)
    assert_eq(text(Some(attempts[1]), "code"), "123456", msg=at)
    t.tap_text("重新获取安全码")
    t.frame()
    assert_eq(requests.length(), 1, msg=at)
    assert_eq(text(Some(requests[0]), "workspace"), "ws1", msg=at)
    assert_eq(t.ime().1, "", msg=at)
    t.type_text("123456")
    assert_eq(attempts.length(), 3, msg=at)
    // A late rejection of the previous attempt must not clear the new one, even when its digits are the same.
    answers[1](Err(Json::string("late rejection")))
    t.frame()
    assert_eq(t.ime().1, "123456", msg=at)
  }
}

///|
test "the lock waiting page leaves the workspace switcher and settings reachable on a small screen" {
  new_run()
  let src = fixture("lock-waiting")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  t.tap_text("星火工作室")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  t.tap_text("个人")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.workspace_in_view(src).0.map(fn(w) { w.id }), Some("ws2"))

  new_run()
  let src = fixture("lock-waiting")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.click(Button, label="设置")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Settings)
}

///|
test "the lock waiting page's approval request is reachable and pressable with the keyboard" {
  for w in [390.0, 690.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="lock-waiting", w~, h=800.0, platform=0)
    assert_true(t.query(Button, label="发送批准请求") is Some(_), msg=w.to_string())
    for _ in 0..<30 {
      if t.focused().map(fn(s) { s.label }) == Some("发送批准请求") {
        break
      }
      t.key(@ui.key_tab)
    }
    assert_eq(t.focused().map(fn(s) { s.label }), Some("发送批准请求"), msg=w.to_string())
    t.enter()
    assert_eq(named(calls, "lock.pair").length(), 1, msg=w.to_string())
  }
}

///|
test "resizing a waiting workspace across the three screens neither loses the page nor sends a request" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="lock-waiting", w=390.0, h=844.0, platform=0)
  for w in [690.0, 1280.0, 390.0] {
    t.resize(w, 844.0)
    t.frame()
    assert_true(t.find("等待批准此设备") is Some(_), msg=w.to_string())
    assert_true(t.find("发送批准请求") is Some(_), msg=w.to_string())
    assert_eq(named(calls, "lock.pair").length(), 0, msg=w.to_string())
  }
  t.tap_text("发送批准请求")
  assert_eq(named(calls, "lock.pair").length(), 1)
}

///|
test "the lock waiting page keeps the window's top row draggable" {
  for platform in [0, 3] {
    for w in [690.0, 1280.0] {
      let calls : Array[Made] = []
      let t = wide_tester(calls, mode="lock-waiting", w~, h=800.0, platform~, window_inset=true)
      t.run_for(@ui.move_most_ms)
      row_drags(t, "the lock waiting page", 400.0)
    }
  }
}
