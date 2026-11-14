// An agent's line on the chat's page made with its inside nodes (chat_body_node's, working_said_node): its first words
// come in a glyph at a time from the moment its row came into the list by data (the list's `comes`, asked at its
// cause), as the old page's did; there as the chat opened, they are there whole.

///|
test "chat as nodes: an agent's line come by data: its first words arrive a glyph at a time, then whole" {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  let words = tr("android-chat.chat.working")
  // (as the line is first seen: some of its glyphs further in than others)
  let alphas = activity_first_alphas(t, words)
  assert_true(alphas.length() > 1 && alphas.iter().any(fn(a) { a != alphas[0] }), msg="\{Repr(alphas)}")
  t.run_for(@ui.move_most_ms + @sfbase.glyph_line_in_ms)
  let alphas = activity_glyph_alphas(t, words)
  assert_true(alphas.length() > 1 && alphas.iter().all(fn(a) { a == alphas[0] && a > 0L }), msg="\{Repr(alphas)}")
}

///|
test "chat as nodes: an agent's line there as the chat opened: its words whole from the first frame they are drawn" {
  let src = fixture_app("chat-working")
  @sfbase.chat_page_nodes.set(true)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let words = @sffixture.working_step
  let mut seen = false
  for _ in 0..<12 {
    t.run_for(activity_look_ms)
    let alphas = activity_glyph_alphas(t, words)
    if alphas.length() > 1 {
      assert_true(alphas.iter().all(fn(a) { a == alphas[0] }), msg="\{Repr(alphas)}")
      seen = true
    }
  }
  assert_true(seen, msg="its words never drawn")
}
