// What the app asks the core of the connects (the user, 2026-11-10: a list's item carries what its row shows; a page of
// one thing asks that thing's own topic): 连接 and the settings their rows (`connects`), never one whole; a connect's
// page that connect alone (`connect`), and a single-session connect's page, while its 更换 row shows, the sessions its
// choice of one lists (`connectCandidates`), so the choice opens on them whole; no other page and no list asks those.
// Over the settings' made-up core (its connects answered as the core answers: the settings' fixture_connects.mbt), what
// the client sent it (asked_of: station_asks_wbtest.mbt).

///|
/// The settings' made-up core, the single-session connect k2's choice listing one session it could go into.
fn connect_candidates_said(base : Source) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "connectCandidates" && params.get("id") is Some(String("k2")) {
        let one : Json = {
          "key": "s-c9",
          "titleText": "上周的值班交接",
          "description": "单会话 · 值班机器人 · 3 轮 · 昨天",
          "current": false,
        }
        return { value: Some({ "candidates": [one] }), error: None, version: 1 }
      }
      base.topic(name, params).get().snapshot()
    },
  }
}

///|
/// A phone over the settings' made-up core answering `place_core_soon_ms` late, a page of the settings open (`page`, as
/// open_setting names it): every subscription the client sent said in `said` as `<topic> <params>`.
fn connect_asked(said : Array[String], page : String) -> @ui.Tester {
  new_run()
  let heard = fn(h : String) {
    guard h.has_prefix("out ") else { return }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => return }
    guard j is Object(m) && m.get("subscribe") is Some(Object(sub)) && sub.get("topic") is Some(String(topic)) else {
      return
    }
    let rest = sub.to_array().filter(fn(kv) { kv.0 != "topic" })
    said.push(topic + " " + Json::object(Map::from_array(rest)).stringify())
  }
  let src = round_trip_again(connect_candidates_said(fixture("settings")), place_core_soon_ms, heard~)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=4000.0)
  open_setting(page)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  t
}

///|
test "连接 open: the connects' rows subscribed, no connect whole, nor what a connect's choice of a session lists" {
  let said : Array[String] = []
  let t = connect_asked(said, "connects")
  assert_true(asked_of(said, "connects").contains("connects {\"scope\":\"ws1\",\"mine\":false}"), msg="\{Repr(said)}")
  assert_eq(asked_of(said, "connect"), [])
  assert_eq(asked_of(said, "connectCandidates"), [])
  assert_true(t.find("星火助手") is Some(_), msg="its rows show")
}

///|
test "a single-session connect's page open: that connect and what its choice of a session lists, both before 更换 is pressed" {
  let said : Array[String] = []
  let t = connect_asked(said, "connect:ws1/st1#k2")
  let asked = asked_of(said, "connect")
  assert_eq(asked.length(), 1, msg="\{Repr(said)}")
  assert_true(asked[0].contains("\"station\":\"ws1/st1\"") && asked[0].contains("\"id\":\"k2\""), msg=asked[0])
  let chose = asked_of(said, "connectCandidates")
  assert_eq(chose.length(), 1, msg="\{Repr(said)}")
  assert_true(chose[0].contains("\"station\":\"ws1/st1\"") && chose[0].contains("\"id\":\"k2\""), msg=chose[0])
  assert_true(t.find("值班机器人") is Some(_), msg="its page shows it")
  // (the choice opens on what its page asked: nothing more asked, the session it could go into listed)
  t.tap_text("更换")
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  assert_eq(asked_of(said, "connectCandidates").length(), 1, msg="\{Repr(said)}")
  assert_true(t.find("单会话 · 值班机器人 · 3 轮 · 昨天") is Some(_), msg="the session it could go into listed")
  assert_eq(asked_of(said, "connect").length(), 1, msg="the page's own ask not made again")
}

///|
test "a multi-session connect's page open: that connect alone, nothing of a choice of a session it has not" {
  let said : Array[String] = []
  let t = connect_asked(said, "connect:ws1/st1#k1")
  let asked = asked_of(said, "connect")
  assert_eq(asked.length(), 1, msg="\{Repr(said)}")
  assert_true(asked[0].contains("\"station\":\"ws1/st1\"") && asked[0].contains("\"id\":\"k1\""), msg=asked[0])
  assert_eq(asked_of(said, "connectCandidates"), [])
  assert_true(t.find("Slack 里问的报销流程") is Some(_), msg="its page shows its sessions")
}
