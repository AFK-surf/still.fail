// What other chats' agents wrote to a chat (the core's `letters`): a run of it is one pill across the chat (Chat.kt
// LettersLine, Android's ChatLettersTest), its messages out of the list; tapped, the core is asked to show it whole
// (`chat.letters`) and the messages come in under the pill; tapped again, folded.

///|
/// The fixture's chat with a run of three letters at its end, then its agent's answer; folded unless `open`.
fn with_letters(v : Json, open : Bool) -> Json {
  let ms = match v {
    Object(m) =>
      match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
    _ => []
  }
  let from : Json = {
    "name": "BFT 备份尺寸分析",
    "from": "https://app.still.fail/o/w/s/ember%3Ac-4dbf0d0c6e",
    "maker": { "id": "anthropic", "name": "anthropic" },
  }
  let letter = fn(seq : Int, words : String) { msg(seq, "agent", from, words, "刚刚", { "author": "peer/ember:c-9" }) }
  let run = [
    letter(200, "用户让精简备份并改用 zstd，改好的两个脚本放好了，麻烦替换一下"),
    letter(201, "补充一点：系统自带的 tar 能直接解 zstd"),
    letter(202, "已替换，今晚那份会按新脚本出"),
  ]
  let line : Json = { "count": 3, "line": "「BFT 备份尺寸分析」发给 Claude · 3 条", "open": Json::boolean(open) }
  ms.push(with_fields(run[0], [("letters", line)]))
  if open {
    ms.push(run[1])
    ms.push(run[2])
  }
  ms.push(msg(203, "agent", by_agent("anthropic", "claude", "s-c1"), "备份改好了：每份小了一大半", "刚刚", {}))
  with_fields(v, [("messages", Json::array(ms))])
}

///|
test "a run of other chats' agents' messages: one pill; tapped, the core shows it whole, tapped again folds it" {
  let calls : Array[Made] = []
  let open = Ref::new(false)
  let epoch = Ref::new(0)
  let t = edited_core(
    calls,
    "chat",
    fn(name, v) { if name == "chat" { with_letters(v, open.val) } else { v } },
    answer=fn(name) {
      // (the core folds or opens it: the chat's view again)
      if name == "chat.letters" {
        open.val = !open.val
        epoch.val += 1
      }
      Json::object({})
    },
    epoch~,
  )
  let pill = "「BFT 备份尺寸分析」发给 Claude · 3 条"
  for _ in 0..<8 {
    if t.find(pill) is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, 300.0)
  }
  assert_true(t.find(pill) is Some(_), msg="the run's line")
  assert_true(t.find("补充一点") is None, msg="the run folded")
  assert_true(t.find("备份改好了") is Some(_))
  t.tap_text(pill)
  t.frame()
  let asked = calls.filter(fn(m) { m.name == "chat.letters" })
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].params, { "station": "ws1/st1", "thread": 7, "seq": 200, "open": true })
  // its messages come in under it, in their turn
  t.run_for(row_turn_ms + turn_calm_ms)
  assert_true(t.find(pill) is Some(_))
  assert_true(t.find("补充一点") is Some(_), msg="the run shown whole")
  t.tap_text(pill)
  t.frame()
  let asked = calls.filter(fn(m) { m.name == "chat.letters" })
  assert_eq(asked.length(), 2)
  assert_eq(asked[1].params, { "station": "ws1/st1", "thread": 7, "seq": 200, "open": false })
  t.run_for(row_turn_ms + turn_calm_ms)
  assert_true(t.find("补充一点") is None, msg="folded again")
}
