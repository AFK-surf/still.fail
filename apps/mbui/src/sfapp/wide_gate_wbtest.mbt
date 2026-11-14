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
    topic_read: fn(name, params) {
      let topic = base.topic(name, params).get().snapshot()
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

///|
/// The wide frame on chat 整理发布清单, this device made to wait in the workspace's lock and let in again as `waiting`
/// says; the calls made, in turn.
fn lock_wait_tester(waiting : @signals.Signal[Bool], calls : Array[String]) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name)
      (base.call)(name, params, done)
    },
    topic_read: fn(name, params) {
      let topic = base.topic(name, params).get().snapshot()
      if name == "lock" && waiting.get() {
        {
          ..topic,
          value: Some({ "me": { "waiting": Json::boolean(true), "unsigned": Json::boolean(false) } }),
          version: topic.version + 1,
        }
      } else {
        topic
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
}

///|
/// The wide frame on chat 整理发布清单, then on chat 首页的列表改成按天分组 put in its place (the one before it in the
/// history); where the field to write in is.
fn lock_wait_two(waiting : @signals.Signal[Bool], calls : Array[String]) -> (@ui.Tester, Double, Double) raise {
  let t = lock_wait_tester(waiting, calls)
  t.frame()
  @sfbase.open_page(Chat(over_chat))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }))
  let (fx, fy, fw, fh) = t.rect_of("发消息").unwrap()
  (t, fx + fw / 2.0, fy + fh / 2.0)
}

///|
/// What has the focus, as a person's assistive reader says it.
fn focus_said(t : @ui.Tester) -> String {
  t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
}

///|
test "wide: while the device waits in the lock its page in the pages' place, the chat under it kept: nothing of it pressed or typed into, the chat not let go; let in, the same chat, the focus back in its field" {
  let waiting = @signals.signal(false)
  let calls : Array[String] = []
  let (t, fx, fy) = lock_wait_two(waiting, calls)
  let pages = app.nav.pages()
  let stay = app.nav.top_stay()
  let left = @sfbase.left_said.get()
  waiting.set(true)
  t.frame()
  assert_true(t.find("等待批准此设备") is Some(_))
  assert_true(t.find("好的，我来处理。") is None)
  // (what had the focus gone with the chat; where its field was, the lock's page: nothing of the chat's pressed)
  assert_eq(focus_said(t), "none")
  let made = calls.length()
  t.tap(fx, fy)
  t.frame()
  assert_eq(focus_said(t), "none")
  assert_eq(calls.length(), made, msg="\{Repr(calls[made:])}")
  // (what is typed meanwhile goes into nothing of the chat's)
  t.type_text("zq")
  t.frame()
  assert_true(t.find("等待批准此设备") is Some(_))
  assert_true(app.nav.pages() == pages)
  assert_eq(app.nav.top_stay(), stay)
  // (let in: the same chat, never let go and made again)
  waiting.set(false)
  t.frame()
  assert_true(t.find("等待批准此设备") is None)
  assert_true(t.find("好的，我来处理。") is Some(_))
  assert_true(app.nav.pages() == pages)
  assert_eq(app.nav.top_stay(), stay)
  assert_eq(@sfbase.left_said.get(), left)
  // (the focus back where it was as the lock came, nothing typed meanwhile in it; typed now, in it)
  assert_eq(focus_said(t), "TextField 发消息")
  assert_eq(t.ime().1, "")
  t.type_text("zq")
  t.frame()
  assert_eq(t.ime().1, "zq")
}

///|
test "wide: back while the device waits in the lock goes back in the history as it does let in, its page staying in the pages' place" {
  let waiting = @signals.signal(false)
  let calls : Array[String] = []
  let (t, _, _) = lock_wait_two(waiting, calls)
  waiting.set(true)
  t.frame()
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat({ session: "s-c1", .. }))
  assert_true(t.find("等待批准此设备") is Some(_))
  assert_true(t.find("做完了：") is None)
}

///|
test "wide: the focus elsewhere than the chat as the device came to wait in the lock (the sidebar's edge, by Tab): there again as it is let in, none taken by the chat" {
  let waiting = @signals.signal(false)
  let calls : Array[String] = []
  let (t, _, _) = lock_wait_two(waiting, calls)
  t.key(@ui.key_tab)
  t.frame()
  let was = focus_said(t)
  assert_true(was.has_prefix("Button "), msg=was)
  waiting.set(true)
  t.frame()
  waiting.set(false)
  t.frame()
  assert_eq(focus_said(t), was)
}

///|
test "wide: nothing with the focus as the device came to wait in the lock (文件, no field): none taken as it is let in" {
  let waiting = @signals.signal(false)
  let calls : Array[String] = []
  let t = lock_wait_tester(waiting, calls)
  t.frame()
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_said(t), "none")
  waiting.set(true)
  t.frame()
  waiting.set(false)
  t.frame()
  assert_true(app.nav.top() is Files)
  assert_eq(focus_said(t), "none")
}

///|
test "wide: the chat with the focus in its field put out of the stack while the device waits in the lock (文件 put in its place): let in, the focus not back in the chat gone, nothing of 文件's given it" {
  let waiting = @signals.signal(false)
  let calls : Array[String] = []
  let (t, _, _) = lock_wait_two(waiting, calls)
  assert_eq(focus_said(t), "TextField 发消息")
  waiting.set(true)
  t.frame()
  app.nav.replace(Files)
  t.frame()
  waiting.set(false)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Files)
  assert_true(t.find("好的，我来处理。") is None)
  assert_eq(focus_said(t), "none")
  assert_false(t.ime().0)
}

///|
test "Duo: 发送批准请求 pressed on the waiting page is taken, the system's bars handed all the while" {
  new_run()
  let calls : Array[String] = []
  let base = fixture("lock-waiting")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name)
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=669.0, h=951.0, platform=1, nav_able=true)
  t.set_rows_on_pixels(true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":82,\"bottom\":34,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  // (none handed to the host in a frame would take the app's view out of the tabs, the finger on it never told it went up)
  let handed = fn() { !t.nav_said().contains("\"groups\":[]") }
  assert_true(handed())
  let b = t.words().filter(fn(n) { n.0 == "发送批准请求" })[0]
  let (x, y) = (b.1 + b.3 / 2.0, b.2 + b.4 / 2.0)
  t.press_at(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(handed())
  t.release(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(handed())
  assert_true(calls.contains("lock.pair"), msg="\{Repr(calls)}")
}

///|
/// One of the system's bars' floating controls (a native button at a box of the app's: rail_native.mbt
/// native_workspace_placed) by its id: where it is.
fn floating_at(t : @ui.Tester, id : String) -> (Double, Double, Double, Double)? raise {
  guard @json.parse(t.nav_said()) is Object(bar) else { fail("no bar") }
  guard bar.get("floating") is Some(Array(items)) else { return None }
  for i in items {
    let f = Some(i)
    if text(field(f, "item"), "id") == id {
      return Some((number(f, "x"), number(f, "y"), number(f, "w"), number(f, "h")))
    }
  }
  None
}

///|
test "Duo: while the device waits in the lock the workspace's button is in the system's glass over the waiting page (the sidebar not shown), and another workspace chosen from it is the one in view" {
  new_run()
  let src = fixture("lock-waiting")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=669.0, h=951.0, platform=1, nav_able=true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":82,\"bottom\":34,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("等待批准此设备") is Some(_))
  guard floating_at(t, "workspace-switch") is Some((x, y, w, h)) else { fail("no workspace-switch in the bars: \{t.nav_said()}") }
  // under the status bar, in from the left, over the page's words
  let (_, ty, _, _) = t.rect_of("等待批准此设备").unwrap()
  assert_true(y >= 82.0 && x > 0.0 && w > 0.0 && h > 0.0 && y + h <= ty, msg="\{x} \{y} \{w} \{h} over the title at \{ty}")
  t.post(@hostapi.system_channel, "{\"nav\":\"workspace-switch\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  t.tap_text("个人")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.workspace_in_view(src).0.map(fn(w) { w.id }), Some("ws2"))
}

///|
test "wide: while the device looks for its trusted devices, 没收到？重新申请 under it asks again at once (a trusted device opened and nothing came up)" {
  new_run()
  let base = fixture("chat")
  let calls : Array[String] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name)
      (base.call)(name, params, done)
    },
    topic_read: fn(name, params) {
      let topic = base.topic(name, params).get().snapshot()
      if name == "lock" {
        {
          ..topic,
          value: Some({
            "me": {
              "waiting": Json::boolean(true),
              "unsigned": Json::boolean(false),
              "pair": { "state": Json::string("finding") },
            },
          }),
          version: topic.version + 1,
        }
      } else {
        topic
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.frame()
  assert_true(t.find("正在联系你的受信任设备") is Some(_))
  t.tap_text("没收到？重新申请")
  t.frame()
  assert_true(calls.contains("lock.pair"), msg="\{Repr(calls)}")
}

///|
test "a waiting device's code approved, no station having taken it yet: the code put away, its sentence said, not the done words" {
  new_run()
  let said = "批准设备 Pixel 9：已记下，等 Willow 上线后生效"
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
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  assert_true(t.ime().0)
  t.type_text("123456")
  assert_eq(answers.length(), 1)
  answers[0](
    Ok({
      "t": "approved",
      "workspaces": ["ws1"],
      "failed": [],
      "pending": { "id": "p9", "text": said, "state": "waiting", "stations": ["Willow"] },
    }),
  )
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.toast_words(), said)
  assert_false(t.ime().0)
  assert_true(t.find(said) is Some(_))
}
