// Back, the shell's one way in every tier (sfbase's shell.mbt back_step, go_back; docs/architecture.md, the tiers'
// table), with touch and with keyboard and mouse: laid out Small a page popped, a place's top page back to the chats,
// none at the chats'; on the tape the sidebar brought over from the chat, none with the chats' sidebar in use; laid
// out Large the chat popped to the list, a new chat beside it, and back from that none. A page's own back and close
// (its bar's back, 取消, 关闭) through the shell too (go_back, close_page).

///|
test "back laid out Small, a phone's and a narrow window's: the chat popped, 文件 back to the chats, none at the chats" {
  for case in [(2, 390.0, 844.0, "compact", "medium"), (0, 500.0, 800.0, "", "")] {
    let (platform, w, h, width, height) = case
    let at = "platform \{platform} \{w}"
    let t = tape_chat(platform, w, h, width~, height~)
    assert_eq(@sf.layout(w), Small, msg=at)
    assert_eq(app.nav.depth(), 2, msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(app.nav.depth(), 1, msg=at)
    assert_true(app.nav.top() == Home, msg=at)
    assert_false(@sfbase.back_step() is Some(_), msg=at)
    tap_said(t, "文件")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Files, msg=at)
    assert_true(t.takes_back(), msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(app.nav.depth(), 1, msg=at)
    assert_true(app.nav.top() == Home, msg=at)
    assert_false(@sfbase.back_step() is Some(_), msg=at)
  }
}

///|
test "back on the tape, a computer's and a tablet's: from the chat in use the sidebar over, the chat kept; then none" {
  for case in [(0, 720.0, 800.0, "", ""), (2, 690.0, 840.0, "medium", "medium")] {
    let (platform, w, h, width, height) = case
    let at = "platform \{platform} \{w}"
    let t = tape_chat(platform, w, h, width~, height~)
    assert_true(@sfdesk.wide.tape, msg=at)
    page_over(t, w)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg=at)
    assert_true(on_first_chat(), msg=at)
    assert_false(@sfbase.back_step() is Some(_), msg=at)
  }
}

///|
test "back laid out Large, a computer's and a tablet's: the chat popped to the list, a new chat beside it; then none" {
  for case in [(0, 1280.0, 800.0, "", ""), (2, 1024.0, 768.0, "expanded", "medium")] {
    let (platform, w, h, width, height) = case
    let at = "platform \{platform} \{w}"
    let t = tape_chat(platform, w, h, width~, height~)
    assert_eq(@sf.layout(w), Large, msg=at)
    assert_true(on_first_chat(), msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    // (the page beside the list is never empty: the web's WorkspaceHome, sfdesk's land)
    assert_true(app.nav.pages() == [Home, NewChat], msg=at)
    assert_false(@sfbase.back_step() is Some(_), msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.pages() == [Home, NewChat], msg=at)
  }
}

///|
test "a page closed through the shell: taken off where it lies with what is over it; not there, or the root, nothing" {
  new_run()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let read : Page = DriveRead({ station: "ws1/st1", root: Some("r"), path: "a.md" })
  app.nav.push(Chat(r))
  app.nav.push(read)
  assert_false(@sfbase.close_page(NewChat))
  assert_false(@sfbase.close_page(Home))
  assert_eq(app.nav.depth(), 3)
  assert_true(@sfbase.close_page(read))
  assert_true(app.nav.pages() == [Home, Chat(r)])
  app.nav.push(read)
  assert_true(@sfbase.close_page(Chat(r)))
  assert_true(app.nav.pages() == [Home])
}

///|
test "a phone's new chat: 取消 closes it through the shell, back to the chats" {
  let t = tape_chat(2, 390.0, 844.0, width="compact", height="medium")
  @sfbase.open_page(NewChat)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == NewChat)
  t.tap_text("取消")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
  assert_eq(app.nav.depth(), 2)
}
