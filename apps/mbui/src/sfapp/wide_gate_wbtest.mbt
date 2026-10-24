// The desktop's page for a device waiting to be confirmed in the workspace's lock (sfdesk security.mbt
// security_waiting, cloud/Security.tsx SecurityWaiting): in the page's place, beside the rail.

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
