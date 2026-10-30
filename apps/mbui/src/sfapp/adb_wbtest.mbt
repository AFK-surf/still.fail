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
  assert_eq(m.get("name"), Some(Json::string("Studio")))
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
  // (the button, not the title that asks 允许…)
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  assert_eq(asked_native(t, "adb.switch").length(), 1)
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
test "an approved request whose station is not paired with the phone yet: not green, 去配对 opening that station's 共享调试" {
  let t = phone_chat("chat-phone-linked-unpaired", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 还差一步：这台手机还没和 station 配对") is Some(_))
  assert_true(t.find("已连上") is None)
  t.tap_text("去配对")
  t.run_for(@ui.move_most_ms)
  // (the chat's station's own page, the one waiting on it: not settings' page, which has no station's pairing)
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.find("默认最长授权") is None)
  // on a computer, no adb of its own: where it is paired, said, nothing to tap
  let t = phone_chat("chat-phone-linked-unpaired-desk", adb_phone_of(supported=false))
  assert_true(t.find("在手机的 still.fail 里打开这条消息配对") is Some(_))
  assert_true(t.find("去配对") is None)
  // connected: said, nothing more to do
  let t = phone_chat("chat-phone-linked-connected", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 已连上") is Some(_))
  assert_true(t.find("去配对") is None)
  // offered there no longer
  let t = phone_chat("chat-phone-linked-gone", adb_phone_of(wireless=true))
  assert_true(t.find("已允许调试手机 · 本对话内 · 手机现在没有共享给这台 station") is Some(_))
}

///|
test "共享调试 of the second station a phone is lent to: its own lending, waiting to be paired, though the first's is connected" {
  // (the phone as the fixture's host said it: all it takes)
  let t = settings_tester("adb:ws1/st2", shows="settings-adb-second")
  assert_true(t.find("此 station 尚未与本机配对") is Some(_))
  assert_true(t.find("agent 可以使用 adb") is None)
  // the next step: its code, paired with this station
  assert_true(t.find("输入配对码") is Some(_))
  adb_done(t)
}

///|
test "settings' 共享调试: the stations its grants lend it to, each as its adb holds the phone, its own page a tap away" {
  let t = settings_tester("adb:", shows="settings-adb-chats")
  for c in t.native_calls() {
    if c.1 == "adb.phone" {
      t.answer_native(c.0, adb_phone_of(wireless=true))
    }
  }
  t.draw()
  assert_true(t.find("共享给的 station") is Some(_))
  assert_true(t.find("agent 可以使用 adb") is Some(_))
  assert_true(t.find("此 station 尚未与本机配对") is Some(_))
  t.tap_text("此 station 尚未与本机配对")
  t.run_for(@ui.move_most_ms)
  // (MBA's page: settings' page gone from view)
  assert_true(t.find("默认最长授权") is None)
}
