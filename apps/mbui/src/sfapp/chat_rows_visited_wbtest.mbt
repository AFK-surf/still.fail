///|
/// A real chat page at the same end after visiting `visited` earlier positions. Count reads made when its next
/// message comes, not those needed to scroll there. The messages and the final visible window are the same.
fn arrival_after_visiting(visited : Int) -> (Int, (Int, Int), Array[(Double, Double, Double, Double)?], Bool, Double, Int) raise {
  new_run()
  let n = 360
  let all : Json = { "messages": Json::array(Array::makei(n, fn(i) { said_json(i + 1) })) }
  let rows = @rows.TopicList::new(["messages"], ["seq", "outgoing"], Some(all))
  let rest : Json = { "title": "整理发布清单", "thread": { "id": 1 }, "messages": Json::null(), "agents": [], "people": [] }
  let changed = @signals.signal(1)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
        { value: Some(rest), error: None, version: changed.get() }
      } else {
        (base.topic)(name, params)
      }
    },
    list: fn(name, _, _, _) { if name == "chat" { Some(rows) } else { None } },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let setup_at = t.time()
  let windows : Array[Int] = []
  for i in 0..<visited {
    t.scroll_to(n - 1 - i * 8)
    t.draw()
    let first = t.visible().0
    if !windows.contains(first) { windows.push(first) }
  }
  t.scroll_to(n + 1)
  t.draw()
  assert_true(t.time() < setup_at + 10000.0)
  t.frame_at(setup_at + 10000.0)
  let end = t.visible()
  let rects = [t.row(n - 1), t.row(n), t.row(n + 1)]
  let at_end = t.at_end()
  let at = t.time()
  let before = rows.work()
  @signals.start_batch()
  rows.take({
    "path": Json::array([Json::string("messages")]),
    "key": Json::array([Json::string("seq"), Json::string("outgoing")]),
    "why": Json::string("came"),
    "put": said_json(n + 1),
  }) |> ignore
  rows.come_in()
  changed.set(2)
  @signals.end_batch()
  t.frame()
  t.run_for(@sf.enter_ms)
  assert_true(t.find("第 \{n + 1} 句") is Some(_), msg="the latest message is visible after visiting \{visited}, was \{end}")
  let work = rows.work() - before
  println("visited=\{visited}, windows=\{windows.length()}, end=\{end}, rects=\{rects}, at_end=\{at_end}, at=\{at}, arrival reads=\{work}")
  (work, end, rects, at_end, at, windows.length())
}

///|
test "an arrival does not reread rows already scrolled out of the chat window" {
  let (direct, end0, rects0, follows0, at0, _) = arrival_after_visiting(0)
  let (wandered, end1, rects1, follows1, at1, windows) = arrival_after_visiting(30)
  assert_true(windows >= 20, msg="the scrolls visited different windows: \{windows}")
  assert_eq(end0, end1)
  assert_eq(rects0, rects1)
  assert_eq(follows0, follows1)
  assert_eq(at0, at1)
  assert_true(wandered <= direct + 50, msg="one arrival after visiting history: \{direct} vs \{wandered} reads")
}
