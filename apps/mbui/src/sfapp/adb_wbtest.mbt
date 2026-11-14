// 共享调试's page (settings/station_parts.mbt adb_settings) over the settings' fixture, its phone as the test's host says it
// (the native calls of the app's Android: AdbShare.java).

///|
/// The phone as AdbShare.java's adb.phone answers it.
fn adb_phone_of(
  supported? : Bool = true,
  developer? : Bool = true,
  wireless? : Bool = false,
  wifi? : Bool = true,
  can_switch? : Bool = false,
  refused? : Bool = false,
) -> Json {
  {
    "supported": Json::boolean(supported),
    "developer": Json::boolean(developer),
    "wireless": Json::boolean(wireless),
    "wifi": Json::boolean(wifi),
    "canSwitch": Json::boolean(can_switch),
    "switchRefused": Json::boolean(refused),
  }
}

///|
/// The native calls asked so far by `name`.
fn asked_native(t : @ui.Tester, name : String) -> Array[Json] {
  t.native_asked().filter(fn(a) { a.0 == name }).map(fn(a) { a.1 })
}

///|
/// Every native call still waiting answered `{}` (what the host says of adb.open and adb.start), then the page's
/// motions run to their declared end: nothing left waited on or moving.
fn adb_done(t : @ui.Tester) -> Unit {
  for c in t.native_calls() {
    t.answer_native(c.0, {})
  }
  t.draw()
  t.run_for(bar.rest() - t.time())
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "共享调试 on a phone no chat holds: its switch and the chats alone, the phone asked of its host as it shows; the switch lends the phone to no station" {
  let t = settings_tester("adb:ws1/st1", platform=2)
  // asked once, the page waiting on it
  let calls = t.native_calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].1, "adb.phone")
  t.answer_native(calls[0].0, adb_phone_of(developer=false))
  t.draw()
  t.run_for(@ui.move_most_ms)
  let said = t.words().map(fn(w) { w.0 })
  assert_true(t.find("重启手机、更新 app 后也保持开启") is Some(_), msg="\{Repr(said)}")
  assert_true(t.find("已授权的对话") is Some(_))
  // (2026-11-11: what a person does not need here, gone) no grant live: nothing of the phone's lacks yet
  for gone in ["默认最长授权", "本机设置", "等你允许", "能批准手机调试的设备", "自动填配对码", "允许 app 自动开启无线调试", "打开开发者选项", "下一步"] {
    assert_true(t.find(gone) is None, msg="\{gone}: \{Repr(said)}")
  }
  // its switch turns 共享调试 on for the chats' grants (the core's adb.on), never the host's lending to a station
  t.tap_text("重启手机、更新 app 后也保持开启")
  t.draw()
  adb_done(t)
  assert_eq(asked_native(t, "adb.start"), [])
}

///|
/// The chat at `mode` on a phone, each call of the core it makes kept in order; its host answering `phone` where the
/// fixture has not said the phone already.
fn phone_chat_calls(mode : String, phone? : Json = adb_phone_of(wireless=true)) -> (@ui.Tester, Array[(String, Json)]) {
  new_run()
  let base = fixture(mode)
  let calls : Array[(String, Json)] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, phone)
    }
  }
  t.draw()
  (t, calls)
}

///|
test "an agent's request for this phone while it lacks something, or its switch is off: 允许 all the same, turning 共享调试 on with it" {
  let (t, _) = phone_chat_calls("chat-phone", phone=adb_phone_of(developer=false))
  let only = fn(w : String) { t.words().filter(fn(x) { x.0 == w }).length() }
  assert_true(t.find("需要先打开开发者选项") is None)
  assert_true(t.find("查看步骤") is None)
  assert_eq(only("允许"), 1)
  assert_eq(only("拒绝"), 1)
  // all it takes, but its 共享调试 switch off (2026-10-30: off at first): 允许 turns it on with it
  let (t, calls) = phone_chat_calls("chat-phone-off")
  assert_true(t.find("需要先打开共享调试") is None)
  let allow = t.words().filter(fn(x) { x.0 == "允许" })
  assert_eq(allow.length(), 1)
  t.tap(allow[0].1 + allow[0].3 / 2.0, allow[0].2 + allow[0].4 / 2.0)
  t.draw()
  assert_eq(calls.filter(fn(c) { c.0 == "adb.on" }).map(fn(c) { c.1 }), [{ "on": true }])
  assert_eq(calls.filter(fn(c) { c.0 == "adb.decide" }).length(), 1)
  // (an hour unused at first, as a device's grant: 2026-11-10)
  assert_eq(@sffixture.fix_phone_scope.val, "idle")
  // all it takes there (Wireless debugging the app turns on itself): 允许, which turns it on, the switch left as it is
  let (t, calls) = phone_chat_calls("chat-phone", phone=adb_phone_of(can_switch=true))
  assert_true(t.find("闲置 1 小时后失效") is Some(_))
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  assert_eq(asked_native(t, "adb.switch").length(), 1)
  assert_eq(calls.filter(fn(c) { c.0 == "adb.on" }).length(), 0)
  // on a computer (no adb of its own): 允许, nothing of a switch
  let (t, calls) = phone_chat_calls("chat-phone-off", phone=adb_phone_of(supported=false))
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  assert_eq(calls.filter(fn(c) { c.0 == "adb.on" }).length(), 0)
  assert_eq(calls.filter(fn(c) { c.0 == "adb.decide" }).length(), 1)
}

///|
test "共享调试: granted, the app turns Wireless debugging on itself; the host says it changed, the page with it" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  // (its stations' adb holding the phone already: nothing next once it is on)
  @settings.fixture_motion(1)
  t.post("native:adb.phone", adb_phone_of(can_switch=true).stringify())
  t.draw()
  t.run_for(@ui.move_most_ms)
  let turn_on = t.words().filter(fn(w) { w.0 == "开启" })[0]
  t.tap(turn_on.1 + turn_on.3 / 2.0, turn_on.2 + turn_on.4 / 2.0)
  t.draw()
  assert_eq(asked_native(t, "adb.switch").length(), 1)
  // the host's answer: on; the phone asked again, as the host says it now
  t.answer_native(t.native_calls()[0].0, { "on": true })
  t.draw()
  t.draw()
  let again = t.native_calls()
  assert_eq(again.map(fn(c) { c.1 }), ["adb.phone"])
  t.answer_native(again[0].0, adb_phone_of(wireless=true, can_switch=true))
  t.draw()
  t.run_for(@ui.move_most_ms)
  // all it needs on, its stations holding it: nothing left to say
  assert_true(t.find("开启无线调试") is None)
  assert_true(t.find("待处理") is None)
  // said by the host by itself: off Wi-Fi (Android, as the Wi-Fi went): Wi-Fi's settings a press away
  t.post("native:adb.phone", adb_phone_of(wifi=false).stringify())
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("连接 WLAN") is Some(_))
  t.tap_text("前往 WLAN 设置")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "wifi" }])
  adb_done(t)
}

///|
test "共享调试 on a host with no adb at all (a computer's): no card saying a phone's Android is too old, the chats said of the person's phone; an Android before 11: its card" {
  let t = settings_tester("adb:")
  t.refuse_native(t.native_calls()[0].0, "unsupported")
  t.draw()
  assert_true(t.find("需要 Android 11 及以上：此设备不支持无线调试") is None)
  // (no switch: only a phone lends)
  assert_true(t.find("重启手机、更新 app 后也保持开启") is None)
  assert_true(t.find("现在没有对话在用你的手机") is Some(_))
  assert_true(t.find("现在没有对话在用这台手机") is None)
  adb_done(t)
  // the host says the phone has no Wireless debugging: why, and the chats said of this phone
  let t = settings_tester("adb:")
  t.answer_native(t.native_calls()[0].0, adb_phone_of(supported=false))
  t.draw()
  assert_true(t.find("需要 Android 11 及以上：此设备不支持无线调试") is Some(_))
  assert_true(t.find("现在没有对话在用这台手机") is Some(_))
  adb_done(t)
}
///|
/// The chat's tester with its phone's host answered (`phone`: what AdbShare.java says of it).
fn phone_chat(mode : String, phone : Json) -> @ui.Tester {
  phone_chat_calls(mode, phone~).0
}

///|
test "a granted request on the phone: the first thing left a card under its line, each step done from the card, its line not saying it again; gone once connected" {
  // each kind of step: its title, its line, and what pressing it does (never a page about it)
  let steps : Array[(String, String, String, Json?)] = [
    ("chat-phone-step-off", "打开共享调试", "重启手机、更新 app 后也保持开启", None),
    ("chat-phone-step-developer", "打开开发者选项", "设置 › 关于手机，连点「版本号」7 次", Some({ "what": "about" })),
    ("chat-phone-step-wifi", "连接 WLAN", "无线调试需要连接 WLAN", Some({ "what": "wifi" })),
    // (a press's own words are no line under its title: the card is the press)
    ("chat-phone-step-wireless", "开启无线调试", "", Some({ "what": "wireless" })),
    ("chat-phone-linked-unpaired", "打开配对窗口", "在无线调试中点「使用配对码配对设备」", Some({ "what": "wireless", "beside": true })),
  ]
  for step in steps {
    let (mode, title, line, opens) = step
    let (t, calls) = phone_chat_calls(mode)
    let said = t.words().map(fn(w) { w.0 })
    // (the line stops at what was allowed: the card says what is left)
    assert_true(t.find("已允许调试手机 · 本对话内") is Some(_), msg="\{mode}: \{Repr(said)}")
    assert_true(t.find(title) is Some(_), msg="\{mode}: \{Repr(said)}")
    assert_true(line == "" || t.find(line) is Some(_), msg="\{mode}: \{Repr(said)}")
    assert_true(!said.contains("前往设置开启") && !said.contains("开启"), msg="\{mode}: \{Repr(said)}")
    let (x, y) = adb_button_at(t, title).unwrap()
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.move_most_ms)
    match opens {
      Some(o) => assert_eq(asked_native(t, "adb.open"), [o], msg=mode)
      // (the switch: turned on as its own switch turns it)
      None => assert_eq(calls.filter(fn(c) { c.0 == "adb.on" }).map(fn(c) { c.1 }), [{ "on": true }], msg=mode)
    }
    // never the settings page
    assert_true(app.nav.top() is Chat(_), msg=mode)
  }
  // the app may not turn Wireless debugging on as the phone refused it: which switch lets it, on the card
  let t = phone_chat("chat-phone-step-refused", adb_phone_of())
  assert_true(t.find("开启无线调试") is Some(_))
  assert_true(t.words().iter().any(fn(w) { w.0.contains("禁止权限监控") }), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // the pairing dialog open: its code typed in the app, asked for from the card
  let (t, calls) = phone_chat_calls("chat-phone-step-code")
  assert_true(t.find("输入配对码") is Some(_))
  let (x, y) = adb_button_at(t, "输入配对码").unwrap()
  t.tap(x, y)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("配对码") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_eq(calls.filter(fn(c) { c.0 == "adb.pair" }).length(), 0)
  // the phone's own prompt to allow: said, nothing to press
  let (t, calls) = phone_chat_calls("chat-phone-linked-unauthorized", phone=adb_phone_of(wireless=true))
  let prompt = "手机上弹出「允许 USB 调试吗？」时，点「允许」"
  assert_true(t.find(prompt) is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // pressed: nothing asked of the host or the core, nothing opened
  let (px, py) = t.find(prompt).unwrap()
  t.tap(px + 4.0, py + 4.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(t.native_calls().length(), 0)
  assert_eq(calls.filter(fn(c) { c.0.has_prefix("adb.") }).length(), 0)
  assert_true(app.nav.top() is Chat(_))
  assert_true(t.find("已允许调试手机 · 本对话内") is Some(_))
  // on a computer, no adb of its own: where it is paired, said, nothing to press
  let t = phone_chat("chat-phone-linked-unpaired-desk", adb_phone_of(supported=false))
  assert_true(t.find("已允许调试手机 · 本对话内 · 还差一步：手机尚未完成配对") is Some(_))
  assert_true(t.find("在手机的 still.fail 里打开这条消息配对") is Some(_))
  assert_true(t.find("打开配对窗口") is None)
  // connected: said, nothing more to do
  let t = phone_chat("chat-phone-linked-connected", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 已连上") is Some(_))
  assert_true(t.find("打开配对窗口") is None)
  // offered there no longer, the phone lacking nothing: said
  let t = phone_chat("chat-phone-linked-gone", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 手机现在没有共享给这台 station") is Some(_))
}

///|
test "共享调试 of the second station a phone is lent to: its step first, named, though the first's is connected" {
  // (the phone as the fixture's host said it: all it takes)
  let t = settings_tester("adb:ws1/st2", shows="settings-adb-second")
  assert_true(t.find("agent 可以使用 adb") is None)
  // the next step: its code, paired with this station, which it names (lent to two)
  assert_true(t.find("输入配对码") is Some(_))
  assert_true(t.find("Maple") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  adb_done(t)
}
///|
test "settings' 共享调试: a station waiting for the phone to be paired: the pairing step on the page, no list of stations" {
  let t = settings_tester("adb:", shows="settings-adb-chats", platform=2)
  assert_true(t.find("共享给的 station") is None)
  assert_true(t.find("打开配对窗口") is Some(_))
  t.tap_text("前往无线调试")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "wireless", "beside": true }])
  // paired: nothing left to do, and nothing said of it
  @settings.fixture_motion(1)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("打开配对窗口") is None)
}

///|
test "settings' 共享调试: unfinished setup stands out before routine settings" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  guard t.find("待处理") is Some((_, attention_y)) else { fail("unfinished setup is marked") }
  guard t.find("开启无线调试") is Some((_, step_y)) else { fail("the next step is named") }
  guard t.find("已授权的对话") is Some((_, stations_y)) else { fail("the chats are shown") }
  assert_true(attention_y < stations_y && step_y < stations_y)
  assert_true(t.find("前往设置开启") is Some(_))
  // When more than one prerequisite is missing, the first step and all the other missing settings are visible.
  t.post("native:adb.phone", adb_phone_of(developer=false, wifi=false).stringify())
  t.draw()
  assert_true(t.find("打开开发者选项") is Some(_))
  assert_true(t.words().iter().any(fn(w) { w.0.contains("设置 › 关于手机") }), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // its press: About phone, where Developer options are turned on
  t.tap_text("前往关于手机")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "about" }])
}

///|
test "settings' 共享调试: the unfinished setup's mark follows its title" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  let title = t.words().filter(fn(w) { w.0 == "开启无线调试" })[0]
  let mark = t.words().filter(fn(w) { w.0 == "待处理" })[0]
  // The mark belongs to this title: it follows its words on the same line.
  assert_true(title.1 + title.3 <= mark.1 && title.2 < mark.2 + mark.4 && mark.2 < title.2 + title.4)
}

///|
test "settings' 共享调试: a request waiting is not on the page (its card in its chat is in 待处理)" {
  let t = settings_tester("adb:", shows="settings-adb-chats", platform=2)
  assert_true(t.find("已授权的对话") is Some(_))
  assert_true(t.find("等你允许") is None)
  assert_true(t.words().iter().all(fn(w) { !w.0.contains("看通知权限弹窗的文案") }), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "settings' 共享调试: grants show each chat, its reason and when it was last used" {
  let t = settings_tester("adb:", shows="settings-adb-chats-long", platform=2)
  assert_true(t.find("键盘升起卡顿排查") is Some(_))
  assert_true(t.find("客户端卡顿排查") is Some(_))
  assert_true(t.find("3 分钟前") is Some(_))
  assert_true(t.find("2 小时前") is Some(_))
  assert_true(t.find("暂无使用记录") is Some(_))
  // Long reasons take the same single line, not as many lines as their words need.
  let long = t.rect_of("在开发版里打开对话").unwrap()
  let short = t.rect_of("量整页重搭").unwrap()
  assert_eq(long.3, short.3)
  // Each action is at the same end of its row, regardless of the title or the time's length.
  let actions = t.words().filter(fn(w) { w.0 == "收回" })
  assert_eq(actions.length(), 3)
  assert_eq(actions[0].1, actions[1].1)
  assert_eq(actions[1].1, actions[2].1)
  // Each action has a full touch target inside its own row.
  let rooms = t.room_faults()
  assert_true(!rooms.iter().any(fn(f) { f.contains("「收回」") }), msg="\{Repr(rooms)}")
}

///|
test "settings' 共享调试: the grants list keeps its spacing and each action has room" {
  for win in corner_windows {
    for lang in ["zh", "en"] {
      let t = screen_in("settings-adb-chats-long", win, lang)
      let gaps = t.gap_faults()
      assert_true(gaps.is_empty(), msg="\{win.0}-\{lang}: \{Repr(gaps)}")
      let rooms = t.room_faults().filter(fn(f) { f.contains("「收回」") || f.contains("「Take back」") })
      assert_true(rooms.is_empty(), msg="\{win.0}-\{lang}: \{Repr(rooms)}")
    }
  }
}

///|
test "settings' 共享调试: the take back button acts on its own chat" {
  new_run()
  @settings.fixture_page("settings-adb-chats-long") |> ignore
  let base = fixture("settings")
  let calls : Array[Made] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_setting("adb:")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("收回")
  t.draw()
  let asked = calls.filter(fn(call) { call.name == "adb.revoke" })
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].params, { "station": "ws1/st1", "request": "p-long-1" })
}

///|
test "settings' 共享调试: phone setup comes before a long list of grants" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  guard t.find("开启无线调试") is Some((_, phone_y)) else { fail("phone setup is shown") }
  guard t.find("已授权的对话") is Some((_, stations_y)) else { fail("the chats are shown") }
  assert_true(phone_y < stations_y)
}

///|
test "settings' 共享调试: wireless debugging opens its system setting" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  t.tap_text("前往设置开启")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "wireless" }])
}

///|
test "settings' 共享调试: wireless debugging turns on in the app when allowed" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  t.post("native:adb.phone", adb_phone_of(can_switch=true).stringify())
  t.draw()
  let turn_on = t.words().filter(fn(w) { w.0 == "开启" })[0]
  t.tap(turn_on.1 + turn_on.3 / 2.0, turn_on.2 + turn_on.4 / 2.0)
  t.draw()
  assert_eq(asked_native(t, "adb.switch").length(), 1)
}

///|
test "settings' 共享调试: the phone setup closes in place as wireless debugging comes on" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  // (its stations' adb holding the phone already: nothing next once it is on)
  @settings.fixture_motion(1)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let (_, before) = t.drawn_of("已授权的对话").unwrap()
  t.post("native:adb.phone", adb_phone_of(wireless=true).stringify())
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, halfway) = t.drawn_of("已授权的对话").unwrap()
  t.run_for(@ui.row_size_ms)
  let (_, after) = t.drawn_of("已授权的对话").unwrap()
  assert_true(after < halfway && halfway < before, msg="\{before}, \{halfway}, \{after}")
}

///|
test "settings' 共享调试: the phone that refused the app's grant: its step says which switch lets the app; a station's adb failing, not said here" {
  let t = settings_tester("adb:", shows="settings-adb-chats-off", platform=2)
  assert_true(t.words().iter().all(fn(w) { !w.0.contains("禁止权限监控") }))
  t.post("native:adb.phone", adb_phone_of(refused=true).stringify())
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("开启无线调试") is Some(_))
  assert_true(t.words().iter().any(fn(w) { w.0.contains("禁止权限监控") }), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // the app let since: the switch's own press, no word of it
  t.post("native:adb.phone", adb_phone_of(can_switch=true, refused=true).stringify())
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.words().iter().all(fn(w) { !w.0.contains("禁止权限监控") }))
  // its adb failing: tried again by itself, nothing to do here (its chat's card says it)
  let t = settings_tester("adb:", shows="settings-adb-failed", platform=2)
  assert_true(t.find("adb 连接失败") is None)
  assert_true(t.find("待处理") is None)
}

///|
test "a request on a device its person's trusted devices have not approved: 批准这台设备 first, 查看步骤 opening 共享调试; with no lock of theirs yet, 允许 as anywhere" {
  for phone in [adb_phone_of(wireless=true), adb_phone_of(supported=false)] {
    let t = phone_chat("chat-phone-outside", phone)
    assert_true(t.find("需要先批准这台设备") is Some(_))
    assert_eq(t.words().filter(fn(x) { x.0 == "允许" }).length(), 0)
    t.tap_text("查看步骤")
    t.run_for(@ui.move_most_ms)
    // (settings' 共享调试, that step alone)
    assert_true(t.find("此设备尚未获批") is Some(_))
    assert_true(t.find("发送批准请求") is Some(_))
    assert_true(t.find("重启手机、更新 app 后也保持开启") is None)
    // no lock yet: the core says nothing first (allowing begins it), so the card is any ready device's
    let t = phone_chat("chat-phone-none", phone)
    assert_true(t.find("需要先") is None)
    assert_eq(t.words().filter(fn(x) { x.0 == "允许" }).length(), 1)
    assert_true(t.find("查看步骤") is None)
  }
}

///|
test "settings' 共享调试: a grant the phone does not lend keeps its title whole, what it says clear of 收回" {
  let t = settings_tester("adb:", shows="settings-adb-unsigned", platform=2)
  let title = t.rect_of("定时 · 每 15 分钟审 mbui 三条线").unwrap()
  assert_true(title.2 > 200.0, msg="\{Repr(title)}")
  let said = t.words().filter(fn(w) { w.0 == "待确认" })
  let back = t.words().filter(fn(w) { w.0 == "收回" })
  assert_eq(said.length(), 1)
  assert_eq(back.length(), 1)
  assert_true(said[0].1 + said[0].3 <= back[0].1, msg="\{Repr(said)} \{Repr(back)}")
  // the card's link rows' words on the same line as the switch's
  let other = t.rect_of("重启手机、更新 app 后也保持开启").unwrap()
  assert_eq(title.0, other.0)
  assert_true(t.room_faults().is_empty(), msg="\{Repr(t.room_faults())}")
}

///|
/// Settings' 共享调试 (`page`, a route's name) on a phone over the fixture's `mode`, each call it makes kept in order.
fn adb_settings_calls(
  mode : String,
  page? : String = "adb:",
  w? : Double = 390.0,
  scale? : Double = 1.0,
) -> (@ui.Tester, Array[(String, Json)]) {
  new_run()
  @settings.fixture_page(mode) |> ignore
  let base = fixture("settings")
  let calls : Array[(String, Json)] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform=2)
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  open_setting(page)
  t.draw()
  t.run_for(@ui.move_most_ms)
  (t, calls)
}

///|
test "settings' 共享调试 with no lock of the person's own yet: the page as it is, no step to turn anything on first" {
  let t = settings_tester("adb:", shows="settings-adb-gate-none", platform=2)
  assert_true(t.find("重启手机、更新 app 后也保持开启") is Some(_))
  // (the owner took 开启 away, 2026-11-10: nothing names a lock of one's own, nor asks to turn one on)
  assert_eq(t.words().filter(fn(w) { w.0.contains("个人锁") || w.0 == "开启" }).length(), 0)
  assert_true(t.find("此设备尚未获批") is None)
  // nobody's devices listed: this device is on no lock
  assert_true(t.find("能批准手机调试的设备") is None)
}

///|
test "settings' 共享调试 on a device its person's trusted devices have not approved: that step alone, 发送批准请求 asking it" {
  let (t, calls) = adb_settings_calls("settings-adb-lock-outside")
  assert_true(t.find("此设备尚未获批") is Some(_))
  assert_true(t.find("在你的受信任设备上批准这台设备后，它才能批准手机调试。") is Some(_))
  // nothing that does anything before it: the switch
  assert_true(t.find("重启手机、更新 app 后也保持开启") is None)
  t.tap_text("发送批准请求")
  t.draw()
  let asked = calls.filter(fn(call) { call.0 == "adb.personalJoin" })
  assert_eq(asked.length(), 1, msg="\{Repr(calls.map(fn(call) { call.0 }))}")
  assert_eq(asked[0].1, { "sub": "s" })
}

///|
test "settings' 共享调试: a device being approved types the code its trusted device shows in the page" {
  let (t, calls) = adb_settings_calls("settings-adb-gate-code")
  assert_true(t.find("此设备尚未获批") is Some(_))
  assert_true(t.find("14:05 前有效") is Some(_))
  t.tap_text("MacBook Pro")
  t.type_text("123456")
  let typed = calls.filter(fn(call) { call.0 == "adb.personalCode" })
  assert_eq(typed.length(), 1, msg="\{Repr(calls.map(fn(call) { call.0 }))}")
  assert_eq(typed[0].1, { "code": "123456" })
}

///|
test "settings' 共享调试 on a device its person's trusted devices approved: their devices are not listed here (安全's), what is to confirm is" {
  // (the link of the person's own lock's page of before opens it: existing links keep working)
  let (t, calls) = adb_settings_calls("settings-adb-lock-member", page="personal-lock:")
  assert_true(t.find("重启手机、更新 app 后也保持开启") is Some(_))
  assert_true(t.find("能批准手机调试的设备") is None)
  assert_true(t.find("MacBook Pro") is None)
  assert_true(t.find("移除") is None)
  assert_true(t.find("确认") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_eq(calls.filter(fn(call) { call.0 == "adb.personalRemove" }).length(), 0)
}

///|
test "settings' 共享调试: its switch at the top, the chats after it" {
  let t = settings_tester("adb:", shows="settings-adb-chats-long", platform=2)
  guard t.find("重启手机、更新 app 后也保持开启") is Some((_, switch_y)) else { fail("the switch is shown") }
  guard t.find("已授权的对话") is Some((_, chats_y)) else { fail("the chats are shown") }
  assert_true(switch_y < chats_y)
}

///|
test "settings' 共享调试 on a computer (no adb of its own): the chats granted the person's phone alone, each taken back" {
  let t = settings_tester("adb:", shows="settings-adb-desk", platform=0)
  assert_true(t.find("已授权的对话") is Some(_))
  assert_true(t.find("键盘升起卡顿排查") is Some(_))
  assert_eq(t.words().filter(fn(w) { w.0 == "收回" }).length(), 3)
  assert_true(t.find("重启手机、更新 app 后也保持开启") is None)
  assert_true(t.find("待处理") is None)
}

///|
test "settings' 共享调试 on a phone's narrow page: what it is behind the ⓘ after its title, a tap away" {
  for w in [390.0, 320.0] {
    let (t, _) = adb_settings_calls("settings-adb-chats-long", w~)
    assert_true(t.find("agent 在对话里申请，你允许后只有那个对话能用。") is None)
    guard adb_button_at(t, "说明") is Some((x, y)) else { fail("no ⓘ at \{w}: \{Repr(t.semantics().map(fn(s) { s.label }))}") }
    // after the title, in the bar
    let (title_x, title_y) = t.find("共享调试").unwrap()
    assert_true(x > title_x && (y - title_y).abs() < 20.0, msg="\{w}: \{Repr((x, y))} \{Repr((title_x, title_y))}")
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("agent 在对话里申请，你允许后只有那个对话能用。") is Some(_), msg="\{w}")
  }
}
