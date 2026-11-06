// The retained Home row must use the operation supplied by longJobs for screens as well as the original job stop.

///|
test "a retained long-running row closes a simulator or disconnects a view with its own arguments" {
  let examples : Array[(Json, String, String, Json)] = [
    (
      @sffixture.long_screen("screen:simulator:A", "Demo", "Willow", "5 小时", "screen.close", "simulator:A", "", "关闭"),
      "关闭 Demo",
      "screen.close",
      { "station": "ws1/st1", "screen": "simulator:A" },
    ),
    (
      @sffixture.long_screen("view:desktop/v1", "Display", "Willow", "2 小时", "screen.endView", "desktop", "v1", "断开"),
      "断开 Display",
      "screen.endView",
      { "station": "ws1/st1", "screen": "desktop", "view": "v1" },
    ),
    (@sffixture.long_job(), "停止", "job.stop", { "station": "ws1/st1", "id": "j-web" }),
  ]
  for (job, label, call, params) in examples {
    new_run()
    let calls : Array[Made] = []
    let base = fixture("home")
    let src : Source = {
      ..base,
      call: fn(name, args, done) {
        calls.push({ name, params: args, bytes: None, done, heard: None })
      },
    }
    let t = @ui.Tester::new(
      fn(_) { },
      tree=fn(root) { root.box(fn(row) { open_job_row_node(row, src, @signals.signal(job)) }) |> ignore },
      w=390.0, h=100.0, platform=2,
    )
    t.click(Button, label~)
    assert_eq(named(calls, call).length(), 1, msg=label)
    assert_eq(named(calls, call)[0].params, params, msg=label)
    assert_eq(calls.length(), 1, msg="only the intended action is called")
  }
}

///|
test "narrow Home lists long-running screens and closes the chosen one" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home-jobs-screens", w=390.0, h=2000.0, platform=2)
  t.frame()
  assert_true(t.find("长时间开着的模拟器 · 2") is Some(_))
  t.click(Button, label="关闭 Demo iPhone · iOS 27.2")
  assert_eq(named(calls, "screen.close").length(), 1)
  assert_eq(named(calls, "screen.close")[0].params, { "station": "ws1/st1", "screen": "simulator:A" })
}
