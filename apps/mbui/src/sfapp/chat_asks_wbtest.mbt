// The chat's questions through the library's presenters (sheets.mbt open_rename, context.mbt open_context): its name
// asked (@sf.ask, an empty one said too: named anew), its agent's context compacted or cleared (@sf.panel), clearing
// asked first (@sf.confirm).

///|
test "renaming the chat: asked for its name, an empty one said too (named anew, as its note says)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_rename(decide_src.val.unwrap(), r, Some(7.0), "整理发布清单", from=Unanchored)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("重命名对话") is Some(_), msg="its question")
  for _ in 0..<12 {
    t.press("Backspace")
  }
  t.frame()
  t.tap_text("保存")
  t.run_for(@ui.move_most_ms)
  let sent = named(calls, "chat.rename")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "title"), "")
  assert_eq(text(Some(sent[0].params), "session"), "s-c1")
}

///|
test "an agent's context: its tile opens what can be done; clearing it asked first, cleared once it is said" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent-unsaid")
  let tile = if t.find("压缩上下文") is Some(_) { "压缩上下文" } else { "上下文" }
  t.tap_text(tile)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting(), msg="what can be done to it")
  t.tap_text("清空上下文")
  // (to where the presenters' sheet rests: the panel's gone down, the question's up in its place)
  t.run_for(@sf.presented_rest() - t.time())
  // asked first: nothing cleared yet, its action the one 清空上下文 there is
  assert_true(t.find("清空此 agent 的上下文？") is Some(_), msg="the question")
  assert_eq(t.locate("清空上下文").length(), 1)
  assert_eq(named(calls, "session.clear").length(), 0)
  let felt = t.haptics().length()
  t.tap_text("清空上下文")
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "session.clear").length(), 1)
  assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm])
}

///|
test "a list's panel as tall as what it holds, its share of the window the most it comes to, past that scrolling" {
  // (the letters' sheet: 80% of the window at most)
  let calls : Array[Made] = []
  // two chats written with: the sheet as tall as they are, no room under them to spare
  let t = decide_core(calls, "chat-letters")
  sheet_rested(t, "sf-present")
  let (_, sy, _, sh) = t.get(@ui.Role::Dialog).rect
  let (_, ly, _, lh) = t.rect_of("BFT 备份尺寸分析").unwrap()
  assert_true(sh < 844.0 * 0.8 - 100.0, msg="short: \{sh}")
  assert_true(sy + sh - (ly + lh) < 120.0, msg="under its last: \{sy + sh - (ly + lh)}")
  // thirty: the sheet at its share, the last of them under its foot, scrolled to
  let t = decide_core(calls, "chat-letters-many")
  sheet_rested(t, "sf-present")
  let (_, _, _, sh) = t.get(@ui.Role::Dialog).rect
  assert_true((sh - 844.0 * 0.8).abs() < 2.0, msg="capped: \{sh}")
  assert_true(t.find("往来的对话 1") is Some(_))
  assert_true(t.find("往来的对话 30") is None, msg="its last under its foot")
}

// The agent's context panel (context.mbt open_context) on each screen: touch on a small window (a sheet from the
// foot), keyboard and mouse there (a sheet too), a wide window (a dialog in its middle); each of its rows, Escape, and
// where its words stand.

///|
/// The corner rule's faults known in the context's dialog in a wide window's middle (Tester::corners_known), kept till
/// the panels' layout is decided (the coordinator of the migration, 2026-11-12): its last row's ground under the hand or
/// with the focus (choice_row_node's, 18 round) stands 16 in from the dialog's sides and 24 over its foot, in its 42
/// corners, as far from neither edge as from the other, so no corner of it is concentric there (42 − 24 = 18 by its
/// foot, 42 − 16 = 26 by its side). What would mend it: the row 16 over the foot too, its corner 26.
// kept across runs: a value (no field of it changes)
let context_corners_known : Array[String] = [
  "「清空上下文 结束当前进程，下一条消息开始新的会话」 (at 356,434 488×60, node 911) (corner 18) in the bottom right of 「上下文 压缩上下文 保留摘要，释放上下文空间 清…」 (at 340,283 520×235, node 880) (corner 42): 16 and 24 from its edges",
  "「清空上下文 结束当前进程，下一条消息开始新的会话」 (at 356,434 488×60, node 911) (corner 18) in the bottom left of 「上下文 压缩上下文 保留摘要，释放上下文空间 清…」 (at 340,283 520×235, node 880) (corner 42): 16 and 24 from its edges",
]

///|
/// The fixture's agent card (decide_core's `chat-agent-unsaid`, its context compactable and clearable) on a window of
/// `platform`, 390×844, or 1200×800 where `wide`; its context's tile pressed, the panel come to rest (with `rest`, else
/// at the frame it opened in).
fn context_up(calls : Array[Made], platform? : Int = 2, wide? : Bool = false, rest? : Bool = true) -> @ui.Tester {
  new_run()
  let base = fixture("chat-agent-unsaid")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
  }
  decide_src.val = Some(src)
  open_fixture_over("chat-agent-unsaid", src)
  let (w, h) = if wide { (1200.0, 800.0) } else { (390.0, 844.0) }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  if wide {
    t.corners_known(context_corners_known)
  }
  t.run_for(@ui.move_most_ms)
  let tile = if t.find("压缩上下文") is Some(_) { "压缩上下文" } else { "上下文" }
  t.tap_text(tile)
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// Where the words `words` are drawn last (the panel's, over what it is opened from): left, top, width, height.
fn context_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().filter(fn(w) { w.0 == words }).last() {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
test "an agent's context on each screen: 压缩上下文 compacts it at once, the panel gone" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[Made] = []
    let t = context_up(calls, platform=screen.0, wide=screen.1)
    assert_true(t.find("保留摘要，释放上下文空间") is Some(_), msg="\{about}: its rows")
    assert_true(t.find("结束当前进程，下一条消息开始新的会话") is Some(_), msg=about)
    t.tap_text("保留摘要，释放上下文空间")
    t.run_for(@ui.move_most_ms)
    let sent = named(calls, "session.compact")
    assert_eq(sent.length(), 1, msg=about)
    assert_eq(text(Some(sent[0].params), "station"), "ws1/st1", msg=about)
    assert_eq(text(Some(sent[0].params), "key"), "s-c1", msg=about)
    assert_eq(named(calls, "session.clear").length(), 0, msg=about)
    assert_true(t.find("保留摘要，释放上下文空间") is None, msg="\{about}: the panel gone")
  }
}

///|
test "an agent's context on each screen: 清空上下文 asked first, nothing cleared until it is said" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[Made] = []
    let t = context_up(calls, platform=screen.0, wide=screen.1)
    t.tap_text("结束当前进程，下一条消息开始新的会话")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("清空此 agent 的上下文？") is Some(_), msg="\{about}: the question")
    assert_true(t.find("保留摘要，释放上下文空间") is None, msg="\{about}: the panel gone")
    assert_eq(named(calls, "session.clear").length(), 0, msg=about)
    t.tap_text("清空上下文")
    t.run_for(@ui.move_most_ms)
    assert_eq(named(calls, "session.clear").length(), 1, msg=about)
    assert_eq(named(calls, "session.compact").length(), 0, msg=about)
  }
}

///|
/// Whether the agent's card shows (its context's tile's words drawn) and the context's panel does (its rows' notes).
fn card_and_context(t : @ui.Tester) -> (Bool, Bool) {
  (t.find("当前没有运行中的") is Some(_), t.find("保留摘要，释放上下文空间") is Some(_))
}

///|
test "an agent's context a step further in from its card (the presenters' step, 2026-11-10): Escape and back are back to the card, nothing done" {
  // (it used to stand over the card, Escape closing it alone; the card closes for it now, a step further in: the
  // presenters' rule, apps/mbui/AGENTS.md 弹层里往里走)
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    for how in ["escape", "back", "back key"] {
      let calls : Array[Made] = []
      let t = context_up(calls, platform=screen.0, wide=screen.1)
      assert_eq(card_and_context(t), (false, true), msg="\{about}: the card gone for it")
      // (its back key before its title, read out as back)
      let back = t.all(Button, label=@sf.t("common.back"))
      assert_eq(back.length(), 1, msg="\{about}: its back key")
      match how {
        "escape" => {
          t.key(@ui.key_escape)
          t.draw()
        }
        "back" => t.back()
        _ => t.click(Button, label=@sf.t("common.back"))
      }
      t.run_for(@ui.move_most_ms)
      assert_eq(card_and_context(t), (true, false), msg="\{about}, \{how}: back to the card")
      assert_true(@sf.presenting(), msg="\{about}, \{how}")
      assert_eq(named(calls, "session.compact").length() + named(calls, "session.clear").length(), 0, msg=about)
    }
  }
}

///|
test "an agent's context a step further in from its card (the presenters' step, 2026-11-10): a press outside closes all of it" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let t = context_up([], platform=screen.0, wide=screen.1)
    t.tap(8.0, 8.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(card_and_context(t), (false, false), msg=about)
    assert_true(!@sf.presenting(), msg=about)
  }
}

///|
test "an agent's context opened from its card on a phone's window (the presenters' step, 2026-11-10): one sheet all along, the scrim as it was" {
  for platform in [2, 0] {
    let t = context_up([], platform~, rest=false)
    let from = t.time()
    let mut ms = 0.0
    while ms <= @ui.move_most_ms {
      t.run_for(from + ms - t.time())
      let sheets = t.drawn_glass().filter(fn(g) { g.3 > 100.0 })
      assert_eq(sheets.length(), 1, msg="platform \{platform} at \{ms}: \{Repr(sheets)}")
      let scrims = t
        .drawn_rects()
        .filter(fn(r) { r.0 <= 0.0 && r.1 <= 0.0 && r.2 >= 390.0 && r.3 >= 844.0 && (r.4 & 0xFFL) > 0L && (r.4 & 0xFFL) < 0xFFL })
      assert_eq(scrims.length(), 1, msg="platform \{platform} at \{ms}")
      ms = ms + 50.0
    }
  }
}

///|
test "an agent's context: its title over its rows, each row's note under its name; a dialog in a wide window's middle" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[Made] = []
    let t = context_up(calls, platform=screen.0, wide=screen.1)
    let title = context_word(t, "上下文")
    let compact = context_word(t, "压缩上下文")
    let compact_note = context_word(t, "保留摘要，释放上下文空间")
    let clear = context_word(t, "清空上下文")
    let clear_note = context_word(t, "结束当前进程，下一条消息开始新的会话")
    // top to bottom: the title, 压缩上下文 and its note, 清空上下文 and its note
    assert_true(title.1 + title.3 <= compact.1, msg="\{about}: \{Repr(title)}, \{Repr(compact)}")
    assert_true(compact.1 + compact.3 <= compact_note.1, msg="\{about}: \{Repr(compact)}, \{Repr(compact_note)}")
    assert_true(compact_note.1 + compact_note.3 <= clear.1, msg="\{about}: \{Repr(compact_note)}, \{Repr(clear)}")
    assert_true(clear.1 + clear.3 <= clear_note.1, msg="\{about}: \{Repr(clear)}, \{Repr(clear_note)}")
    // each note starts where its name does; the two rows' words line up
    assert_true((compact.0 - compact_note.0).abs() < 1.0 && (clear.0 - clear_note.0).abs() < 1.0, msg=about)
    assert_true((compact.0 - clear.0).abs() < 1.0, msg=about)
    // the rows as far apart as each is tall: the second a row on from the first
    assert_true(((clear.1 - compact.1) - (clear_note.1 - compact_note.1)).abs() < 1.0, msg=about)
    if screen.1 {
      // in the middle of the window: neither at its foot nor at its side
      assert_true(title.0 > 200.0 && title.0 < 800.0 && title.1 > 100.0 && title.1 < 500.0, msg="\{about}: \{Repr(title)}")
      // (the corner rule's faults there, those known and no more: context_corners_known)
      assert_eq(
        t.corner_faults().map(@ui.corner_fault_unplaced),
        context_corners_known.map(@ui.corner_fault_unplaced),
        msg=about,
      )
    } else {
      // a sheet from the foot: its rows in the window's lower half
      assert_true(clear_note.1 > 422.0, msg="\{about}: \{Repr(clear_note)}")
    }
  }
}

