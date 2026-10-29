// What a chat's agents and other chats' wrote each other (the core's `chatLetters`, Android's ChatLettersTest): not in
// the chat at all; its sheet ("…") has a row for them (the chat's `letters`), which opens them in a sheet of their
// own: the chats it wrote with, a row each; one opened, its letters both ways, drawn as the chat draws messages.

///|
test "letters are not in the chat: from its sheet, the chats written with, one opened shows its letters both ways" {
  reset()
  let base = fixture("chat-info")
  let asked : Array[Map[String, Json]] = []
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      match (name, t.value) {
        ("chat", Some(v)) => { ..t, value: Some(fix_with_letters(v)) }
        ("chatLetters", _) => {
          asked.push(params)
          { ..t, value: Some(fix_letters()) }
        }
        _ => t
      }
    },
  }
  open_fixture_over("chat-info", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // the chat's sheet open over it: a row for them, saying how many; none of them in the chat
  assert_true(t.find("agent 往来") is Some(_), msg="its row in the chat's sheet")
  assert_true(t.find("4 条") is Some(_))
  assert_true(t.find("补充一点") is None, msg="not in the chat")
  t.tap_text("agent 往来")
  // (the chat's sheet goes, theirs comes up, to where it rests)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(asked.length() > 0)
  let of_chat : Map[String, Json] = { "station": Json::string("ws1/st1"), "thread": Json::number(7.0) }
  assert_eq(asked[0], of_chat)
  // the chats written with, a row each: how many and when, the last letter in brief; none of the letters yet
  assert_true(t.find("BFT 备份尺寸分析") is Some(_))
  assert_true(t.find("3 条 · 5 分钟前") is Some(_))
  assert_true(t.find("1 条 · 4 分钟前") is Some(_), msg="the one written with last, first")
  assert_true(t.find("补充一点：系统自带的") is Some(_))
  assert_true(t.find("用户让精简备份") is None, msg="its letters once opened")
  t.tap_text("BFT 备份尺寸分析")
  t.frame()
  assert_true(t.find("用户让精简备份") is Some(_), msg="coming in")
  assert_true(t.find("已替换") is Some(_), msg="going out")
  assert_true(t.find("「BFT 备份尺寸分析」的 agent") is Some(_))
}
