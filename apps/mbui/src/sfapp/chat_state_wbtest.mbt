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
  let said = Ref(true)
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" || !said.val {
      return tp
    }
    match tp.value {
      Some(v) =>
        { ..tp, value: Some(@sffixture.with_state(v, ("需要你处理：" + need, "need", need))), version: tp.version + 1 }
      None => tp
    }
  })
  t.keep_parts(true)
  t.draw()
  let (_, need_y) = t.find(need).unwrap()
  let (_, last_y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(need_y > last_y)
  // the core no longer says it: it fades as its room closes (docs/list-motion.md), what is over it coming down with
  // it, a step of the way each frame, never at once
  said.val = false
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
  let bell = t
    .boxes()
    .filter(fn(b) {
      (b.w - 14.0).abs() < 0.01 && (b.h - 14.0).abs() < 0.01 && b.x + b.w <= run.x0 && b.x > run.x0 - 30.0
    })
  // (its place and the icon in it: one square)
  assert_true(bell.length() > 0 && bell.all(fn(b) { b.y == bell[0].y }), msg="\{bell.map(fn(b) { (b.x, b.y, b.w, b.h) })}")
  let line_mid = (run.top + run.bottom) / 2.0
  let bell_mid = bell[0].y + bell[0].h / 2.0
  assert_true((bell_mid - line_mid).abs() < 0.01, msg="bell \{bell_mid}, line \{line_mid}")
}
