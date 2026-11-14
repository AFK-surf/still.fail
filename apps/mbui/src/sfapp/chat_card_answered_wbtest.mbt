// An options card under the agent's last post, answered at the list's foot, on the chat's page made as nodes with its
// list's rows on the host's pixels (小屏 and 大屏, where the post sits beside its avatar): the options close and how it
// went comes in their place, the answer's key coming at the foot as well, or none. From the press to rest, what is over
// the card never steps against the way it goes, and the line saying how it went never goes back: what closes inside
// the row is laid on the grid as it goes (mbui's flex Style come_grid), so the row put on the grid round it goes one
// way with it, the line under it too. Looked at every 10 ms.

///|
/// The post asking, its options; its words; the line saying how it went; the answer as sent.
let ca_post : String = "你在手机上试一下新的列表，有问题截个图给我。"

///|
let ca_said : String = "你 选择了「一起换」"

///|
let ca_answer : String = "一起换"

///|
/// The fixture's chat, its agent's last post asking with options (seq 12) while `answered` is false; answered, its
/// decision says so, and where `key` the answer comes at its foot as one's own words (seq 13). On `screen`, rows on
/// pixels, at rest.
fn ca_open(screen : (String, Double, Double, Int), answered : @signals.Signal[Bool], key : Bool) -> @ui.Tester {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "decision.answer" | "session.warm" | "client.focus" | "chat.place" | "draft.get" | "draft.put" =>
          done(Ok(Json::object({})))
        _ => (base.call)(name, params, done)
      }
    },
    topic_read: fn(name, params) {
      let tp = base.topic(name, params).get().snapshot()
      guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      let done = answered.get()
      let options : Json = [
        { "label": "先不换", "detail": "这次只改列表，截图下次再说" },
        { "label": ca_answer, "detail": "把首页和聊天页的截图都更新", "recommended": true },
      ]
      let decision : Json = if done {
        { "resolved": true, "chosen": ca_answer, "text": ca_said }
      } else {
        { "resolved": false }
      }
      all.push(
        @sffixture.msg(12, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), ca_post, "1 分钟前", {
          "card": { "type": "options", "assigneeText": "等 林 决定", "options": options },
          "decision": decision,
          "asked": !done,
        }),
      )
      if done && key {
        all.push(@sffixture.msg(13, "person", @sffixture.by_person("林"), ca_answer, "刚刚", { "mine": true }))
      }
      o["messages"] = Json::array(all)
      { ..tp, value: Some(Json::object(o)), version: tp.version + (if done { 1 } else { 0 }) }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Where among `seen` (a place at each look, none where not drawn) it steps against the way it went first, by more than
/// a hundredth of a point: none, or where.
fn ca_back(seen : Array[Double?]) -> String? {
  let mut way = 0.0
  let mut was : Double? = None
  for i, y in seen {
    match (was, y) {
      (Some(a), Some(b)) => {
        let d = b - a
        if way == 0.0 && d.abs() > 0.01 {
          way = if d > 0.0 { 1.0 } else { -1.0 }
        } else if d * way < -0.01 {
          return Some("look \{i}: \{a} to \{b}, against the way it went")
        }
      }
      _ => ()
    }
    if y is Some(_) {
      was = y
    }
  }
  None
}

///|
test "an options card answered at the list's foot, rows on pixels, 小屏 and 大屏, its answer's key coming and none: from the press to rest nothing over the card steps against the way it goes, and how it went never goes back" {
  for case in [(cr_screens[0], true), (cr_screens[1], true), (cr_screens[0], false), (cr_screens[1], false)] {
    let (screen, key) = case
    let answered = @signals.signal(false)
    let t = ca_open(screen, answered, key)
    guard t.find_last(ca_answer) is Some((x, y)) else { fail("\{screen.0}: no option \{ca_answer}") }
    t.tap(x, y)
    t.draw()
    answered.set(true)
    t.draw()
    let over = []
    let said = []
    let end = t.time() + cr_after_ms
    while t.time() < end {
      over.push(t.find(ca_post).map(fn(p) { p.1 }))
      said.push(t.rect_of(ca_said).map(fn(r) { r.1 }))
      t.run_for(cr_look_ms)
    }
    match ca_back(over) {
      Some(w) => fail("\{screen.0}, its key \{key}: the post over the card, \{w}")
      None => ()
    }
    match ca_back(said) {
      Some(w) => fail("\{screen.0}, its key \{key}: \{ca_said}, \{w}")
      None => ()
    }
  }
}
