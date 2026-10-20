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
  // the chat pushed in over Home
  t.run_for(@ui.nav_push_ms)
  t
}

///|
/// Answered options gone: faded out, their room closed on the rows' spring (a little late), how it went faded in.
fn options_gone_ms() -> Double {
  dmax(close_gap.duration(1.0, 0.0, 0.0), 2.0 * options_out_ms)
}

///|
/// Under a post, what comes or goes by the archive's curve (忽略, 保留 and 归档).
fn archive_ms() -> Double {
  archive_tween.duration(1.0, 0.0, 0.0)
}

///|
/// `words` tapped where it is, as two inputs (the press, the lift), each drawn.
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
  }
}

///|
test "an option answered: the options go, how it went comes in their place, the picked one as it was" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "把首页和聊天页的截图都更新")
  tap_now(t, "把首页和聊天页的截图都更新")
  t.draw()
  assert_eq(named(calls, "decision.answer").length(), 1)
  // half way through their fade: the options still drawn as they go (only drawn: a tap on them answers nothing), 忽略
  // going with them
  t.run_for(options_out_ms / 2.0)
  assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
  tap_now(t, "这次只改列表，截图下次再说")
  t.draw()
  assert_eq(named(calls, "decision.answer").length(), 1)
  // once they have gone (faded, then their room closing on the delayed spring), how it went
  t.run_for(options_gone_ms())
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  assert_true(t.find("忽略") is None)
  t.assert_idle()
}

///|
test "the options' room closes on the rows' spring, a little late, and the line fades in after them" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "把首页和聊天页的截图都更新")
  let (_, _, _, h0) = t.rect_of("你 选择了").unwrap_or((0.0, 0.0, 0.0, -1.0))
  assert_eq(h0, -1.0)
  tap_now(t, "把首页和聊天页的截图都更新")
  // within their fade the options still are
  t.draw()
  t.run_for(options_out_ms / 2.0)
  assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
  // once they have faded, the line is
  t.run_for(options_out_ms)
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  // and their room closed
  t.run_for(options_gone_ms())
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
  t.assert_idle()
}

///|
test "忽略: it and the ask go at once (decision.dismiss), drawn going, then gone" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "忽略")
  tap_now(t, "忽略")
  t.draw()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  // going: drawn, not tapped
  t.run_for(archive_ms() / 4.0)
  assert_true(t.find("忽略") is Some(_))
  tap_now(t, "忽略")
  t.draw()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  t.run_for(archive_ms())
  assert_true(t.find("忽略") is None)
  // the ask's room closed after it
  t.run_for(options_gone_ms())
  t.assert_idle()
}

///|
test "保留 kept: the buttons under the post go and the bar's 归档 with them" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "保留")
  t.tap_text("保留")
  assert_eq(named(calls, "chat.keep").length(), 1)
  t.run_for(archive_ms())
  assert_true(t.find("归档此对话") is None)
  t.assert_idle()
}

///|
test "保留 that failed is marked so for 6 s, said in a toast" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-cards")
  scroll_to_words(t, "保留")
  assert_true(dui.failed.contains("keep/ws1/st1/7"))
  t.tap_text("保留")
  assert_eq(named(calls, "chat.keep").length(), 1)
  assert_true(app.toast.contains("Studio 没有回应"))
  // still offered
  assert_true(t.find("归档此对话") is Some(_))
  assert_true(dui.failed.contains("keep/ws1/st1/7"))
  t.run_for(failed_ms)
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
  t.draw()
  assert_eq(named(calls, "chat.keep").length(), 1)
}
