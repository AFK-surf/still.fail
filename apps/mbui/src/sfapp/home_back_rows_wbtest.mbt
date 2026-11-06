// Back to the chats from a chat opened from them: the chats' rows drawn again where they were (the film of switching
// chats, scripts/bench/switch.drive: 整理发布清单 opened, back, 盯着 CI found again).

///|
test "back to the chats from a chat opened from them: its rows drawn again, found where they were" {
  for platform in [0, 2] {
    let at = "platform \{platform}"
    let src = fixture_app("")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
    t.run_for(500.0)
    let before = t.find("盯着 CI，绿了告诉我")
    let word = fn() { t.words().filter(fn(w) { w.0 == "盯着 CI，绿了告诉我" }) }
    let word_before = word()
    assert_true(before is Some(_), msg="\{at}: its row before")
    t.tap_text("整理发布清单")
    t.run_for(900.0)
    assert_true(app.nav.depth() == 2, msg="\{at}: the chat open")
    t.back()
    t.run_for(900.0)
    assert_true(app.nav.top() == Home, msg="\{at}: back at the chats")
    let after = t.find("盯着 CI，绿了告诉我")
    if after != before {
      println("\{at}: found \{before} before, \{after} after; drawn \{word_before} before, \{word()} after")
    }
    assert_eq(after, before, msg="\{at}: its row drawn again where it was")
  }
}
