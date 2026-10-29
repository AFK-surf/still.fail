// The chat's questions through the library's presenters (sheets.mbt open_rename, context.mbt open_context): its name
// asked (@sf.ask, an empty one said too: named anew), its agent's context compacted or cleared (@sf.panel), clearing
// asked first (@sf.confirm).

///|
test "renaming the chat: asked for its name, an empty one said too (named anew, as its note says)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_rename(decide_src.val.unwrap(), r, Some(7.0), "整理发布清单", from=Unanchored)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("重命名对话") is Some(_), msg="its question")
  for _ in 0..<12 {
    t.press("Backspace")
  }
  t.frame()
  t.tap_text("保存")
  t.run_for(@ui.move_most_ms)
  let sent = named(calls, "chat.rename")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "title"), "")
  assert_eq(text(Some(sent[0].params), "session"), "s-c1")
}

///|
test "an agent's context: its tile opens what can be done; clearing it asked first, cleared once it is said" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent-unsaid")
  let tile = if t.find("压缩上下文") is Some(_) { "压缩上下文" } else { "上下文" }
  t.tap_text(tile)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting(), msg="what can be done to it")
  t.tap_text("清空上下文")
  // (to where the presenters' sheet rests: the panel's gone down, the question's up in its place)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // asked first: nothing cleared yet, its action the one 清空上下文 there is
  assert_true(t.find("清空此 agent 的上下文？") is Some(_), msg="the question")
  assert_eq(t.locate("清空上下文").length(), 1)
  assert_eq(named(calls, "session.clear").length(), 0)
  t.tap_text("清空上下文")
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "session.clear").length(), 1)
}

///|
test "a list's panel as tall as what it holds, its share of the window the most it comes to, past that scrolling" {
  // (the letters' sheet: 80% of the window at most)
  let calls : Array[Made] = []
  // two chats written with: the sheet as tall as they are, no room under them to spare
  let t = decide_core(calls, "chat-letters")
  sheet_rested(t, "sf-present")
  let (_, sy, _, sh) = t.get(@ui.Dialog).rect
  let (_, ly, _, lh) = t.rect_of("BFT 备份尺寸分析").unwrap()
  assert_true(sh < 844.0 * 0.8 - 100.0, msg="short: \{sh}")
  assert_true(sy + sh - (ly + lh) < 120.0, msg="under its last: \{sy + sh - (ly + lh)}")
  // thirty: the sheet at its share, the last of them under its foot, scrolled to
  let t = decide_core(calls, "chat-letters-many")
  sheet_rested(t, "sf-present")
  let (_, _, _, sh) = t.get(@ui.Dialog).rect
  assert_true((sh - 844.0 * 0.8).abs() < 2.0, msg="capped: \{sh}")
  assert_true(t.find("往来的对话 1") is Some(_))
  assert_true(t.find("往来的对话 30") is None, msg="its last under its foot")
}
