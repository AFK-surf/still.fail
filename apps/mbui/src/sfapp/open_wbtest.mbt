// Pages open what they open through the shell (sfbase's Shell: @sfbase.open_page, open_detail); where it goes is the
// layout's at that moment (docs/architecture.md, the pane table), never the page's.

///|
/// The fixture's chat open in a window `w` × `h` of `platform`, and what it is over.
fn open_tester(w : Double, h : Double, platform : Int) -> (@ui.Tester, Source, ChatRef) {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  (t, src, r)
}

///|
test "an agent's history a page asks of its chat: laid out Small its page over the chat; wide, the chat's side panel's tab" {
  let (t, src, r) = open_tester(390.0, 844.0, 2)
  open_detail(src, r, "s-c1")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is History(_, "s-c1", None), msg="the history's page")
  let (t, src, r) = open_tester(1280.0, 800.0, 0)
  open_detail(src, r, "s-c1")
  t.frame()
  assert_true(app.nav.top() == Chat(r), msg="the chat's page still")
  assert_eq(side_now(r), (["s-c1"], "s-c1"))
}

///|
test "a new chat opened: laid out Small it rises from the foot over the page; wide, it is the page" {
  let (t, _, _) = open_tester(390.0, 844.0, 2)
  open_page(NewChat)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is NewChat && app.nav.risen())
  let (t, _, _) = open_tester(1280.0, 800.0, 0)
  open_page(NewChat)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is NewChat && !app.nav.risen())
}
