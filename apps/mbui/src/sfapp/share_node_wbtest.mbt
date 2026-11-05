// 小屏: what another app shares in while the app is at rest is taken as the host says it, as a frame begins
// (signed_in_node's share_in_node, on_host_said), its sheet put up; closed, let go. Not when an old view under the
// pages happens to build next (narrow_under's share_in_frame before).

///|
test "小屏 at rest: shared in, its sheet up from the next frame; closed, what was shared let go" {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(share_in.shared.get() is None)
  t.share_in("列表滑动的十个细节 https://youtube.com/watch?v=1", title="列表滑动的十个细节")
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(share_in.shared.get() is Some(_), msg="taken")
  assert_true(t.find("发到") is Some(_), msg="its sheet up")
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(share_in.shared.get() is None, msg="let go as its sheet closed")
}

///|
test "小屏 at rest: shared in, taken as the next frame begins, one sheet put up; 新建对话, the sheet gone and the new chat up" {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  t.run_for(@ui.move_most_ms * 2.0)
  let before = @sf.last_presented()
  t.share_in("列表滑动的十个细节 https://youtube.com/watch?v=1", title="列表滑动的十个细节")
  t.draw()
  assert_true(share_in.shared.get() is Some(_), msg="taken as the next frame begins")
  assert_eq(@sf.last_presented() - before, 1, msg="one sheet put up, not one and another in its place")
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(t.find("发到") is Some(_), msg="its sheet up")
  t.tap_text("新建对话")
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(app.nav.top() is NewChat, msg="the new chat up")
  assert_true(t.find("发到") is None, msg="no sheet left up")
}
