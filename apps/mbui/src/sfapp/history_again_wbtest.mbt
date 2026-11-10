// An agent's history opened again: its steps read from the source of the page showing it now, not from the one that
// showed it before, which ended with it (the steps waited in their bones for ever, 2026-11-09).

///|
test "an agent's history opened again after going back from it shows its steps" {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(older_history(4)), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 4 页第 29 条") is Some(_), msg="opened")
  @sfbase.go_back() |> ignore
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 4 页第 29 条") is None, msg="gone back")
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 4 页第 29 条") is Some(_), msg="opened again")
}
