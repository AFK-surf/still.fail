// References to other chats in the phone's composer (chat_refs.mbt over sfbase's refs.mbt; Composer.kt ChatRefMenu,
// markPasted): what the field holds read as the core reads it (its answers kept, src/sfkept).

///|
test "`@` and words: the chats they find over the composer; one picked goes in as its mark, a backspace takes it whole" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("看 @首页")
  assert_true(t.find("引用对话") is Some(_))
  // the workspace's chats with the words in their title, not the one written in
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
test "`@` and words: the workspace's other stations' chats too, each with its station's tag after its title; this one's with none" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  // written in a chat of Studio's (ws1/st1); 夜里的构建又失败了 is MBA's (ws1/st2)
  t.type_text("@的")
  // (then when it was last active)
  assert_true(after_on_its_row(t, "夜里的构建又失败了") == ["MBA", "15 分钟前"], msg=about_its_row(t, "夜里的构建又失败了"))
  assert_true(after_on_its_row(t, "首页的列表改成按天分组") == ["8 分钟前"], msg=about_its_row(t, "首页的列表改成按天分组"))
  // a finger's row: 44 high at least (Theme::rows pick)
  let (_, _, _, high) = t.get(Button, label="夜里的构建又失败了").rect
  assert_true(high >= 44.0, msg="\{high}")
  t.tap_text("夜里的构建又失败了")
  t.draw()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "ws1/st2")
}

///|
/// The words drawn after the title `title` on its row (centred on its line, right of where it starts), left to right.
fn after_on_its_row(t : @ui.Tester, title : String) -> Array[String] {
  let words = t.words()
  guard words.iter().find_first(fn(w) { w.0 == title }) is Some((_, x, y, _, h, _)) else { return ["(no \{title})"] }
  let mid = y + h / 2.0
  let after = words.filter(fn(o) { o.0 != title && o.1 > x && (o.2 + o.4 / 2.0 - mid).abs() < 1.0 })
  after.sort_by(fn(a, b) { a.1.compare(b.1) })
  after.map(fn(o) { o.0 })
}

///|
/// What is drawn about the title `title`'s line (within 16 of it), with where, for a failure to say.
fn about_its_row(t : @ui.Tester, title : String) -> String {
  let words = t.words()
  guard words.iter().find_first(fn(w) { w.0 == title }) is Some((_, _, y, _, h, _)) else { return "(no \{title})" }
  words.filter(fn(o) { (o.2 + o.4 / 2.0 - (y + h / 2.0)).abs() < 16.0 }).map(fn(o) { "\{o.0}@\{o.1},\{o.2} \{o.3}x\{o.4} a\{o.5}" }).join(" | ")
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
test "`@` with a title longer than its row has room for: the title cut short, when it was last active whole after it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  // (a narrow phone: the menu as wide as the composer, less than the row would need)
  t.resize(240.0, 640.0)
  t.tap_text("发消息")
  t.type_text("看 @首页")
  let words = t.words()
  guard words.iter().find_first(fn(w) { w.0 == "首页的列表改成按天分组" }) is Some((_, title_x, title_y, title_w, _, _)) else {
    fail("no title")
  }
  guard words.iter().find_first(fn(w) { w.0 == "8 分钟前" && w.2 - title_y < 20.0 && title_y - w.2 < 20.0 })
    is Some((_, when_x, _, _, _, _)) else {
    fail("no when")
  }
  assert_true(title_w > 0.0)
  assert_true(title_x + title_w <= when_x)
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
test "words sent with a mark draw it as the field did, as their message will: never its brackets on the way" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.paste("[首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2)")
  t.type_text(" 吧")
  t.draw()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  (made[0].done)(Ok({ "mark": "@[首页]" }))
  t.draw()
  t.draw()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@[首页] 吧")
  tap_send(t)
  // (what it refers to is of this workspace: nothing to share first)
  let asked = named(calls, "chat.outsideRefs")
  assert_eq(asked.length(), 1)
  (asked[0].done)(Ok(Json::object({})))
  t.draw()
  // sent as written (the core makes the mark its link), its row drawing the mark from the frame it is sent
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_eq(text(Some(named(calls, "chat.send")[0].params), "text"), "@[首页] 吧")
  match sending_of("ws1/st1\u{1}s-c1") {
    [l] => assert_eq(sent_marks(l.row), [(0, 5)])
    _ => fail("not in the list")
  }
  t.draw()
  assert_true(t.find("@[首页]") is None)
  t.run_for(flight_ms)
  assert_true(t.find("@[首页]") is None)
  assert_true(t.find("首页") is Some(_))
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
  assert_eq(app.toast.get().words, "无法引用「首页的列表改成按天分组」：没有权限")
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@首页")
  // closed for this `@` until its words are gone
  assert_true(t.find("引用对话") is None)
  t.clear()
  t.type_text("@")
  assert_true(t.find("引用对话") is Some(_))
}
