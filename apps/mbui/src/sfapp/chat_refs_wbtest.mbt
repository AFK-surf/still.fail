// References to other chats in the phone's composer (chat_refs.mbt over sfbase's refs.mbt; Composer.kt ChatRefMenu,
// markPasted): what the field holds read as the core reads it (its answers kept, src/sfkept).

///|
test "`@` and words: the chats they find over the composer; one picked goes in as its mark, a backspace takes it whole" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("看 @首页")
  assert_true(t.find("引用对话") is Some(_))
  // this station's chats with the words in their title, not the one written in
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  t.tap_text("首页的列表改成按天分组")
  t.draw()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  (made[0].done)(Ok({ "mark": "@[首页的列表改成按天分组]" }))
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "看 @[首页的列表改成按天分组] ")
  // the menu closed for this `@`
  assert_true(t.find("引用对话") is None)
  t.backspace()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "看 @[首页的列表改成按天分组]")
  t.backspace()
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "看 ")
}

///|
test "`@` with nothing found says so; another workspace's chat says whose" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("@没有这个")
  assert_true(t.find("没有标题匹配的对话") is Some(_))
  for _ in 0..<4 {
    t.backspace()
  }
  t.type_text("路线")
  assert_true(t.find("季度路线图") is Some(_))
  assert_true(t.find_last("个人") is Some(_))
}

///|
test "a link pasted, written after before the core makes its mark: the mark where the link is now" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.paste("[首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2)")
  t.draw()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
  assert_eq(text(Some(made[0].params), "id"), "s-c2")
  assert_eq(text(Some(made[0].params), "title"), "首页")
  t.type_text(" 吧")
  (made[0].done)(Ok({ "mark": "@[首页]" }))
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@[首页] 吧")
  // no history in the link: nothing more kept
  assert_eq(named(calls, "chat.refs").length(), 0)
}

///|
test "a link to an execution history: its mark once the core keeps that link, else the link as it is" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.paste("[首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2?history=k&entry=3)")
  t.draw()
  (named(calls, "chat.ref")[0].done)(Ok({ "mark": "@[首页]" }))
  t.draw()
  let kept = named(calls, "chat.refs")
  assert_eq(kept.length(), 1)
  assert_eq(
    kept[0].params.stringify(),
    ({ "links": [["首页", trim_slash(cloud_origin()) + "/w/ws1/s/st1/chats/s-c2?history=k&entry=3"]] } : Json).stringify(),
  )
  // not yet: the link still there
  let (_, words, _, _) = t.ime()
  assert_true(words.has_prefix("[首页]("))
  (kept[0].done)(Err({ "message": "x" }))
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_true(words.has_prefix("[首页]("))
  // pasted again, kept this time
  t.clear()
  t.paste("[首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2?history=k&entry=3)")
  t.draw()
  let made = named(calls, "chat.ref")
  (made[made.length() - 1].done)(Ok({ "mark": "@[首页]" }))
  t.draw()
  let kept = named(calls, "chat.refs")
  (kept[kept.length() - 1].done)(Ok(Json::object({})))
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@[首页]")
}

///|
test "a chat picked the core cannot make a mark of: a toast says why, the `@words` stay" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("@首页")
  t.tap_text("首页的列表改成按天分组")
  t.draw()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "into"), "ws1")
  (made[0].done)(Err({ "message": "没有权限" }))
  t.draw()
  assert_eq(app.toast, "无法引用「首页的列表改成按天分组」：没有权限")
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@首页")
  // closed for this `@` until its words are gone
  assert_true(t.find("引用对话") is None)
  t.clear()
  t.type_text("@")
  assert_true(t.find("引用对话") is Some(_))
}
