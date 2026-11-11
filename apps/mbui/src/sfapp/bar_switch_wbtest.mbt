// The bottom bar on 小屏 going down out of the way under a chat page coming in, the workspace switched meanwhile: it
// comes back from where it is then, set out at the switch's moment, never put back in its place in one frame (till
// 2026-11-12 the chats' lists of the new workspace's Home, made by the switch, asked for a moment long gone, and what was
// told with it, the bar's way back among it, was set out then: drawn back whole in the switch's frame).

///|
test "bottom bar: a workspace switched as a chat page comes in on 小屏, the bar going down comes back from where it is, from the switch's moment" {
  new_run()
  let src = fixture("home-pins")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(bar.vis.at(t.time()).0, 1.0)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @ui.view_tree().unwrap().event(t.time(), fn() { open_page(Chat(r)) })
  t.frame()
  // (a while into its way down, which is bar_hide_ms long)
  t.run_for(bar_hide_ms / 2.0)
  let at = t.time()
  let was = bar.vis.at(at).0
  assert_true(was > 0.1 && was < 0.95, msg="going down: \{was}")
  @ui.view_tree().unwrap().event(at, fn() { @sfpages.switch_workspace(src, "ws2") })
  // (drawn on its way back: at a rate, each frame judged; the bar is told nothing more meanwhile)
  t.run_for(@ui.move_most_ms)
  assert_eq(bar.vis.at(t.time()).0, 1.0)
  // (its way back set out at the switch, from where it was then: a frame on, still on its way)
  assert_eq(bar.vis.target, 1.0)
  assert_eq(bar.vis.start, at)
  assert_true((bar.vis.from - was).abs() < 0.000001, msg="set out from \{bar.vis.from}, not \{was}")
  let next = bar.vis.at(at + 1000.0 / 60.0).0
  assert_true(next < 0.95, msg="a frame on: \{next}, from \{was}")
}
