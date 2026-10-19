// A chat's cards answered from the chat, over the fixture's own answers (chat_fixture.mbt: a card answered or let go
// at once, the chat kept): what goes, what comes in its place, and how long it takes (Decisions.kt DecisionUnder,
// Chat.kt AskDismiss, ArchiveUnder, ChatBar).

///|
/// The fixture's chat open (the first row's), its calls kept in `calls` and answered by the fixture.
fn cards_core(calls : Array[Made], mode? : String = "chat") -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_cards_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.settle() |> ignore
  t
}

///|
/// `words` tapped, a frame drawn, nothing settled (Tester::tap_text waits for all motion to end).
fn tap_now(t : @ui.Tester, words : String) -> Unit {
  let (x, y) = t.find(words).unwrap()
  t.press_at(x, y)
  t.release(x, y)
}

///|
/// Scrolled until `words` show.
fn scroll_to_words(t : @ui.Tester, words : String) -> Unit {
  t.move(195.0, 400.0)
  for _ in 0..<8 {
    if t.find(words) is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
    t.settle() |> ignore
  }
}

///|
test "an option answered: the options go, how it went comes in their place, the picked one as it was" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "把首页和聊天页的截图都更新")
  tap_now(t, "把首页和聊天页的截图都更新")
  t.frame()
  assert_eq(named(calls, "decision.answer").length(), 1)
  // a moment on: the options still drawn as they go (only drawn: a tap on them answers nothing), 忽略 going with them
  t.frame(ms=60.0)
  assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
  tap_now(t, "这次只改列表，截图下次再说")
  t.frame()
  assert_eq(named(calls, "decision.answer").length(), 1)
  // once they have gone (200 ms, then their room closing on the delayed spring), how it went
  t.settle() |> ignore
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  assert_true(t.find("忽略") is None)
}

///|
test "the options' room closes on the rows' spring, a little late, and the line fades in after them" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "把首页和聊天页的截图都更新")
  let (_, _, _, h0) = t.rect_of("你 选择了").unwrap_or((0.0, 0.0, 0.0, -1.0))
  assert_eq(h0, -1.0)
  tap_now(t, "把首页和聊天页的截图都更新")
  // within its fade (200 ms) the line is not there yet; the options still are
  t.frame()
  t.frame(ms=50.0)
  assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
  // once they have gone, it is
  for _ in 0..<40 {
    t.frame()
  }
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  t.settle() |> ignore
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
}

///|
test "忽略: it and the ask go at once (decision.dismiss), drawn going, then gone" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "忽略")
  tap_now(t, "忽略")
  t.frame()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  t.frame(ms=40.0)
  // going (280 ms): drawn, not tapped
  assert_true(t.find("忽略") is Some(_))
  tap_now(t, "忽略")
  t.frame()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  t.settle() |> ignore
  assert_true(t.find("忽略") is None)
}

///|
test "保留 kept: the buttons under the post go and the bar's 归档 with them" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "保留")
  t.tap_text("保留")
  t.frame()
  assert_eq(named(calls, "chat.keep").length(), 1)
  t.settle() |> ignore
  assert_true(t.find("归档此对话") is None)
}

///|
test "保留 that failed is marked so for 6 s, said in a toast" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-cards")
  scroll_to_words(t, "保留")
  assert_true(dui.failed.contains("keep/ws1/st1/7"))
  t.tap_text("保留")
  t.frame()
  assert_eq(named(calls, "chat.keep").length(), 1)
  t.settle() |> ignore
  assert_true(app.toast.contains("Studio 没有回应"))
  // still offered
  assert_true(t.find("归档此对话") is Some(_))
  assert_true(dui.failed.contains("keep/ws1/st1/7"))
  t.advance(7000.0)
  t.frame()
  assert_true(dui.failed.is_empty())
}

///|
test "an option pressed is drawn smaller, its tap where it is laid out" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "保留")
  let (x, y) = t.find("保留").unwrap()
  t.press_at(x, y)
  for _ in 0..<8 {
    t.frame()
  }
  t.release(x, y)
  t.settle() |> ignore
  assert_eq(named(calls, "chat.keep").length(), 1)
}
