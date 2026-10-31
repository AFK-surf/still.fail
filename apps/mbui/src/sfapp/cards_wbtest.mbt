// A chat's cards answered from the chat, over the fixture's own answers (chat_fixture.mbt: a card answered or let go
// at once): on screen the card stays as it is, none of it pressed any more; out of sight it is how it went
// (sfbase's list_turns.mbt Turns::in_turn; the user, 2026-10-29: what is answered moves nothing in the list).

///|
/// The fixture's chat open (the first row's), its calls kept in `calls` and answered by the fixture.
fn cards_core(calls : Array[Made], mode? : String = "chat", platform? : Int = 2) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_cards_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The chat left for Home and opened again: what was answered in it has been out of sight.
fn out_of_sight(t : @ui.Tester) -> Unit {
  t.back()
  t.run_for(@ui.move_most_ms)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.run_for(@ui.move_most_ms)
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
}

///|
test "answered options can be read again by hovering or holding the outcome, without answering again" {
  for platform in [0, 2] {
    let calls : Array[Made] = []
    let t = cards_core(calls, platform~)
    scroll_to_words(t, "把首页和聊天页的截图都更新")
    tap_now(t, "把首页和聊天页的截图都更新")
    t.run_for(turn_most_ms)
    out_of_sight(t)
    scroll_to_words(t, "你 选择了「一起换」")
    assert_true(t.find("这次只改列表，截图下次再说") is None)
    let (x, y) = t.find("你 选择了「一起换」").unwrap()
    let (_, _, width, _) = t.rect_of("你 选择了「一起换」").unwrap()
    assert_true(width < 250.0)
    if platform == 0 {
      t.move(x, y)
      t.run_for(@sfpages.hover_open_ms)
    } else {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms)
    }
    t.draw()
    assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
    assert_true(t.find("这次只改列表，截图下次再说") is Some(_))
    if platform == 2 { t.release(x, y) }
    // A pointer can enter the card and read it without the history disappearing.
    if platform == 0 {
      let (cx, cy) = t.find("这次只改列表，截图下次再说").unwrap()
      t.move(cx, cy)
      t.run_for(@sfpages.hover_close_ms)
      assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
    }
    tap_now(t, "这次只改列表，截图下次再说")
    assert_eq(named(calls, "decision.answer").length(), 1)
  }
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
/// Whether the words `what` are drawn faded out (there, their room kept, nothing of them seen).
fn faded(t : @ui.Tester, what : String) -> Bool {
  match t.look_of(what) {
    Some((_, _, alpha)) => alpha < 0.01
    None => false
  }
}

///|
/// How tall the card's options are, from the first's top to the last's foot.
fn options_tall(t : @ui.Tester) -> Double {
  let (_, top, _, _) = t.rect_of("把首页和聊天页的截图都更新").unwrap()
  let (_, y, _, h) = t.rect_of("这次只改列表，截图下次再说").unwrap()
  y + h - top
}

///|
test "an option answered on screen: its options close at once, how it went in their place, none answered again" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "把首页和聊天页的截图都更新")
  tap_now(t, "把首页和聊天页的截图都更新")
  assert_eq(named(calls, "decision.answer").length(), 1)
  // (none of them answers again, closing as they are)
  tap_now(t, "这次只改列表，截图下次再说")
  assert_eq(named(calls, "decision.answer").length(), 1)
  // on screen as out of sight: its room closed with what came of it, one move (docs/list-motion.md)
  t.run_for(turn_most_ms)
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  t.assert_idle()
}

///|
test "忽略 on screen: let go at once (decision.dismiss), the card's options and 忽略 closing" {
  let calls : Array[Made] = []
  let t = cards_core(calls)
  scroll_to_words(t, "忽略")
  tap_now(t, "忽略")
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  t.run_for(turn_most_ms)
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
  assert_true(t.find("忽略") is None)
  t.assert_idle()
}

///|
test "words sent at the chat's end under a card waiting: it closes as they come in, what is over them going one way" {
  // (2026-10-30 the user: 「消息滚动在最底下的时候，在有决策卡片的时候发消息，整个消息列表会频繁来回移动」)
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-ask-end")
  let post = "列表的动效改好了"
  assert_true(t.find("一起改") is Some(_))
  t.tap_text("发消息")
  t.type_text("先把 app 的合了")
  tap_send(t)
  // what is over the card stands where the rows under it end: from the words sent till the station has them (the
  // fixture's fix_deliver_ms), the card's options closing as they come in, it goes one way
  let mut y = t.rect_of(post).unwrap().1
  let mut way = 0.0
  let from = t.time()
  while t.time() < from + @sffixture.fix_deliver_ms - 50.0 {
    t.frame()
    let y2 = t.rect_of(post).unwrap().1
    let d = y2 - y
    if d.abs() > 0.01 {
      if way != 0.0 && d * way < 0.0 {
        fail("the card's post turned back at \{t.time() - from} ms: \{y} to \{y2}")
      }
      way = d
    }
    y = y2
  }
  assert_true(t.find("一起改") is None)
  assert_true(t.find("你 回复了") is Some(_))
}

///|
test "words sent at the chat's end under a card waiting: nothing over them steps in one frame, through its agent at work" {
  // (2026-10-30 the user: 「还是会有顿挫」: a card's rooms closing left their gaps till the last frame, then went at once;
  // the words sent changed as the station had them from a height another row had had)
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-ask-end")
  let over = "做完了：列表"
  t.tap_text("发消息")
  t.type_text("先把 app 的合了")
  tap_send(t)
  // from the words sent, through the station having them and its agent at work, to its answer
  let from = t.time()
  let ys : Array[Double] = [t.rect_of(over).unwrap().1]
  let ts : Array[Double] = [from]
  while t.time() < from + @sffixture.fix_deliver_ms + @ui.move_most_ms {
    t.frame()
    ys.push(t.rect_of(over).unwrap().1)
    ts.push(t.time())
  }
  let step = fn(i : Int) { if i <= 0 || i >= ys.length() { 0.0 } else { (ys[i] - ys[i - 1]).abs() } }
  for i in 1..<ys.length() {
    let d = step(i)
    let around = dmax(dmax(step(i - 1), step(i + 1)), 0.5)
    if d > 6.0 && d > 3.0 * around {
      fail("what is over the card stepped \{ys[i] - ys[i - 1]} at once at \{ts[i] - from} ms (\{step(i - 1)} and \{step(i + 1)} round it)")
    }
  }
}
