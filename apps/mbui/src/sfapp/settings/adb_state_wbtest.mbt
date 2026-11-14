// 共享调试's next step while it is lent (station_parts.mbt adb_next).

///|
test "共享调试 held off Wi-Fi on adbd's plain port: Wi-Fi and Wireless debugging are not asked for" {
  // (its own run of the settings first: what the words are read in is this test's, not the one's before it)
  reset()
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
