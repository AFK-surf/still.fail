// An agent's request for a rig of the workspace as its card in the chat (settings/rig_ask.mbt, sfpages decision.mbt
// rig_ask_card: a station that only runs tasks): answered by the rig's person alone, for the time they choose; said whose it is to anyone
// else; on a device that does not sign as its person, what first; decided, a line saying how it went.

///|
fn only_word(t : @ui.Tester, w : String) -> Int {
  t.words().filter(fn(x) { x.0 == w }).length()
}

///|
test "a request for the viewer's own rig: its name and the reason, 允许 for the time asked and 拒绝; allowed, the core is asked with what the card said of the chat" {
  let t = chat_tester("chat-rig")
  assert_true(t.find("允许这个对话的 agent 使用 station「build-box」？") is Some(_))
  assert_true(t.find("在 Linux 上跑一遍完整的 station 测试") is Some(_))
  assert_eq(only_word(t, "允许"), 1)
  assert_eq(only_word(t, "拒绝"), 1)
  // (the time the agent asked for, first)
  assert_true(t.find("闲置 1 小时") is Some(_))
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  let asked = @sffixture.fix_rig_asked
  assert_eq(asked.length(), 1)
  let p = Some(asked[0])
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(text(p, "request"), "r-1")
  assert_true(flag(p, "allow"))
  assert_eq(text(p, "timeoutKind"), "idle")
  assert_eq(count(p, "timeoutSeconds"), 3600)
  let ask = field(p, "ask")
  assert_eq(text(ask, "rig"), "aa11")
  assert_eq(text(ask, "session"), "s-c1")
  assert_eq(text(ask, "chat"), "CHAT/1")
  assert_eq(text(ask, "title"), "修 CI")
  assert_eq(text(ask, "by"), "lin@example.com")
  // decided: how it went, in the answer's place
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("已允许使用这台 station · 8 小时后失效") is Some(_))
}

///|
test "a request for the viewer's rig refused: asked with no time, and said so" {
  let t = chat_tester("chat-rig")
  t.tap_text("拒绝")
  t.draw()
  let asked = @sffixture.fix_rig_asked
  assert_eq(asked.length(), 1)
  assert_true(!flag(Some(asked[0]), "allow"))
  assert_eq(text(Some(asked[0]), "timeoutKind"), "")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("已拒绝使用这台 station") is Some(_))
}

///|
test "a request for someone else's rig: no answer here, who decides said" {
  let t = chat_tester("chat-rig-other")
  assert_true(t.find("允许这个对话的 agent 使用 station「build-box」？") is Some(_))
  assert_true(t.find("等 陈 决定") is Some(_))
  assert_eq(only_word(t, "允许"), 0)
  assert_eq(only_word(t, "拒绝"), 0)
}

///|
test "a request for the viewer's rig on a device that does not sign as them: a web page says where to answer; one not approved yet is sent to 共享调试; both may refuse" {
  let t = chat_tester("chat-rig-web")
  assert_true(t.find("网页版批准不了：请在手机或电脑上的 app 里批准") is Some(_))
  assert_eq(only_word(t, "允许"), 0)
  assert_eq(only_word(t, "拒绝"), 1)
  let t = chat_tester("chat-rig-outside")
  assert_true(t.find("此设备尚未获批") is Some(_))
  assert_eq(only_word(t, "允许"), 0)
  assert_eq(only_word(t, "拒绝"), 1)
  t.tap_text("查看步骤")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("共享调试") is Some(_))
}

///|
test "a request for a rig decided before it is seen: a line in its place, by how it went" {
  let t = chat_tester("chat-rig-granted")
  assert_true(t.find("已允许使用这台 station · 8 小时后失效") is Some(_))
  assert_eq(only_word(t, "允许"), 0)
  let t = chat_tester("chat-rig-away")
  assert_true(t.find("已批准，等它上线") is Some(_))
  let t = chat_tester("chat-rig-ended")
  assert_true(t.find("这台 station 的授权已结束：所有者已收回") is Some(_))
}

///|
test "a request for one device of the viewer's rig: the card names the device and its station; allowed, what is signed names the device" {
  let t = chat_tester("chat-rig-device")
  assert_true(t.find("允许这个对话的 agent 使用设备「开发板」（在 station「build-box」上）？") is Some(_))
  assert_true(t.find("给开发板刷新固件，看串口输出") is Some(_))
  let allow = t.words().filter(fn(x) { x.0 == "允许" })[0]
  t.tap(allow.1 + allow.3 / 2.0, allow.2 + allow.4 / 2.0)
  t.draw()
  let asked = @sffixture.fix_rig_asked
  assert_eq(asked.length(), 1)
  let ask = field(Some(asked[0]), "ask")
  assert_eq(text(ask, "device"), "1b2c3d4e5f607182")
  assert_eq(text(ask, "deviceName"), "开发板")
}
