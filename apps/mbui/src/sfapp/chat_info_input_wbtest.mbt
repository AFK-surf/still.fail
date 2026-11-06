///|
test "a chat info action opens its tab and closes the info at release, once, with no following frame" {
  for (label, tab) in [("Station 文件", "files"), ("图片、文件和链接", "things"), ("全部 4 个 PR", "things")] {
    for framed in [false, true] {
      new_run()
      let calls : Array[Made] = []
      let base = fixture("chat")
      let src : Source = {
        ..base,
        call: fn(name, params, done) {
          calls.push({ name, params, bytes: None, done, heard: None })
          (base.call)(name, params, done)
        },
      }
      let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
      open_chat(r)
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
      t.run_for(@ui.move_most_ms)
      t.click(Button, label="对话信息")
      t.run_for(@kit.pop_ms)
      let (x, y) = t.find(label).unwrap()
      t.touch_at(0, x, y, t.time())
      if framed { t.frame() }
      t.touch_at(2, x, y, t.time())
      assert_eq(@sfdesk.chat_pops_open().0, false, msg=label)
      assert_eq(side_now(r), ([tab], tab), msg=label)
      let opened = named(calls, "chat.tabs.open")
      assert_eq(opened.length(), 1, msg=label)
      assert_eq(text(Some(opened[0].params), "chat"), "ws1/st1:s-c1")
      t.run_for(dmax(@kit.presence_out_ms, @ui.move_most_ms))
      assert_eq(named(calls, "chat.tabs.open").length(), 1, msg="drawing does not repeat the action")
      if tab == "files" {
        let arrivals = named(calls, "drive.browse").filter(fn(call) {
          text(Some(call.params), "act") == "at"
        })
        assert_eq(arrivals.length(), 1, msg="rebuilding or retaining the tab tells its directory once")
      }
    }
  }
}
