// A run of the app begins at one moment (sf's run_begins.mbt): where it is begun before its Tester (new_run), at that
// moment, and not again as its Tester is made. Both halves at once, so that neither is mended without the other: what
// the run before left open is gone as the next begins, and what the next opened before its Tester is still there.

///|
/// The app on a phone's window over the made-up core's chats.
fn rb_tester() -> @ui.Tester {
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a run of the app begun before its Tester: the menu the run before left open gone as it begins, the one it opened before its Tester still open once it is made" {
  // (a run that leaves a menu open)
  new_run()
  let first = rb_tester()
  @sf.menu([Some(@sf.menu_item_of("上一次的菜单", fn() {  }))], from=@sf.at_point(100.0, 300.0))
  first.run_for(@ui.move_most_ms)
  assert_true(first.find("上一次的菜单") is Some(_), msg="the first run's menu drawn")
  // (the next begun before its Tester, a menu opened then)
  new_run()
  assert_false(@sf.presenting(), msg="gone as the next run begins")
  @sf.menu([Some(@sf.menu_item_of("这一次的菜单", fn() {  }))], from=@sf.at_point(100.0, 300.0))
  let next = rb_tester()
  assert_true(@sf.presenting(), msg="what this run opened before its Tester still presented")
  assert_true(next.find("这一次的菜单") is Some(_), msg="and drawn")
  assert_true(next.find("上一次的菜单") is None)
}
