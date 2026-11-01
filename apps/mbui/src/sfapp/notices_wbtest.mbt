// Notifications (notices.mbt) over the fixture's chats, the core's `notify` made up here and the system a fake that
// keeps what it is asked: a notice shown once it is taken, tapped it opens its chat at its message, the chat on top
// takes its notification off, the system asked once and told what it allows, pushes registered.

///|
/// What the fake system was asked.
priv struct FakeSystem {
  shown : Array[(String, String, String, String)]
  cancelled : Array[String]
  mut permission : String
  mut asks : Int
  mut answer : Bool?
  mut opened : String
  mut token : String
  mut service : String
}

///|
fn fake_system() -> FakeSystem {
  { shown: [], cancelled: [], permission: "granted", asks: 0, answer: None, opened: "", token: "", service: "fcm" }
}

///|
fn use_system(s : FakeSystem) -> Unit {
  notice_host.val = {
    show: fn(tag, title, body, opens) { s.shown.push((tag, title, body, opens)) },
    cancel: fn(tag) { s.cancelled.push(tag) },
    permission: fn() { s.permission },
    ask: fn() {
      s.asks += 1
      true
    },
    answer: fn() {
      let a = s.answer
      s.answer = None
      a
    },
    opened: fn() {
      let o = s.opened
      s.opened = ""
      o
    },
    token: fn() { s.token },
    service: fn() { s.service },
  }
}

///|
/// The notice of a chat of the fixture's (首页的列表改成按天分组, ws1/st1 s-c2): its card waits, message 2.
let a_notice : Json = {
  "id": "n7",
  "kind": "wait",
  "station": "ws1/st1",
  "workspace": "ws1",
  "stationId": "st1",
  "session": "s-c2",
  "thread": 8,
  "seq": 2,
  "title": "首页的列表改成按天分组",
  "body": "待你决定 · 分组的标题用相对日期还是具体日期？",
  "tag": "ws1/st1/s-c2",
  "url": "/o/ws1/st1/s-c2?message=2",
  "at": 1790000000000.0,
}

///|
/// Home over the fixture, the core's `notify` as `notify` (the device's) and its notices to show as `show`, every
/// call kept (and answered as the core would, where it says).
fn notify_core(
  calls : Array[Made],
  sys : FakeSystem,
  notify? : Ref[Json] = Ref({ "on": true, "asked": true, "push": true, "show": [] }),
  show? : Array[Json] = [],
  env? : Array[(String, String)] = [],
) -> @ui.Tester {
  new_run()
  use_system(sys)
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match name {
        "notify" =>
          if params.contains("workspace") {
            { value: Some({ "show": Json::array(show) }), error: None, version: show.length() }
          } else {
            { value: Some(notify.val), error: None, version: 1 }
          }
        _ => (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "notice.claim" => done(Ok({ "show": true }))
        "link.parse" => done(Ok({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "s-c2" }))
        // left for the test to answer
        "notify.set" | "notify.permission" | "push.register" | "push.unregister" | "notice.bring" => ()
        _ => (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, env~, platform=2)
  t
}

///|
test "a notice the core says to show: taken, then shown once in the system, as the chat's" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys, show=[a_notice])
  assert_eq(named(calls, "notice.claim").length(), 1)
  assert_eq(sys.shown.length(), 1)
  let (tag, title, body, opens) = sys.shown[0]
  assert_eq(tag, "ws1/st1/s-c2")
  assert_eq(title, "首页的列表改成按天分组")
  assert_true(body.has_prefix("待你决定"))
  assert_eq(opens, "/o/ws1/st1/s-c2?message=2\n2")
  // frames on: not taken again
  t.frame()
  assert_eq(named(calls, "notice.claim").length(), 1)
  assert_eq(sys.shown.length(), 1)
  // (not idle yet: a spinner turns for ever (sf/icons.mbt), till mbui#25)
}

///|
test "tapped, the notice's chat opens over Home at its message, which flashes; its notification goes" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys, show=[a_notice])
  sys.opened = "/o/ws1/st1/s-c2?message=2\n2"
  t.frame()
  // its chat slid in
  t.run_for(@ui.move_most_ms)
  let parsed = named(calls, "link.parse")
  assert_eq(parsed.length(), 1)
  assert_true(parsed[0].params.stringify().contains("/o/ws1/st1/s-c2?message=2"))
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => {
      assert_eq(r.station, "ws1/st1")
      assert_eq(r.session, "s-c2")
    }
    _ => fail("not the chat")
  }
  assert_true(t.find("好的，我来处理。") is Some(_))
  // gone to: nothing left to go to, and it was lit
  assert_true(go_tos.is_empty())
  assert_true(sys.cancelled.contains("ws1/st1/s-c2"))
  // back: Home
  app.nav.pop() |> ignore
  assert_eq(app.nav.depth(), 1)
  // it slides off from the frame that takes it
  t.draw()
  t.run_for(@ui.move_most_ms)
  // (not idle yet: the bottom bar is still on its spring (bar.mbt), till mbui#25 declares its end)
}

///|
test "共享调试's notification tapped (AdbShare.java): settings' 共享调试 opens over Home" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys)
  sys.opened = "settings:adb:"
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "link.parse").length(), 0)
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.top() == Setting(@settings.Route::AdbShare("")))
  // tapped again on that page: nothing more opens
  sys.opened = "settings:adb:"
  t.frame()
  assert_eq(app.nav.depth(), 2)
}

///|
test "tapped while a file is open over the window, the file is put down and the notice's chat shows" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys, show=[a_notice])
  let a : Attachment = {
    name: "界面草图.png",
    path: "uploads/fx/界面草图.png",
    size: 1024.0,
    width: 800.0,
    height: 600.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  open_preview("ws1/st1", "s-c1", a)
  t.frame()
  assert_true(@sfbase.preview_open())
  sys.opened = "/o/ws1/st1/s-c2?message=2\n2"
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.preview_open())
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c2")
    _ => fail("not the chat")
  }
  assert_true(t.find("好的，我来处理。") is Some(_))
}

///|
test "put away where the app goes on (a desktop's tray, minimized), its notices still come; behind for good, left" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let show : Array[Json] = []
  let t = notify_core(calls, sys, show~)
  assert_eq(notice_state.following, "ws1")
  // put away, the host still running it (Windows' notification area): followed, a notice come meanwhile shown
  t.app_state(false, false, awake=true)
  assert_true(@ui.app_awake())
  assert_eq(notice_state.following, "ws1")
  show.push(a_notice)
  t.frame()
  assert_eq(named(calls, "notice.claim").length(), 1)
  assert_eq(sys.shown.length(), 1)
  assert_eq(sys.shown[0].0, "ws1/st1/s-c2")
  // behind for good (a phone's app behind another: its frames stop): no longer followed
  t.app_state(false, false)
  assert_true(!@ui.app_awake())
  assert_eq(notice_state.following, "")
}

///|
test "a message gone to flashes, in and out as the Android app's, nothing of it after" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys)
  sys.opened = "/o/ws1/st1/s-c2?message=2\n2"
  // the chat pushed and put in place, then gone to: its flash in, held (the middle of its hold), then gone
  t.draw()
  t.run_for(@ui.move_most_ms)
  // (the middle of its hold, from when it began: its end less its length; now, where that is gone by)
  let held = flash_rest() - flash_ms + (flash_in_ms + flash_held_ms) / 2.0
  if held > t.time() {
    t.run_for(held - t.time())
  }
  assert_eq(@sfpages.flashing_now.val.0, "ts2")
  assert_true(@sfpages.flashing_now.val.1 > 0.99)
  t.run_for(flash_ms)
  t.draw()
  assert_eq(@sfpages.flashing_now.val.1, 0.0)
  t.assert_idle()
}

///|
test "a message gone to is lit whole as a band: across the list from edge to edge, square, half the gaps over and under it" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys)
  sys.opened = "/o/ws1/st1/s-c2?message=2\n2"
  t.draw()
  t.run_for(@ui.move_most_ms)
  let held = flash_rest() - flash_ms + (flash_in_ms + flash_held_ms) / 2.0
  if held > t.time() {
    t.run_for(held - t.time())
  }
  let ground = @sf.theme().p.accent_bg
  let bands = t.drawn_rect_corners().filter(fn(r) { r.4 >> 8 == ground >> 8 && (r.4 & 0xFFL) != 0L })
  assert_eq(bands.length(), 1)
  let (x, _, w, h, _, corners) = bands[0]
  assert_true(x.abs() < 0.5 && (w - 390.0).abs() < 0.5 && h > 0.0)
  assert_eq(corners, (0.0, 0.0, 0.0, 0.0))
}

///|
test "with motion reduced, a message gone to is lit whole for its flash's time, then not: no fade" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys, env=[("MBUI_REDUCE_MOTION", "1")])
  sys.opened = "/o/ws1/st1/s-c2?message=2\n2"
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfpages.flashing_now.val, ("ts2", 1.0))
  t.run_for(flash_ms)
  assert_eq(@sfpages.flashing_now.val.1, 0.0)
}

///|
test "the system told what it allows; asked once when it never was, with notifications on" {
  let calls : Array[Made] = []
  let sys = fake_system()
  sys.permission = "ask"
  let t = notify_core(calls, sys, notify=Ref({ "on": true, "asked": false, "push": true, "show": [] }))
  let told = named(calls, "notify.permission")
  assert_eq(told.length(), 1)
  assert_true(told[0].params.stringify().contains("\"default\""))
  assert_eq(sys.asks, 1)
  let set = named(calls, "notify.set")
  assert_eq(set.length(), 1)
  assert_true(set[0].params.stringify().contains("\"asked\":true"))
  // allowed: told so
  sys.answer = Some(true)
  t.frame()
  let after = named(calls, "notify.permission")
  assert_eq(after.length(), 2)
  assert_true(after[1].params.stringify().contains("\"granted\""))
  // hidden and shown again: told again; not asked again
  t.app_state(false, false)
  t.app_state(true, true)
  assert_eq(named(calls, "notify.permission").length(), 3)
  assert_eq(sys.asks, 1)
  // (not idle yet: a spinner turns for ever (sf/icons.mbt), till mbui#25)
}

///|
test "pushes: none registered without a token, taken off while off; a token registered" {
  let calls : Array[Made] = []
  let sys = fake_system()
  notify_core(calls, sys, notify=Ref({ "on": true, "asked": true, "push": true, "show": [] })) |> ignore
  assert_eq(named(calls, "push.register").length(), 0)
  assert_eq(named(calls, "push.unregister").length(), 0)
  let calls2 : Array[Made] = []
  let sys2 = fake_system()
  notify_core(calls2, sys2, notify=Ref({ "on": false, "asked": true, "push": false, "show": [] })) |> ignore
  assert_eq(named(calls2, "push.unregister").length(), 1)
  let calls3 : Array[Made] = []
  let sys3 = fake_system()
  sys3.token = "tok-1"
  notify_core(calls3, sys3, notify=Ref({ "on": true, "asked": true, "push": true, "show": [] })) |> ignore
  let reg = named(calls3, "push.register")
  assert_eq(reg.length(), 1)
  assert_true(reg[0].params.stringify().contains("\"token\":\"tok-1\""))
  assert_true(reg[0].params.stringify().contains("\"kind\":\"fcm\""))
  // iOS's: an APNs token, said with which of APNs' servers knows it
  let calls4 : Array[Made] = []
  let sys4 = fake_system()
  sys4.token = "ab12"
  sys4.service = "apns-sandbox"
  notify_core(calls4, sys4, notify=Ref({ "on": true, "asked": true, "push": true, "show": [] })) |> ignore
  let reg = named(calls4, "push.register")
  assert_eq(reg.length(), 1)
  assert_eq(reg[0].params, { "kind": "apns", "token": "ab12", "sandbox": true })
}

///|
test "settings: notifications switched off on 通知's page, the core keeps it; on again, the system asked" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let notify : Ref[Json] = Ref({ "on": true, "asked": true, "push": true, "show": [] })
  let t = notify_core(calls, sys, notify~)
  open_setting("home")
  t.draw()
  t.run_for(@ui.move_most_ms)
  // the list's row (below the fold on a 844 high screen: the page at its end) opens their page
  t.scroll_to_end()
  t.draw()
  t.tap_text("通知")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Notifications))
  // its banners' tile switches them, as the core keeps it
  t.tap_text("横幅")
  let set = named(calls, "notify.set")
  assert_eq(set.length(), 1)
  assert_true(set[0].params.stringify().contains("\"on\":false"))
  // switched at once, a spinner while the core has not answered: not switched again meanwhile
  t.tap_text("横幅")
  assert_eq(named(calls, "notify.set").length(), 1)
  notify.val = { "on": false, "asked": true, "push": false, "show": [] }
  (set[0].done)(Ok(notify.val))
  t.draw()
  assert_eq(named(calls, "push.unregister").length(), 1)
  let asks = sys.asks
  t.tap_text("横幅")
  assert_eq(sys.asks, asks + 1)
  let on = named(calls, "notify.set")
  assert_true(on[on.length() - 1].params.stringify().contains("\"on\":true"))
  // refused by the system: a toast says where to allow them
  (on[on.length() - 1].done)(Err({ "code": "x", "message": "坏了" }))
  assert_eq(app.toast.get().words, "无法开启通知：坏了")
  sys.answer = Some(false)
  t.frame()
  assert_eq(app.toast.get().words, "在系统设置里允许 still.fail 发通知")
  let told = named(calls, "notify.permission")
  assert_true(told[told.length() - 1].params.stringify().contains("\"denied\""))
  // (not idle yet: the bottom bar is still on its spring (bar.mbt), till mbui#25 declares its end)
}

///|
test "settings: usage statistics and error reports switched off on this device, on again; no row where none are sent" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let notify : Ref[Json] = Ref({ "on": true, "asked": true, "push": true, "show": [] })
  let t = notify_core(calls, sys, notify~)
  // (a host that sends none: a build without PostHog's key, macOS, the web)
  open_setting("about")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.scroll_to_end()
  t.draw()
  assert_true(t.find("发送使用统计和错误报告") is None)
  // Android's (Crashes.reporting, kept in the app's prefs): on until turned off
  let on = Ref(true)
  let told : Array[Bool] = []
  reporting_host.set(Some({ get: fn() { on.val }, set: fn(v) { told.push(v); on.val = v } }))
  t.draw()
  t.scroll_to_end()
  t.draw()
  assert_true(t.find("不会包含你的聊天内容") is Some(_))
  t.click(Switch, label="发送使用统计和错误报告")
  // off: what Crashes.send then sends is nothing (Crashes.java: !reporting, no batch goes)
  assert_eq(told, [false])
  assert_true(!on.val)
  t.draw()
  t.click(Switch, label="发送使用统计和错误报告")
  assert_eq(told, [false, true])
  reporting_host.set(None)
}

///|
test "pushes: a token come after the start registered then, a new one again; the same one not twice" {
  let calls : Array[Made] = []
  let sys = fake_system()
  let t = notify_core(calls, sys)
  assert_eq(named(calls, "push.register").length(), 0)
  // the push service's first token, given once the app runs (Push.java: FirebaseMessaging's token)
  sys.token = "tok-1"
  t.frame()
  let reg = named(calls, "push.register")
  assert_eq(reg.length(), 1)
  assert_true(reg[0].params.stringify().contains("\"token\":\"tok-1\""))
  t.frame()
  assert_eq(named(calls, "push.register").length(), 1)
  // a new token (PushService.onNewToken)
  sys.token = "tok-2"
  t.frame()
  let reg = named(calls, "push.register")
  assert_eq(reg.length(), 2)
  assert_true(reg[1].params.stringify().contains("\"token\":\"tok-2\""))
}
