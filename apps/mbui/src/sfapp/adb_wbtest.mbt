// 共享调试's page (settings/station_parts.mbt adb_page) over the settings' fixture, its phone as the test's host says it
// (the native calls of the app's Android: AdbShare.java).

///|
/// The phone as AdbShare.java's adb.phone answers it.
fn adb_phone_of(
  supported? : Bool = true,
  developer? : Bool = true,
  wireless? : Bool = false,
  wifi? : Bool = true,
  can_switch? : Bool = false,
  reads? : Bool = false,
) -> Json {
  {
    "supported": Json::boolean(supported),
    "developer": Json::boolean(developer),
    "wireless": Json::boolean(wireless),
    "wifi": Json::boolean(wifi),
    "canSwitch": Json::boolean(can_switch),
    "reads": Json::boolean(reads),
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
test "共享调试: the phone asked of its host as the page shows; the first thing it lacks next, and where to turn it on" {
  let t = settings_tester("adb:ws1/st1")
  // asked once, the page waiting on it
  let calls = t.native_calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].1, "adb.phone")
  assert_true(t.find("本机设置") is None)
  t.answer_native(calls[0].0, adb_phone_of(developer=false))
  t.draw()
  assert_true(t.find("本机设置") is Some(_))
  // the one thing next: Developer options, and how (Wireless debugging is off too, but comes after it)
  assert_true(t.find("下一步") is Some(_))
  assert_true(t.find("打开开发者选项") is Some(_))
  assert_true(t.find("设置 › 关于手机，连点「版本号」7 次") is Some(_))
  assert_true(t.find("前往设置开启") is None)
  // what the phone lacks, said; what is on with nothing to tap there (WLAN), not
  assert_true(t.find("未打开") is Some(_))
  assert_true(t.find("WLAN") is None)
  // Developer options on (said by the host as the app comes back): Wireless debugging next, the app not granted to
  // turn it on, so Settings at it
  t.post("native:adb.phone", adb_phone_of().stringify())
  t.draw()
  assert_true(t.find("打开开发者选项") is None)
  assert_true(t.find("开启无线调试") is Some(_))
  t.tap_text("前往设置开启")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "wireless" }])
  // lent: the host's service started for this station, with the notifications' words (its row titled as the page is)
  assert_true(t.find("一小时后自动停止") is Some(_))
  guard t.find_last("共享调试") is Some((x, y)) else { fail("the switch's row") }
  t.tap(x, y)
  t.draw()
  let started = asked_native(t, "adb.start")
  assert_eq(started.length(), 1)
  guard started[0] is Object(m) else { fail("adb.start's params") }
  assert_eq(m.get("station"), Some(Json::string("ws1/st1")))
  assert_eq(m.get("name"), Some(Json::string("Willow")))
  guard m.get("texts") is Some(Object(words)) else { fail("adb.start's words") }
  assert_eq(words.get("android-misc.adb.notify.title"), Some(Json::string("正在将调试共享给 {name}")))
  adb_done(t)
}

///|
test "an agent's request for this phone while it lacks something to be lent: what first, and 查看步骤 in 允许's place" {
  let t = chat_tester("chat-phone")
  let only = fn(w : String) { t.words().filter(fn(x) { x.0 == w }).length() }
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, adb_phone_of(developer=false))
    }
  }
  t.draw()
  assert_true(t.find("需要先打开开发者选项") is Some(_))
  assert_eq(only("允许"), 0)
  assert_eq(only("拒绝"), 1)
  t.tap_text("查看步骤")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("本机设置") is Some(_))
  // all it takes, but its 共享调试 switch off (2026-10-30: off at first): turned on first, on its page
  let t = chat_tester("chat-phone-off")
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, adb_phone_of(wireless=true))
    }
  }
  t.draw()
  assert_true(t.find("需要先打开共享调试") is Some(_))
  let only = fn(w : String) { t.words().filter(fn(x) { x.0 == w }).length() }
  assert_eq(only("允许"), 0)
  t.tap_text("查看步骤")
  t.run_for(@ui.move_most_ms)
  // (its page: the switch first)
  assert_true(t.find("默认最长授权") is Some(_))
  // all it takes there (Wireless debugging the app turns on itself): 允许, which turns it on
  let t = chat_tester("chat-phone")
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, adb_phone_of(can_switch=true))
    }
  }
  t.draw()
  assert_true(t.find("需要先") is None)
  let only = fn(w : String) { t.words().filter(fn(x) { x.0 == w }).length() }
  assert_eq(only("允许"), 1)
  // (an hour unused at first, as a device's grant: 2026-11-10)
  assert_true(t.find("闲置 1 小时后失效") is Some(_))
  // (the button, not the title that asks 允许…)
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  assert_eq(asked_native(t, "adb.switch").length(), 1)
  assert_eq(@sffixture.fix_phone_scope.val, "idle")
}

///|
test "共享调试: granted, the app turns Wireless debugging on itself; the host says it changed, the page with it" {
  let t = settings_tester("adb:ws1/st1")
  t.answer_native(t.native_calls()[0].0, adb_phone_of(can_switch=true))
  t.draw()
  assert_true(t.find("开启") is Some(_))
  t.tap_text("开启")
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
  assert_true(t.find("前往设置开启") is None)
  // all it needs on, nothing to turn on: nothing said of the phone
  assert_true(t.find("本机设置") is None)
  // said by the host by itself: Wireless debugging off again (Android, as the Wi-Fi went)
  t.post("native:adb.phone", adb_phone_of(wifi=false).stringify())
  t.draw()
  assert_true(t.find("连接 WLAN") is Some(_))
  assert_true(t.find("未连接") is Some(_))
  adb_done(t)
}

///|
test "共享调试: a host without it, nothing to lend" {
  let t = settings_tester("adb:ws1/st1")
  t.refuse_native(t.native_calls()[0].0, "unsupported")
  t.draw()
  assert_true(t.find("需要 Android 11 及以上：此设备不支持无线调试") is Some(_))
  assert_true(t.find("本机设置") is None)
  adb_done(t)
}

///|
/// The chat's tester with its phone's host answered (`phone`: what AdbShare.java says of it).
fn phone_chat(mode : String, phone : Json) -> @ui.Tester {
  let t = chat_tester(mode)
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, phone)
    }
  }
  t.draw()
  t
}

///|
test "an approved request whose station is not paired with the phone yet: not green, a card opening that station's 共享调试" {
  let t = phone_chat("chat-phone-linked-unpaired", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 还差一步：手机尚未完成配对") is Some(_))
  assert_true(t.find("已连上") is None)
  // (a login's card's look: no button of its own, the card the way there)
  assert_true(t.find("去配对") is None)
  t.tap_text("在手机上完成配对后即可共享调试")
  t.run_for(@ui.move_most_ms)
  // (the chat's station's own page, the one waiting on it: not settings' page, which has no station's pairing)
  assert_true(t.find("Willow") is Some(_))
  assert_true(t.find("默认最长授权") is None)
  // on a computer, no adb of its own: where it is paired, said, nothing to tap
  let t = phone_chat("chat-phone-linked-unpaired-desk", adb_phone_of(supported=false))
  assert_true(t.find("在手机的 still.fail 里打开这条消息配对") is Some(_))
  assert_true(t.find("在手机上完成配对后即可共享调试") is None)
  // connected: said, nothing more to do
  let t = phone_chat("chat-phone-linked-connected", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 已连上") is Some(_))
  assert_true(t.find("在手机上完成配对后即可共享调试") is None)
  // offered there no longer
  let t = phone_chat("chat-phone-linked-gone", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 手机现在没有共享给这台 station") is Some(_))
}

///|
test "共享调试 of the second station a phone is lent to: its own lending, waiting to be paired, though the first's is connected" {
  // (the phone as the fixture's host said it: all it takes)
  let t = settings_tester("adb:ws1/st2", shows="settings-adb-second")
  assert_true(t.find("手机尚未完成配对") is Some(_))
  assert_true(t.find("agent 可以使用 adb") is None)
  // the next step: its code, paired with this station
  assert_true(t.find("输入配对码") is Some(_))
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
  assert_true(t.find("设置 › 关于手机") is Some(_))
  assert_true(t.find("WLAN") is Some(_))
  assert_true(t.find("无线调试") is Some(_))
  // The setting stays with the switch at the page's top.
  assert_true(t.find("默认最长授权") is Some(_))
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
test "settings' 共享调试: a pending request comes before information and opens its chat" {
  let t = settings_tester("adb:", shows="settings-adb-chats", platform=2)
  guard t.find("等你允许") is Some((_, pending_y)) else { fail("the request is shown") }
  guard t.find("已授权的对话") is Some((_, stations_y)) else { fail("the chats are shown") }
  assert_true(pending_y < stations_y)
  t.tap_text("通知权限检查")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("发消息") is Some(_))
  guard app.nav.top() is Chat(opened) else { fail("the request's chat is open") }
  assert_eq(opened.station, "ws1/st1")
  assert_eq(opened.session, "s-c1")
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
  assert_true(!rooms.iter().any(fn(f) { f.contains("「收回」") }), msg="\{rooms}")
}

///|
test "settings' 共享调试: the grants list keeps its spacing and each action has room" {
  for win in corner_windows {
    for lang in ["zh", "en"] {
      let t = screen_in("settings-adb-chats-long", win, lang)
      let gaps = t.gap_faults()
      assert_true(gaps.is_empty(), msg="\{win.0}-\{lang}: \{gaps}")
      let rooms = t.room_faults().filter(fn(f) { f.contains("「收回」") || f.contains("「Take back」") })
      assert_true(rooms.is_empty(), msg="\{win.0}-\{lang}: \{rooms}")
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
      calls.push({ name, params, bytes: None, done, heard: None })
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
  guard t.find("本机设置") is Some((_, phone_y)) else { fail("phone setup is shown") }
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
  let (_, before) = t.drawn_of("等你允许").unwrap()
  t.post("native:adb.phone", adb_phone_of(wireless=true).stringify())
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, halfway) = t.drawn_of("等你允许").unwrap()
  t.run_for(@ui.row_size_ms)
  let (_, after) = t.drawn_of("等你允许").unwrap()
  assert_true(after < halfway && halfway < before, msg="\{before}, \{halfway}, \{after}")
}

///|
test "共享调试 of a station a grant lends the phone to: no switch that cannot stop it, settings' page a tap away" {
  let t = settings_tester("adb:ws1/st2", shows="settings-adb-second")
  assert_true(t.find("在设置里管理") is Some(_))
  t.tap_text("在设置里管理")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("默认最长授权") is Some(_))
  // the code reader's row says where Accessibility keeps it
  let t = settings_tester("adb:ws1/st2", shows="settings-adb-second")
  assert_true(t.find("自动填配对码") is Some(_))
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
    assert_true(t.find("默认最长授权") is None)
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
  assert_true(title.2 > 200.0, msg="\{title}")
  let said = t.words().filter(fn(w) { w.0 == "待确认" })
  let back = t.words().filter(fn(w) { w.0 == "收回" })
  assert_eq(said.length(), 1)
  assert_eq(back.length(), 1)
  assert_true(said[0].1 + said[0].3 <= back[0].1, msg="\{said} \{back}")
  // the card's link rows' words on the same line as its other rows' (the switch's)
  let other = t.rect_of("重启手机、更新 app 后也保持开启").unwrap()
  assert_eq(title.0, other.0)
  assert_eq(t.rect_of("默认最长授权").unwrap().0, other.0)
  assert_true(t.room_faults().is_empty(), msg="\{t.room_faults()}")
}

///|
/// Settings' 共享调试 (`page`, a route's name) on a phone over the fixture's `mode`, each call it makes kept in order.
fn adb_settings_calls(mode : String, page? : String = "adb:") -> (@ui.Tester, Array[(String, Json)]) {
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_setting(page)
  t.draw()
  t.run_for(@ui.move_most_ms)
  (t, calls)
}

///|
test "settings' 共享调试 with no lock of the person's own yet: the page as it is, no step to turn anything on first" {
  let t = settings_tester("adb:", shows="settings-adb-gate-none", platform=2)
  assert_true(t.find("默认最长授权") is Some(_))
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
  // nothing that does anything before it: the switch, how long grants last
  assert_true(t.find("重启手机、更新 app 后也保持开启") is None)
  assert_true(t.find("默认最长授权") is None)
  t.tap_text("发送批准请求")
  t.draw()
  let asked = calls.filter(fn(call) { call.0 == "adb.personalJoin" })
  assert_eq(asked.length(), 1, msg="\{calls.map(fn(call) { call.0 })}")
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
  assert_eq(typed.length(), 1, msg="\{calls.map(fn(call) { call.0 })}")
  assert_eq(typed[0].1, { "code": "123456" })
}

///|
test "settings' 共享调试 on a device its person's trusted devices approved: the devices that approve phone debugging, another removed asked first, not this one" {
  // (the link of the person's own lock's page of before opens it: existing links keep working)
  let (t, calls) = adb_settings_calls("settings-adb-lock-member", page="personal-lock:")
  assert_true(t.find("默认最长授权") is Some(_))
  assert_true(t.find("能批准手机调试的设备") is Some(_))
  let (_, mine_y) = t.find("OPPO PLP110").unwrap()
  let (_, other_y) = t.find("MacBook Pro").unwrap()
  assert_true(t.find("这台设备") is Some(_))
  // 移除 by the other device alone
  let removes = t.words().filter(fn(w) { w.0 == "移除" && w.5 > 0.5 })
  assert_eq(removes.length(), 1, msg="\{removes}")
  let row = removes[0]
  let middle = row.2 + row.4 / 2.0
  assert_true((middle - other_y).abs() < (middle - mine_y).abs(), msg="\{row} \{other_y} \{mine_y}")
  t.tap(row.1 + row.3 / 2.0, middle)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // asked first: nothing removed yet
  assert_true(@sf.presenting())
  assert_true(t.find("移除「MacBook Pro」？") is Some(_))
  assert_true(t.find("该设备将不能再批准手机调试，也无法再访问开了安全模式的 workspace，重新批准后才能使用") is Some(_))
  assert_eq(calls.filter(fn(call) { call.0 == "adb.personalRemove" }).length(), 0)
  // the dialog's 移除, not the row's under it
  let said = t.words().filter(fn(w) { w.0 == "移除" && w.5 > 0.5 && (w.1 != row.1 || w.2 != row.2) })
  assert_eq(said.length(), 1, msg="\{said}")
  t.tap(said[0].1 + said[0].3 / 2.0, said[0].2 + said[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
  let asked = calls.filter(fn(call) { call.0 == "adb.personalRemove" })
  assert_eq(asked.length(), 1, msg="\{calls.map(fn(call) { call.0 })}")
  assert_eq(asked[0].1, { "sub": "s", "key": "ed25519:bb" })
}

///|
test "settings' 共享调试: its settings at the top, the lists after them" {
  let t = settings_tester("adb:", shows="settings-adb-chats-long", platform=2)
  guard t.find("默认最长授权") is Some((_, lasts_y)) else { fail("the setting is shown") }
  guard t.find("已授权的对话") is Some((_, chats_y)) else { fail("the chats are shown") }
  assert_true(lasts_y < chats_y)
}

///|
test "settings' 共享调试: its switch is the library's switch row, its title as strong as the setting's under it" {
  let t = settings_tester("adb:", shows="settings-adb-chats-long", platform=2)
  let calls_before = t.words().filter(fn(w) { w.0 == "共享调试" }).length()
  assert_true(calls_before >= 2)
  let title = t.words().filter(fn(w) { w.0 == "共享调试" }).iter().find_first(fn(w) { w.2 > 60.0 }).unwrap()
  let lasts = t.words().filter(fn(w) { w.0 == "默认最长授权" })[0]
  // the same size and line as a setting's title
  assert_eq(title.4, lasts.4)
  assert_eq(title.1, lasts.1)
}
