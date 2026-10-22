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
test "共享调试: the phone asked of its host as the page shows; what it needs, and where to turn it on" {
  let t = settings_tester("adb:ws1/st1")
  // asked once, the page waiting on it
  let calls = t.native_calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].1, "adb.phone")
  assert_true(t.find("手机上") is None)
  t.answer_native(calls[0].0, adb_phone_of(developer=false))
  t.draw()
  assert_true(t.find("手机上") is Some(_))
  assert_true(t.find("设置 › 关于手机，连点「版本号」7 次") is Some(_))
  assert_true(t.find("已连接") is Some(_))
  // Wireless debugging off, the app not granted to turn it on: Settings at its row
  t.tap_text("前往设置开启")
  t.draw()
  assert_eq(asked_native(t, "adb.open"), [{ "what": "wireless" }])
  // lent: the host's service started for this station, with the notifications' words
  // (the switch's row, under its title: the words end the page's about too, above it)
  guard t.find_last("一小时后自动停止") is Some((x, y)) else { fail("the switch's row") }
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
  // said by the host by itself: Wireless debugging off again (Android, as the Wi-Fi went)
  t.post("native:adb.phone", adb_phone_of(wifi=false).stringify())
  t.draw()
  assert_true(t.find("无线调试需要连接 WLAN") is Some(_))
  adb_done(t)
}

///|
test "共享调试: a host without it, nothing to lend" {
  let t = settings_tester("adb:ws1/st1")
  t.refuse_native(t.native_calls()[0].0, "unsupported")
  t.draw()
  assert_true(t.find("需要 Android 11 及以上：此设备不支持无线调试") is Some(_))
  assert_true(t.find("手机上") is None)
  adb_done(t)
}
