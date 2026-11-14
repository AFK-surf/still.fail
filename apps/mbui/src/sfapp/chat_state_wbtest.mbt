// Where a chat stands, said at the end of its messages as its row says it (the core's ChatView `stateText`): whole,
// under its last message, on either frame.

///|
/// The last of chat-done's messages (rich_chat's), and where it stands.
let state_last_said : String = "列表、跳到最新的按钮、加载更早的消息都好了"

///|
fn state_under_last(t : @ui.Tester, words : String, width : Double) -> Unit raise {
  let (_, last_y, _, last_h) = t.rect_of(state_last_said).unwrap()
  let (x, y, w, _) = t.rect_of(words).unwrap()
  assert_true(y >= last_y + last_h, msg="under the last message")
  assert_true(x >= 0.0 && x + w <= width, msg="whole on the page")
}

///|
test "a chat whose agent is done says so under its last message, its words whole: the wide frame" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-done", wide=true)
  state_under_last(t, @sffixture.done_state.2, 1280.0)
}

///|
test "a chat whose agent is done says so under its last message, its words whole: the phone's frame" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-done")
  state_under_last(t, @sffixture.done_state.2, 390.0)
}

///|
test "where a chat stands gone from its end (a person wrote): what is over it stays where it is, nothing drops onto it as it leaves" {
  let need = "Stripe 的测试 key，放进 vault 后告诉我名字"
  let said = @signals.signal(true)
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" || !said.get() {
      return tp
    }
    match tp.value {
      Some(v) =>
        { ..tp, value: Some(@sffixture.with_state(v, ("需要你处理：" + need, "need", need))), version: tp.version + 1 }
      None => tp
    }
  })
  t.set_rows_on_pixels(true)
  t.draw()
  let (_, need_y) = t.find(need).unwrap()
  let (_, last_y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(need_y > last_y)
  // the core no longer says it: it fades as its room closes (mbui's view/list_motion.mbt), what is over it coming down with
  // it, a step of the way each frame, never at once
  said.set(false)
  t.draw()
  let mut was = last_y
  for _ in 0..<8 {
    t.run_for(@ui.move_most_ms / 8.0)
    let (_, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
    assert_true(y >= was - 0.5 && y - was < 60.0, msg="\{y} \{was}")
    was = y
  }
  assert_true(was > last_y + 1.0, msg="\{was} \{last_y}")
}

///|
test "what a chat's agent needs is said under its last message" {
  let need = "Stripe 的测试 key，放进 vault 后告诉我名字"
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(v) => { ..tp, value: Some(@sffixture.with_state(v, ("需要你处理：" + need, "need", need))) }
      None => tp
    }
  })
  assert_true(t.find(need) is Some(_))
  // its bell's middle the middle of the words' first line: the bell's column as high as their line, whatever line the
  // theme gives them (on 18 the bell stood a point under the words, 2026-10-27)
  let run = t.text_runs().filter(fn(r) { need.has_prefix(r.text) })[0]
  // (the window's tree's boxes among the old view's: on whichever page the chat is made)
  let bell = t
    .boxes_held()
    .filter(fn(b) {
      (b.w - 14.0).abs() < 0.01 && (b.h - 14.0).abs() < 0.01 && b.x + b.w <= run.x0 && b.x > run.x0 - 30.0
    })
  // (its place and the icon in it: one square)
  assert_true(bell.length() > 0 && bell.all(fn(b) { b.y == bell[0].y }), msg="\{Repr(bell.map(fn(b) { (b.x, b.y, b.w, b.h) }))}")
  let line_mid = (run.top + run.bottom) / 2.0
  let bell_mid = bell[0].y + bell[0].h / 2.0
  assert_true((bell_mid - line_mid).abs() < 0.01, msg="bell \{bell_mid}, line \{line_mid}")
}

///|
test "a state ask added without changing its words moves the ask to the state and can be dismissed" {
  let active = @signals.signal(false)
  let held : Ref[Json?] = Ref(None)
  let src : Ref[Source?] = Ref(None)
  let calls : Array[Made] = []
  let t = fake_core(calls, made=src, over=fn(name, topic) {
    if name != "chat" {
      return topic
    }
    let asking = active.get()
    match topic.value {
      Some(raw) => {
        let original = match held.val {
          Some(v) => v
          None => {
            let need = @sffixture.with_need(raw)
            let obj = match need { Object(m) => m.copy(); _ => @halt.saying("chat is not an object") }
            let all = items(Some(need), "messages")
            obj["messages"] = Json::array([all[all.length() - 1]])
            obj["agents"] = Json::array([])
            obj["outbox"] = Json::array([])
            obj["elsewhere"] = Json::array([])
            obj["asks"] = Json::array([{ "seq": 12 }])
            obj["askClear"] = Json::boolean(false)
            let v = Json::object(obj)
            held.val = Some(v)
            v
          }
        }
        let obj = match original { Object(m) => m.copy(); _ => @halt.saying("chat is not an object") }
        if !asking {
          obj.remove("stateAsk") |> ignore
        }
        { ..topic, value: Some(Json::object(obj)), version: topic.version + (if asking { 1 } else { 0 }) }
      }
      None => topic
    }
  })
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let (before_view, before, _) = view_of_chat(src.val.unwrap(), r)
  let old = before_view.unwrap()
  let old_ask = @sfbase.ask_rows_of(old, before)[0]
  assert_true(before[old_ask] is Said(_), msg="the ask was at its message")
  let words = old.state
  active.set(true)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let (after_view, after, _) = view_of_chat(src.val.unwrap(), r)
  let current = after_view.unwrap()
  assert_eq(current.state, words)
  let new_ask = @sfbase.ask_rows_of(current, after)[0]
  assert_true(after[new_ask] is State(_, _, _), msg="the ask moved to the state")
  assert_true(t.find(@sffixture.need_state.2) is Some(_))
  let (x, y) = t.find_last("忽略").unwrap()
  t.tap(x, y)
  let made = named(calls, "decision.dismiss")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "seq"), 12.0)
  active.set(false)
  t.draw()
  let (again_view, again, _) = view_of_chat(src.val.unwrap(), r)
  let after_dismiss = again_view.unwrap()
  assert_eq(after_dismiss.state, words)
  let again_ask = @sfbase.ask_rows_of(after_dismiss, again)[0]
  assert_true(again[again_ask] is Said(_), msg="the ask returned to its message")
}
