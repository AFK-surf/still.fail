///|
test "an old natural-height agent sheet closed before its first frame does not read its topic" {
  new_run()
  let base = fixture("chat")
  let reads = Ref(0)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "agentCard" { reads.val += 1 }
      (base.topic)(name, params)
    },
  }
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    @sf.presented(c)
  }, w=390.0, h=844.0, platform=2)
  t.check_looks(false)
  t.draw()
  open_agent(src, chat, "agent1")
  @sf.close_presented_of(@sf.last_presented())
  t.draw()
  assert_eq(reads.val, 0)
  open_agent(src, chat, "agent1")
  t.draw()
  assert_true(reads.val > 0, msg="the body is read once the sheet is really built")
}
