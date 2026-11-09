// ⌘F in an open chat on 大屏 (sfpages' find.mbt find_bar, find_ask, find_move; sfbase's chat_list.mbt go_tos): its bar
// over the chat, what is typed looked for 120 ms after the last key (chat.find), where the reader is among what was
// found as the core says (chat.find.go: Enter the next, ⇧Enter and ↑ the one before), 无结果 for nothing; a message
// found out of the chat's window has the window moved about it (chat.around), once.

///|
/// The fixture's chat on 大屏 with a Mac's keys, its calls kept in `calls` and answered as the made-up core answers them;
/// `found`: what chat.find answers instead (None: the made-up core's own finding).
fn find_chat_tester(calls : Array[Made], found? : Json? = None) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match (name, found) {
        ("chat.find", Some(f)) => done(Ok(f))
        _ => (base.call)(name, params, done)
      }
    },
  }
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn find_typed(t : @ui.Tester, words : String) -> Unit {
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.type_text(words)
  t.draw()
}

///|
test "⌘F opens the chat's find bar; what is typed is looked for only 120 ms after the last key (chat.find), in the chat's thread" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  assert_true(t.find("在对话中查找") is None)
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在对话中查找") is Some(_))
  assert_true(@sfpages.find_chat() != "")
  t.type_text("截图")
  t.draw()
  assert_eq(named(calls, "chat.find").length(), 0)
  t.run_for(@sfpages.find_typing_ms)
  t.draw()
  let asked = named(calls, "chat.find")
  assert_true(asked.length() >= 1)
  assert_eq(text(Some(asked[0].params), "query"), "截图")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
}

///|
test "⌘F: what is found counted as the core says where the reader is (n/total); Enter the next (chat.find.go by 1), ⇧Enter the one before (by -1)" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  find_typed(t, "截图")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  let counted = fn() { t.words().filter(fn(w) { w.5 > 0.0 && w.0.contains("/") && w.0.length() <= 5 }).map(fn(w) { w.0 }) }
  assert_true(counted().length() == 1, msg="\{t.words().map(fn(w) { w.0 })}")
  let was = counted()[0]
  let goes = named(calls, "chat.find.go").length()
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  let moved = named(calls, "chat.find.go")
  assert_eq(moved.length(), goes + 1)
  assert_eq(number(Some(moved[moved.length() - 1].params), "by"), 1.0)
  assert_true(counted()[0] != was, msg="\{was} \{counted()}")
  t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  let moved = named(calls, "chat.find.go")
  assert_eq(number(Some(moved[moved.length() - 1].params), "by"), -1.0)
  assert_eq(counted()[0], was)
}

///|
test "⌘F: words no message has say 无结果, and its ways up and down are not pressed" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  find_typed(t, "没有这个词")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("无结果") is Some(_), msg="\{t.words().map(fn(w) { w.0 })}")
  let goes = named(calls, "chat.find.go").length()
  t.click(Button, label="下一个")
  t.draw()
  assert_eq(named(calls, "chat.find.go").length(), goes)
}

///|
test "⌘F: a message found out of the chat's window has the window moved about it (chat.around by its seq), asked once, no page before asked for it" {
  let calls : Array[Made] = []
  // (found in the page before the chat's first: seq -98)
  let t = find_chat_tester(calls, found=Some({
    "words": ["构建脚本"],
    "hits": [{ "seq": -98, "count": 1 }],
    "held": 30,
    "of": 30,
    "whole": true,
  }))
  find_typed(t, "构建脚本")
  t.run_for(@sfpages.find_typing_ms)
  for _ in 0..<4 {
    t.run_for(@ui.move_most_ms)
  }
  let around = named(calls, "chat.around")
  assert_eq(around.length(), 1, msg="\{calls.map(fn(m) { m.name })}")
  assert_eq(number(Some(around[0].params), "seq"), -98.0)
  assert_eq(number(Some(around[0].params), "thread"), 7.0)
  assert_eq(named(calls, "chat.older").length(), 0)
}
