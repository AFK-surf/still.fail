// What a draft refers to, shared before it goes (outside.mbt): over the fake core of composer_wbtest.mbt, whose calls
// the test answers, and over the fixture (its 个人 workspace's chats, chat_fixture.mbt fix_outside).

///|
/// On the frames' clock to where the sharing sheet rests (its spring and its scrim's fade, as @kit.sheet_rest says).
fn run_to_outside_rest(t : @ui.Tester) -> Unit raise {
  let end = @kit.sheet_rest("sf-present")
  if end < 0.0 || end > 1.0e300 {
    fail("the sharing sheet does not move (its rest: \{end})")
  }
  t.run_for(end - t.time())
}

///|
/// Another workspace's chat as the core's `chat.outsideRefs` names it.
fn outside_chat(id : String, title : String, may : Bool) -> Json {
  {
    "station": "ws2/st9",
    "id": Json::string(id),
    "title": Json::string(title),
    "workspace": "ws2",
    "workspaceName": "个人",
    "may": Json::boolean(may),
  }
}

///|
test "words with no reference go at once: the core is not asked what they refer to" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("没有引用的话")
  tap_send(t)
  assert_eq(named(calls, "chat.outsideRefs").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 1)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a reference to another workspace's chat: asked first, the sheet says whose, 分享并发送 shares it, then it goes" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("先看 @[季度路线图] 再定")
  tap_send(t)
  // nothing sent yet: the core asked what the words refer to, a second tap meanwhile nothing more
  tap_send(t)
  let asked = named(calls, "chat.outsideRefs")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "text"), "先看 @[季度路线图] 再定")
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(named(calls, "chat.send").length(), 0)
  (asked[0].done)(Ok({ "chats": [outside_chat("s-p1", "季度路线图", true)] }))
  t.draw()
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is Some(_))
  assert_true(t.find("季度路线图") is Some(_))
  // whose: 来自, then that workspace's mark (its letter, 个, where it has none) and its name
  assert_true(t.find("来自 ") is Some(_) && t.find("个") is Some(_) && t.find("个人") is Some(_))
  assert_true(t.find("你没有分享权限，需由发起人或管理员分享") is None)
  t.tap_text("分享并发送")
  // (which of them the viewer may share, and with which workspace, the core's: chat.outsideShare)
  let shared = named(calls, "chat.outsideShare")
  assert_eq(shared.length(), 1)
  let p = Some(shared[0].params)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(text(p, "text"), "先看 @[季度路线图] 再定")
  // not sent until it is shared
  assert_eq(named(calls, "chat.send").length(), 0)
  (shared[0].done)(Ok(Json::object({})))
  t.draw()
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "先看 @[季度路线图] 再定")
  let (_, words, _, _) = t.ime()
  assert_eq(words, "")
  // the sheet sinks away, the words wait for their row (which this core never gives), the composer's room let go
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a share that fails is said in the sheet: nothing goes, the words stay; 取消 leaves them as they were" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("对照 @[季度路线图]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [outside_chat("s-p1", "季度路线图", true)] }))
  t.draw()
  run_to_outside_rest(t)
  t.tap_text("分享并发送")
  (named(calls, "chat.outsideShare")[0].done)(Err({ "code": "forbidden", "message": "对方工作区不接受" }))
  t.draw()
  assert_true(t.find("分享失败：对方工作区不接受") is Some(_))
  assert_eq(named(calls, "chat.send").length(), 0)
  t.tap_text("取消")
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is None)
  assert_eq(named(calls, "chat.send").length(), 0)
  let (_, words, _, _) = t.ime()
  assert_eq(words, "对照 @[季度路线图]")
  // sent again: asked again
  tap_send(t)
  assert_eq(named(calls, "chat.outsideRefs").length(), 2)
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "none of them the viewer may share: each says so, and 仍然发送 sends it as it is" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("参考 @[预算草稿]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [outside_chat("s-p2", "预算草稿", false)] }))
  t.draw()
  run_to_outside_rest(t)
  assert_true(t.find("你没有分享权限，需由发起人或管理员分享") is Some(_))
  assert_true(t.find("分享并发送") is None)
  t.tap_text("仍然发送")
  assert_eq(named(calls, "chat.outsideShare").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 1)
  run_to_outside_rest(t)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a core that cannot say what the words refer to: they go as they are" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("看 @[季度路线图]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Err({ "code": "unknown_call", "message": "chat.outsideRefs" }))
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a new chat's first message is shared before it goes too, over the fixture's core" {
  let t = tester("home")
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text("按 @[季度路线图] 排一下")
  tap_send(t)
  // asked first: the page is still the new chat, the sheet over it
  assert_true(!(app.nav.top() is Chat(_)))
  run_to_outside_rest(t)
  // whose: 来自, then that workspace's mark (its letter, 个, where it has none) and its name
  assert_true(t.find("来自 ") is Some(_) && t.find("个") is Some(_) && t.find("个人") is Some(_))
  t.tap_text("分享并发送")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "new:1")
    _ => fail("not the chat")
  }
  assert_true(fix_xshared.contains("s-p1"))
}

///|
test "references the core says nothing of: the words go with no sheet" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("同一个工作区的 @[发布清单]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [] }))
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}
