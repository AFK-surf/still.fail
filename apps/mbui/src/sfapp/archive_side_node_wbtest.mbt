// 已归档 as the sidebar's list made of nodes (archive_pane_node): open, nothing of it an old view hosted.

///|
test "wide: 已归档's list hosts no old view: open, its newest beside it, as many hosted as the same chat open beside the chats' list" {
  let t = wide_tester([])
  t.frame()
  app.nav.push(Archived)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("搜索归档") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  let r = match app.nav.top() {
    Chat(r) => r
    _ => fail("the newest not open")
  }
  let archived = t.old_views_hosted()
  // (the same chat beside the chats' list: what is hosted there but the list)
  let t = wide_tester([])
  t.frame()
  app.nav.push(Chat(r))
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(archived, t.old_views_hosted())
}
