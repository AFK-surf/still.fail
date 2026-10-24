// 共享调试's line while it is lent (station_parts.mbt adb_state, AdbShare.kt state).

///|
test "共享调试 lent: the minutes left of it, said again as they change" {
  let lines : Array[String] = []
  let until = 1000.0 + 630000.0
  let view : Json = { "phase": "offered", "adb": "connected", "until": until.to_json() }
  let t = @ui.Tester::new(fn(c) { lines.push(adb_state(c, Some(view), c.now)) }, time=1000.0, platform=2)
  assert_eq(lines[lines.length() - 1], fill("android-misc.adb.connected.left", [("n", "10")]))
  // just past where 10 whole minutes are left: drawn then, by itself
  t.run_for(until - 10.0 * 60000.0 - t.time() + 1.0)
  assert_eq(lines[lines.length() - 1], fill("android-misc.adb.connected.left", [("n", "9")]))
  // with no end said: lent, no minutes
  let none : Json = { "phase": "offered", "adb": "connected" }
  let u = @ui.Tester::new(fn(c) { lines.push(adb_state(c, Some(none), c.now)) }, platform=2)
  ignore(u)
  assert_eq(lines[lines.length() - 1], tr("android-misc.adb.connected"))
}
