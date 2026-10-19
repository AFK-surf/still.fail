// Slice 8 over a fake core: the fixture's topics (decide_fixture.mbt's modes), its calls kept for the test to look at.

///|
/// The app over the fixture in `mode` (its pages opened as sffix opens them), its calls kept in `calls` and answered.
fn decide_core(calls : Array[Made], mode : String) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
  }
  if mode.has_prefix("chat") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  open_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.settle() |> ignore
  t
}

///|
test "an option tapped in the chat answers its card (decision.answer)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("把首页和聊天页的截图都更新")
  t.settle() |> ignore
  let made = named(calls, "decision.answer")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "option"), "一起换")
  assert_eq(number(Some(made[0].params), "seq"), 8.0)
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
}

///|
test "忽略 lets the ask go (decision.dismiss), gone at once" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("忽略") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("忽略")
  t.settle() |> ignore
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  assert_true(t.find("忽略") is None)
}

///|
test "归档此对话 archives the chat and goes home; 保留 keeps it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.tap_text("保留")
  t.settle() |> ignore
  let kept = named(calls, "chat.keep")
  assert_eq(kept.length(), 1)
  assert_eq(number(Some(kept[0].params), "thread"), 7.0)
  t.tap_text("归档此对话")
  t.settle() |> ignore
  let archived = named(calls, "chat.archive")
  assert_eq(archived.length(), 1)
  assert_eq(text(Some(archived[0].params), "session"), "s-c1")
  assert_true(flag(Some(archived[0].params), "archived"))
  assert_eq(app.nav.depth(), 1)
}

///|
test "the chat's own sheet: its agents, pinning it, and on to the agent's card and its history" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  assert_true(t.find("复制会话链接") is Some(_))
  assert_true(t.find("Claude · Opus 5.5") is Some(_))
  t.tap_text("固定到列表顶部")
  t.settle() |> ignore
  let pinned = named(calls, "chat.pin")
  assert_eq(pinned.length(), 1)
  assert_true(flag(Some(pinned[0].params), "pinned"))
  t.tap_text("Claude · Opus 5.5")
  t.settle() |> ignore
  assert_true(t.find("费用估算") is Some(_))
  assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is Some(_))
  t.tap_text("8 轮 · 共干了 1 小时 12 分")
  t.settle() |> ignore
  match app.nav.top() {
    History(r, key) => {
      assert_eq(r.session, "s-c1")
      assert_eq(key, "s-c1")
    }
    _ => fail("not the history")
  }
  assert_true(t.find("执行历史") is Some(_))
}

///|
test "the history: a group opens to its steps, a step to its call and what came back" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "history")
  // opened by the fixture: the command and its output, the edit as a diff
  assert_true(t.find("moon test -p ui -f list_test.mbt") is Some(_))
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is Some(_))
  // a step closed again
  t.tap_text("跑一遍列表的测试")
  t.settle() |> ignore
  assert_true(t.find("moon test -p ui -f list_test.mbt") is None)
  t.tap_text("详情")
  t.settle() |> ignore
  assert_true(t.find("Claude Code 2.1.3") is Some(_))
  assert_true(t.find("Mac Studio · macOS 26 · M2 Max") is Some(_))
}

///|
test "the 奏 page: an option answers the card in front, the next comes in" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "decisions")
  assert_true(t.find("1 / 2") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  t.tap_text("把首页和聊天页的截图都更新")
  for _ in 0..<40 {
    t.frame(ms=16.0)
  }
  t.settle() |> ignore
  let made = named(calls, "decision.answer")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "option"), "一起换")
  // the text card in front now
  assert_true(t.find("1 / 1") is Some(_))
  assert_true(t.find("第 4 个：支付的测试") is Some(_))
}

///|
test "the 奏 page: swiped right, a decision is dismissed; none left, the day so far" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "decisions-idle")
  assert_true(t.find("奏折已全部批完") is Some(_))
  assert_true(t.find("选择了「一起换」") is Some(_) || t.find("整理发布清单 · 选择了「一起换」") is Some(_))
  let calls2 : Array[Made] = []
  let t2 = decide_core(calls2, "decisions")
  t2.drag(100.0, 400.0, 360.0, 400.0)
  for _ in 0..<40 {
    t2.frame(ms=16.0)
  }
  t2.settle() |> ignore
  assert_eq(named(calls2, "decision.dismiss").length(), 1)
  assert_true(t2.find("1 / 1") is Some(_))
}

///|
test "a call is drawn by what it is" {
  assert_eq(command_of({ "command": ["bash", "-lc", "ls -la"] }), Some("ls -la"))
  assert_eq(command_of({ "cmd": "git status" }), Some("git status"))
  match parse_call("{\"a\": \"abc") {
    Some(_) => fail("cut short without its marker")
    None => ()
  }
  match parse_call("{\"a\": \"abc\n… (12 more characters)") {
    Some(Object(m)) => assert_eq(m.get("a"), Some(Json::string("abc…")))
    _ => fail("not closed")
  }
  assert_eq(read_lines("    12→one\n    13→two\nmore", false), Some("one\ntwo"))
  assert_eq(plain_brief("## 标题\n- 一项 **重点**\n```sh\nls\n```"), "标题 一项 重点 ls")
  match command_output("Wall time: 1.2s\nProcess exited with code 0\nOutput:\nok") {
    Some((said, out)) => {
      assert_eq(said.length(), 2)
      assert_eq(out, "ok")
    }
    None => fail("no output read")
  }
  assert_eq(chat_link("ws1/st1", "ember:c-1"), "https://app.still.fail/o/ws1/st1/ember%3Ac-1")
}
