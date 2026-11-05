///|
/// The ids of the chat's actions the bars hold now, in their order.
fn chat_acts_said(t : @ui.Tester) -> Array[String] {
  let said : Array[String] = []
  fn walk(j : Json) {
    match j {
      Object(o) => {
        match o.get("id") {
          Some(String(id)) if id.has_prefix("page/chat/") && !said.contains(id) => said.push(id)
          _ => ()
        }
        for _, v in o {
          walk(v)
        }
      }
      Array(a) => for v in a { walk(v) }
      _ => ()
    }
  }
  walk(@json.parse(t.nav_said()) catch { _ => Json::null() })
  said
}

///|
test "the top page switched to another chat and back again: the chat's actions its node handed at their cause are in the bars from the frame of the switch" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  let first = chat_acts_said(t)
  assert_true(first.contains("page/chat/info"), msg=first.to_string())
  open_chat({ station: "ws1/st1", session: "s-c2", title: "首页", station_name: "Willow" })
  t.frame()
  let other = chat_acts_said(t)
  assert_true(other.contains("page/chat/info"), msg="the switch's frame: \{other}")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  assert_eq(chat_acts_said(t), first)
}

///|
test "a chat's services coming: their switch in the system's bars at the change, no old frame built for it" {
  new_run()
  let jobs = @signals.signal(false)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard name == "chatJobs" && jobs.get() else { got }
      { ..got, value: Some({ "hasJobs": true, "jobs": [], "alarm": "" }) }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1, nav_able=true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  assert_false(chat_acts_said(t).contains("page/chat/jobs"))
  t.record_host()
  jobs.set(true)
  // (said to the system at the change, before any frame)
  assert_true(chat_acts_said(t).contains("page/chat/jobs"), msg=chat_acts_said(t).to_string())
  // (the frames the change asks for, as a host draws them: no step of the test's taken as an outside event)
  ignore(host_frames_till(t, t.time() + @ui.move_most_ms))
  let built = t.host_frames().filter(fn(f) { f.old_built }).map(fn(f) { f.why })
  assert_eq(built, [])
}
