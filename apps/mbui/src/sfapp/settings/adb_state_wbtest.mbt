// 共享调试's line while it is lent (station_parts.mbt adb_state).

///|
test "共享调试 lent: the minutes left of it, said again as they change" {
  let lines : Array[String] = []
  let until = 1000.0 + 630000.0
  let view : Json = { "phase": "offered", "adb": "connected", "until": ToJson::to_json(until) }
  let t = @ui.Tester::new(fn(c) { lines.push(adb_state(c, Some(view), c.moment())) }, time=1000.0, platform=2)
  assert_eq(lines[lines.length() - 1], fill("android-misc.adb.connected.left", [("n", "10")]))
  // just past where 10 whole minutes are left: drawn then, by itself
  t.run_for(until - 10.0 * 60000.0 - t.time() + 1.0)
  assert_eq(lines[lines.length() - 1], fill("android-misc.adb.connected.left", [("n", "9")]))
  // with no end said: lent, no minutes
  let none : Json = { "phase": "offered", "adb": "connected" }
  let u = @ui.Tester::new(fn(c) { lines.push(adb_state(c, Some(none), c.moment())) }, platform=2)
  ignore(u)
  assert_eq(lines[lines.length() - 1], tr("android-misc.adb.connected"))
}

///|
test "共享调试 held off Wi-Fi on adbd's plain port: Wi-Fi and Wireless debugging are not asked for" {
  let phone : Json = { "developer": true, "wifi": false, "wireless": false }
  let held : Json = { "phase": "offered", "adb": "connected" }
  assert_true(adb_next(Some(held), Some(phone), true) is None)
  // not held: Wi-Fi is the next step, as before
  let connecting : Json = { "phase": "offered", "adb": "connecting" }
  match adb_next(Some(connecting), Some(phone), true) {
    Some(step) => assert_eq(step.title, tr("android-misc.adb.step.wifi"))
    None => fail("Wi-Fi not asked for")
  }
}
