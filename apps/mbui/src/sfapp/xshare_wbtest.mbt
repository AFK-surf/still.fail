// Sharing a chat with the viewer's other workspaces on a phone (sfpages' xshare.mbt, its row xshare.mbt) and archiving a
// chat that keeps watch from its sheet, over the fixture's chat.

///|
/// The chat's menu over the fixture's chat, its `chat` topic as `over` makes it; calls kept and answered with nothing.
fn sheet_core(calls : Array[Made], over? : (Json?) -> Json? = fn(v) { v }) -> @ui.Tester {
  new_run()
  let base = fixture("chat-actions")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
    topic_read: fn(name, params) {
      let t = base.topic(name, params).get().snapshot()
      if name == "chat" {
        { ..t, value: over(t.value) }
      } else {
        t
      }
    },
  }
  open_fixture_over("chat-actions", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "分享给其他 workspace: its row says where; the sheet ticks another and lets their agents send, 完成 says so" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  open_share(t)
  t.tap_text("分享给其他 workspace")
  // (the chat's sheet put down, the presenters' sheet up: its own end)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is Some(_))
  t.tap_text("日常")
  t.click(Switch, label="可发送消息")
  t.tap_text("完成")
  let made = named(calls, "chat.xshare")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "session"), "s-c1")
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
  assert_true(flag(Some(made[0].params), "write"))
  match field(Some(made[0].params), "to") {
    Some(Array(to)) => assert_eq(to, [Json::string("ws2"), Json::string("ws3")])
    _ => fail("no workspaces said")
  }
}

///|
test "分享给其他 workspace: none ticked, their agents cannot be let send" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  open_share(t)
  t.tap_text("分享给其他 workspace")
  // (the chat's sheet put down, the presenters' sheet up: its own end)
  t.frame()
  t.run_for(@ui.move_most_ms)
  // the one it is shared with let go: none left
  // (the chat's own sheet sinking as far as it is tall: any way is over by then)
  t.run_for(@ui.move_most_ms)
  t.tap_text("开源")
  t.click(Switch, label="可发送消息")
  t.tap_text("完成")
  let made = named(calls, "chat.xshare")
  assert_eq(made.length(), 1)
  assert_false(flag(Some(made[0].params), "write"))
  match field(Some(made[0].params), "to") {
    Some(Array(to)) => assert_eq(to.length(), 0)
    _ => fail("no workspaces said")
  }
}

///|
test "分享给其他 workspace on a phone: its rows a finger's, 完成 across the sheet in a thumb's reach" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  open_share(t)
  t.tap_text("分享给其他 workspace")
  t.frame()
  t.run_for(@ui.move_most_ms)
  // (each row a finger's 44 at least: the next one's words that far under its words)
  let (_, y1, _, _) = t.rect_of("日常").unwrap()
  let (_, y2, _, _) = t.rect_of("开源").unwrap()
  assert_true(y2 - y1 >= 44.0, msg="rows \{y2 - y1} apart")
  // their names a phone's row title (its body's 15 on 21), as the phone's sheet had them; the switch's too
  let (_, _, _, nh) = t.rect_of("日常").unwrap()
  assert_true(nh >= 21.0, msg="a row's name \{nh} high")
  let (_, _, _, sh) = t.rect_of("可发送消息").unwrap()
  assert_true(sh >= 21.0, msg="the switch's title \{sh} high")
  // 完成's ground: across the sheet, less its sides
  let (x, y, w, h) = t.rect_of("完成").unwrap()
  let (cx, cy) = (x + w / 2.0, y + h / 2.0)
  let grounds = t.drawn_rects().filter(fn(r) { r.0 <= cx && cx <= r.0 + r.2 && r.1 <= cy && cy <= r.1 + r.3 && r.3 < 60.0 })
  assert_true(grounds.iter().any(fn(r) { r.2 >= 390.0 - 2.0 * 24.0 }), msg="完成 not across the sheet: \{Repr(grounds)}")
}

///|
/// A phone's buttons are drawn as the large screen's, 34 (button_height: the user, 2026-10-31, 「按钮既然缩，那就跟大屏一致
/// 呗」); a finger reaches one from a fingertip round it all the same (mbui's press_reach: a target under 44 grown to it
/// round its middle where the finger is on nothing else).
test "分享给其他 workspace on a phone: 完成 drawn as the large screen's, reached past its edge" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  open_share(t)
  t.tap_text("分享给其他 workspace")
  t.frame()
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.rect_of("完成").unwrap()
  let (cx, cy) = (x + w / 2.0, y + h / 2.0)
  let pill = t
    .drawn_rects()
    .filter(fn(r) { r.0 <= cx && cx <= r.0 + r.2 && r.1 <= cy && cy <= r.1 + r.3 && r.3 < 60.0 })
    .iter()
    .fold(init=(0.0, 0.0, 0.0, 0.0), fn(a, r) { if r.2 > a.2 { (r.0, r.1, r.2, r.3) } else { a } })
  assert_true((pill.3 - @sf.button_height()).abs() < 0.5, msg="drawn \{pill.3} high")
  // (3 over its top: outside what is drawn, within a finger's 44 round its middle)
  t.tap(cx, pill.1 - 3.0)
  t.frame()
  assert_eq(named(calls, "chat.xshare").length(), 1)
}

// With keyboard and mouse on a small window (a sheet there too) and on a wide one (a dialog in its middle): ticking by
// a row's words or its box, 可发送消息 off while none is ticked, 完成 waiting for what it is shared with now, Escape and
// a press outside telling nothing.

///|
/// The chat's menu over the fixture's chat in a window `w` by `h` with `platform`'s hand, its `chat` topic as `over`
/// makes it, calls kept and answered with nothing; its 分享… opened, 分享给其他 workspace pressed (or the panel opened by
/// `opens`): the panel up, come to
/// rest unless `rest` is false (at the frame it opened in then).
fn xshare_up(
  calls : Array[Made],
  platform? : Int = 2,
  wide? : Bool = false,
  rest? : Bool = true,
  over? : (Json?) -> Json? = fn(v) { v },
  opens? : (Source) -> Unit,
) -> @ui.Tester {
  new_run()
  let base = fixture("chat-actions")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
    topic_read: fn(name, params) {
      let t = base.topic(name, params).get().snapshot()
      if name == "chat" {
        { ..t, value: over(t.value) }
      } else {
        t
      }
    },
  }
  open_fixture_over("chat-actions", src)
  let (w, h) = if wide { (1200.0, 800.0) } else { (390.0, 844.0) }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  match opens {
    Some(f) => {
      // (the fixture's menu put down first)
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      f(src)
    }
    None => {
      open_share(t)
      t.tap_text("分享给其他 workspace")
    }
  }
  t.frame()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The workspaces 完成 told the core, in order, and whether their agents may send.
fn xshare_told(calls : Array[Made]) -> (Array[String], Bool) {
  let made = named(calls, "chat.xshare")
  guard made.length() == 1 else { @halt.saying("chat.xshare told \{made.length()} times") }
  let to = match field(Some(made[0].params), "to") {
    Some(Array(to)) => to.map(fn(j) { (if j is String(s) { Some(s) } else { None }).unwrap_or("?") })
    _ => @halt.saying("no workspaces said")
  }
  (to, flag(Some(made[0].params), "write"))
}

///|
test "分享给其他 workspace with keyboard and mouse on a small window: a sheet; ticked by a row's box or its words, 完成 says so" {
  let calls : Array[Made] = []
  let t = xshare_up(calls, platform=0)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is Some(_))
  // as it is shared now: 开源 ticked, 日常 not
  assert_eq(t.get(Checkbox, label="开源").check, Some(On))
  assert_eq(t.get(Checkbox, label="日常").check, Some(Off))
  // its box ticks it, its words again untick it, and once more
  t.click(Checkbox, label="日常")
  t.frame()
  assert_eq(t.get(Checkbox, label="日常").check, Some(On))
  t.tap_text("日常")
  t.frame()
  assert_eq(t.get(Checkbox, label="日常").check, Some(Off))
  t.tap_text("日常")
  t.frame()
  t.click(Switch, label="可发送消息")
  t.frame()
  t.tap_text("完成")
  t.frame()
  assert_eq(xshare_told(calls), (["ws2", "ws3"], true))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is None)
}

///|
test "分享给其他 workspace with keyboard and mouse: Escape tells nothing" {
  let calls : Array[Made] = []
  let t = xshare_up(calls, platform=0)
  t.tap_text("日常")
  t.frame()
  t.key(@ui.key_escape)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is None)
  assert_eq(named(calls, "chat.xshare").length(), 0)
}

///|
test "分享给其他 workspace on a wide window: a dialog in its middle; 完成 says what is ticked" {
  let calls : Array[Made] = []
  let t = xshare_up(calls, platform=0, wide=true)
  let (x, y, _, _) = t.rect_of("分享给其他 workspace").unwrap()
  assert_true(x > 200.0 && x < 800.0 && y > 100.0 && y < 500.0, msg="its title at \{x},\{y}")
  assert_eq(t.get(Checkbox, label="开源").check, Some(On))
  t.tap_text("日常")
  t.frame()
  t.tap_text("开源")
  t.frame()
  t.tap_text("完成")
  t.frame()
  assert_eq(xshare_told(calls), (["ws2"], false))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is None)
}

///|
test "分享给其他 workspace on a wide window: Escape and a press outside it tell nothing" {
  let calls : Array[Made] = []
  let t = xshare_up(calls, platform=0, wide=true)
  t.tap_text("日常")
  t.frame()
  t.key(@ui.key_escape)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is None)
  let t = xshare_up(calls, platform=0, wide=true)
  t.tap_text("日常")
  t.frame()
  t.tap(20.0, 780.0)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is None)
  assert_eq(named(calls, "chat.xshare").length(), 0)
}

///|
test "分享给其他 workspace: 可发送消息 off while none is ticked, on again once one is" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[Made] = []
    let t = xshare_up(calls, platform=screen.0, wide=screen.1)
    assert_eq(t.get(Switch, label="可发送消息").disabled, false, msg=about)
    t.tap_text("开源")
    t.frame()
    assert_eq(t.get(Switch, label="可发送消息").disabled, true, msg=about)
    t.click(Switch, label="可发送消息")
    t.frame()
    assert_eq(t.get(Switch, label="可发送消息").check, Some(Off), msg=about)
    t.tap_text("日常")
    t.frame()
    assert_eq(t.get(Switch, label="可发送消息").disabled, false, msg=about)
    t.click(Switch, label="可发送消息")
    t.frame()
    assert_eq(t.get(Switch, label="可发送消息").check, Some(On), msg=about)
    t.tap_text("完成")
    t.frame()
    assert_eq(xshare_told(calls), (["ws2"], true), msg=about)
  }
}

///|
/// The chat's `xshare` held back while `held` says so (a signal: what reads the chat follows it, as the core's topic).
fn xshare_held(held : @signals.Signal[Bool]) -> (Json?) -> Json? {
  fn(v) {
    match v {
      Some(Object(m)) if held.get() => {
        let o = m.copy()
        o.remove("xshare")
        Some(Json::object(o))
      }
      _ => v
    }
  }
}

///|
test "分享给其他 workspace before what it is shared with now is read: 完成 waits; ticked as shared once it comes" {
  let calls : Array[Made] = []
  // (as a row's menu opens it, before its page's `xshare` has come)
  let held = @signals.signal(true)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let t = xshare_up(calls, over=xshare_held(held), opens=fn(src) { @sfpages.open_xshare(src, r, Some(7.0), from=Unanchored) })
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is Some(_))
  assert_true(t.find("开源") is None, msg="its places before they are read")
  t.tap_text("完成")
  t.frame()
  assert_eq(named(calls, "chat.xshare").length(), 0)
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is Some(_), msg="完成 pressed while it waits: the panel still up")
  held.set(false)
  t.frame()
  // (its rows make their way in: over by the longest a Move is)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("开源") is Some(_), msg="its places not come: \{t.words().map(fn(w) { w.0 }).join("|")}")
  assert_eq(t.get(Checkbox, label="开源").check, Some(On))
  assert_eq(t.get(Checkbox, label="日常").check, Some(Off))
  t.tap_text("完成")
  t.frame()
  assert_eq(xshare_told(calls), (["ws3"], false))
}

///|
/// Where the first of the words `words` is drawn: its left, top, width and height.
fn xshare_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
test "分享给其他 workspace: each workspace a row, its box, its mark and its name on a line; the switch and its note under them; 完成 last" {
  // (touch on a small window, a sheet; keyboard and mouse there, a sheet too; a wide window, a dialog in its middle)
  for screen in [(2, false), (0, false), (0, true)] {
    let calls : Array[Made] = []
    let t = xshare_up(calls, platform=screen.0, wide=screen.1)
    let about = "platform \{screen.0}, wide \{screen.1}"
    let mid = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
    let lead = xshare_word(t, "所选 workspace 中的 agent 可读取此对话；连续 6 小时未使用即失效，需重新分享")
    let (daily, open) = (xshare_word(t, "日常"), xshare_word(t, "开源"))
    // the workspaces under what it says, one under the other, their names on one line down the panel
    assert_true(daily.1 > lead.1 + lead.3 && open.1 >= daily.1 + daily.3, msg="\{about}: \{Repr(lead)}, \{Repr(daily)}, \{Repr(open)}")
    assert_true((daily.0 - open.0).abs() < 0.5, msg="\{about}: \{Repr(daily)}, \{Repr(open)}")
    for named_by in [("日常", "日"), ("开源", "开")] {
      let (name, first) = named_by
      let words = xshare_word(t, name)
      let box = t.get(Checkbox, label=name).rect
      // its letter (the mark of a workspace with none) on its name's line, before it, its box before that
      let letter = t.words().iter().find_first(fn(w) { w.0 == first && (w.2 + w.4 / 2.0 - mid(words)).abs() < 1.5 })
      assert_true(letter is Some(l) && l.1 + l.3 <= words.0 && box.0 + box.2 <= l.1, msg="\{about}: \{name} \{Repr(words)}, its letter \{Repr(letter)}, its box \{Repr(box)}")
      assert_true((mid(box) - mid(words)).abs() < 1.0, msg="\{about}: \{name} \{Repr(words)}, its box \{Repr(box)}")
      // (its box by the panel's words' line: its row out by a row's room, 12, its box in by its corner)
      assert_true((box.0 - lead.0).abs() < 12.0, msg="\{about}: \{name}'s box \{Repr(box)}, the lead \{Repr(lead)}")
    }
    // 可发送消息 and its note under the workspaces, on the panel's words' line; the switch at its end
    let (write, note) = (xshare_word(t, "可发送消息"), xshare_word(t, "关闭时仅可查看"))
    assert_true(write.1 > open.1 + open.3 && note.1 >= write.1 + write.3, msg="\{about}: \{Repr(open)}, \{Repr(write)}, \{Repr(note)}")
    assert_true((write.0 - lead.0).abs() < 0.5 && (note.0 - lead.0).abs() < 0.5, msg="\{about}: \{Repr(write)}, \{Repr(note)}, \{Repr(lead)}")
    let switch = t.get(Switch, label="可发送消息").rect
    assert_true(switch.0 > write.0 + write.2 && switch.0 + switch.2 <= lead.0 + lead.2 + 0.5, msg="\{about}: \{Repr(switch)}, \{Repr(write)}, \{Repr(lead)}")
    // 完成 last: across a sheet's middle; at a dialog's end
    let done = xshare_word(t, "完成")
    assert_true(done.1 > note.1 + note.3, msg="\{about}: \{Repr(done)}, \{Repr(note)}")
    if screen.1 {
      assert_true(done.0 + done.2 > lead.0 + lead.2 - 40.0, msg="\{about}: \{Repr(done)}, \{Repr(lead)}")
    } else {
      assert_true((done.0 + done.2 / 2.0 - (lead.0 + lead.2 / 2.0)).abs() < 1.0, msg="\{about}: \{Repr(done)}, \{Repr(lead)}")
    }
  }
}
