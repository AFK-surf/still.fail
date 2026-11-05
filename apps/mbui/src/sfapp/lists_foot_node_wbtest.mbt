// The sidebar's foot with no bell in the rail (lists_foot_node): what is wrong with the stations, leading to them, and
// 运行中 N, its list over it; made of nodes, nothing of it an old view hosted.

///|
/// A wide window's Home with its jobs left up long and Maple offline, the rail without its bell (its places but 待处理).
fn foot_tester(calls : Array[Made]) -> @ui.Tester {
  wide_tester(calls, mode="home-jobs", wrap=fn(base) {
    {
      ..base,
      topic: fn(name, params) {
        let r = (base.topic)(name, params)
        match (name, r.value) {
          ("prefs", Some(Object(m))) => {
            let o = m.copy()
            o["railView"] = { "all": { "items": ["chats", "files", "stations"] } }
            { ..r, value: Some(Json::object(o)) }
          }
          ("chats", Some(v)) => { ..r, value: Some(@sffixture.fix_with_trouble(v, params)) }
          _ => r
        }
      },
    }
  })
}

///|
/// What the foot draws: its words (y past `from`) where they stand.
fn foot_words(t : @ui.Tester, from : Double) -> Array[(String, Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.2 >= from && w.1 >= 48.0 && w.1 < 460.0 }).map(fn(w) { (w.0, w.1, w.2, w.3, w.4) })
}

///|
test "wide: the sidebar's foot without the bell: Maple offline leads to the stations, 运行中 N opens its list, no old view hosted" {
  let none = wide_tester([], mode="home").old_views_hosted()
  let calls : Array[Made] = []
  let t = foot_tester(calls)
  t.run_for(@ui.move_most_ms)
  let foot = foot_words(t, 700.0)
  assert_true(foot.iter().any(fn(w) { w.0 == "Maple 离线" }), msg="\{foot}")
  assert_eq(foot.length(), 2, msg="\{foot}")
  assert_eq(t.old_views_hosted(), none)
  // 运行中 N: its list over it
  let chip = foot.iter().find_first(fn(w) { w.0 != "Maple 离线" }).unwrap()
  t.tap(chip.1 + chip.3 / 2.0, chip.2 + chip.4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Willow · 整理发布清单") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "wide: the sidebar's foot's Maple offline leads to the stations" {
  let t = foot_tester([])
  t.run_for(@ui.move_most_ms)
  let m = foot_words(t, 700.0).iter().find_first(fn(w) { w.0 == "Maple 离线" }).unwrap()
  t.tap(m.1 + m.3 / 2.0, m.2 + m.4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.side_place() == "stations", msg=@sfdesk.side_place())
}
