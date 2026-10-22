// References to other chats in the composer (chat_refs.mbt; Composer.kt ChatRefs, RefMarks, ChatRefMenu, markPasted).

///|
test "marks: where they are, the `@words` at the caret, the mark just before it" {
  assert_eq(ref_marks("看 @[首页] 和 @[x]。"), [(2, 7), (10, 14)])
  // a title of none, or with a new line in it, is no mark
  assert_eq(ref_marks("@[] @[a\nb]"), [])
  assert_eq(ref_at("看 @首页", 5), Some((2, "首页")))
  assert_eq(ref_at("@", 1), Some((0, "")))
  // not after a letter (an address), nor past a space
  assert_eq(ref_at("me@x", 4), None)
  assert_eq(ref_at("@a b", 4), None)
  assert_eq(ref_before("看 @[首页]", 7), Some(2))
  assert_eq(ref_before("看 @[首页] ", 8), None)
  assert_eq(inserted_range("ab", "aXYb"), Some((1, 3)))
  assert_eq(inserted_range("abc", "ac"), None)
}

///|
test "a mark drawn: the same letters in the same places, `[@` for `@[`, its brackets clear, the rest in the accent" {
  let (shown, spans) = (ref_look(0xE5704AFFL))("看 @[首页] 了")
  assert_eq(shown, "看 [@首页] 了")
  assert_eq(spans, [(2, 3, 0L), (3, 6, 0xE5704AFFL), (6, 7, 0L)])
}

///|
test "a chat's link, as one is copied: the chat it names, of this workspace only" {
  match linked_chat("https://app.still.fail/o/ws1/st1/ember%3Ac-1") {
    Some(l) => {
      assert_eq(l.station, "ws1/st1")
      assert_eq(l.id, "ember:c-1")
    }
    None => fail("not a chat's link")
  }
  match linked_chat("https://app.still.fail/w/ws1/s/st1/chats/s-c2?history=k&entry=3") {
    Some(l) => {
      assert_eq(l.id, "s-c2")
      assert_eq(l.history, "?history=k&entry=3")
    }
    None => fail("not a chat's page")
  }
  let refs = linked_refs("看 [首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 和 [别处](https://app.still.fail/w/ws9/s/st1/chats/x)", "ws1/st1")
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].1, "首页")
}

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
test "marks and `@words` as Android's regexes take them: 120 at most, `\\s` its ASCII spaces only" {
  let long = "@[" + "字".repeat(120) + "]"
  assert_eq(ref_marks(long), [(0, 123)])
  assert_eq(ref_marks("@[" + "字".repeat(121) + "]"), [])
  // a mark's title takes `@[`; the next mark after it
  assert_eq(ref_marks("@[a@[b] @[c]"), [(0, 7), (8, 12)])
  // U+3000 is no space to java.util.regex: not before an `@`, and in its words
  assert_eq(ref_at("看\u{3000}@x", 4), None)
  assert_eq(ref_at("@a\u{3000}b", 4), Some((0, "a\u{3000}b")))
  assert_eq(ref_at("看\t@x", 4), Some((2, "x")))
  // 40 letters at most after the `@`; brackets and `@` end it
  assert_eq(ref_at("@" + "a".repeat(40), 41), Some((0, "a".repeat(40))))
  assert_eq(ref_at("@" + "a".repeat(41), 42), None)
  assert_eq(ref_at("@a(b", 4), None)
  assert_eq(ref_at("@a@b", 4), None)
  // a caret past the words: at their end
  assert_eq(ref_at("@ab", 9), Some((0, "ab")))
  assert_eq(ref_before("@[a]@[b]", 8), Some(4))
  assert_eq(ref_before("@[a]x", 5), None)
  // one change replacing words: what went in
  assert_eq(inserted_range("abc", "aXYc"), Some((1, 3)))
  assert_eq(inserted_range("", "ab"), Some((0, 2)))
}

///|
test "a chat's link: its key decoded as UTF-8, one ill-formed kept as it is" {
  assert_eq(@codec.percent_decoded("%E9%A6%96%E9%A1%B5"), "首页")
  assert_eq(@codec.percent_decoded("a%20b"), "a b")
  assert_eq(@codec.percent_decoded("%E9%A6"), "%E9%A6")
  assert_eq(@codec.percent_decoded("100%"), "100%")
  assert_true(linked_chat("https://app.still.fail/o/ws1/st1") is None)
  assert_true(linked_chat("https://example.com/x") is None)
  match linked_chat("https://app.still.fail/o/ws1/st1/s-c2/") {
    Some(l) => assert_eq(l.id, "s-c2")
    None => fail("a trailing slash")
  }
}

///|
test "links pasted as Android's findAll takes them: past one that names no chat, none in a space" {
  let chat = "https://app.still.fail/w/ws1/s/st1/chats/s-c2"
  // `\\S+?` runs to the first `)`: the first's link takes in the second, and ends as a chat's page does, so the first
  // is that chat (titled x), the second not looked for inside it
  assert_eq(linked_refs("[x](y[b](" + chat + "))", "ws1/st1").map(fn(r) { (r.0, r.1) }), [((0, 55), "x")])
  // an execution history's end as Android's takes it, or no chat
  assert_true(linked_chat(chat + "?history=k&entry=x") is None)
  assert_true(linked_chat(chat + "?history=") is None)
  assert_eq(linked_refs("[x](a b) [首页](" + chat + ")", "ws1/st1").length(), 1)
  assert_eq(linked_refs("[首页](" + chat + ") [又](" + chat + ")", "ws1/st1").map(fn(r) { r.0 }), [(0, 51), (52, 102)])
  // of no workspace: none
  assert_eq(linked_refs("[首页](" + chat + ")", "st1").length(), 0)
}

///|
test "a kept draft with a chat's link in it: put back as it is, not taken as pasted" {
  let calls : Array[Made] = []
  let link = "[首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2)"
  let t = fake_core(calls, kept={ "text": "看 " + link, "quotes": [], "files": [] })
  t.draw()
  t.draw()
  assert_true(t.dump().contains("看 " + link))
  assert_eq(named(calls, "chat.ref").length(), 0)
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
  assert_eq(app.toast, "无法引用此对话：没有权限")
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@首页")
  // closed for this `@` until its words are gone
  assert_true(t.find("引用对话") is None)
  t.clear()
  t.type_text("@")
  assert_true(t.find("引用对话") is Some(_))
}
