// A chat's own keys on the wide frame (sfdesk chat_page.mbt chat_actions_node): done by the chat's page made as nodes at
// the key's moment, and chosen from the menu bar at the choice's.

///|
test "wide: ⌘F chosen from the menu bar opens the chat's find at once, no frame drawn for it first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfpages.find_chat(), "")
  @settings.ask_action("chat.find")
  assert_true(@sfpages.find_chat() != "")
  t.frame()
  assert_true(t.query(TextField, label="在对话中查找") is Some(_))
}

///|
test "wide: Space with no field focused gives the chat's composer the keyboard: what is typed next is its" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  t.run_for(@ui.move_most_ms)
  t.key_told(@ui.key_space, 0, t.time())
  t.run_for(@ui.move_most_ms)
  t.type_text("先看日志")
  t.run_for(@ui.move_most_ms)
  assert_eq(desk_words(src), "先看日志")
}
