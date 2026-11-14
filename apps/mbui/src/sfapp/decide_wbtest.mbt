// Slice 8 over a fake core: the fixture's topics (decide_fixture.mbt's modes), its calls kept for the test to look at.

///|
/// The made-up core decide_core's Tester was last given (what a test opens something over it with).
let decide_src : Ref[Source?] = Ref(None)

///|
/// The app over the fixture in `mode` (its pages opened as sffix opens them), its calls kept in `calls` and answered;
/// in a desktop's window when `wide`.
fn decide_core(calls : Array[Made], mode : String, wide? : Bool = false, pointing? : @ui.Pointing) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      // a chat's answered, nothing more (and a call's parts as the core makes them, kept: history.tool)
      if name == "history.tool" {
        (base.call)(name, params, done)
      } else {
        done(Ok(Json::object({})))
      }
    },
  }
  decide_src.val = Some(src)
  // (opened as sffix opens it: fixture.mbt)
  open_fixture_over(mode, src)
  let t = if wide {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, pointing?)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  }
  // the pages opened slid in
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "an option tapped in the chat answers its card (decision.answer)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move_to(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("把首页和聊天页的截图都更新")
  let made = named(calls, "decision.answer")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "option"), "一起换")
  assert_eq(number(Some(made[0].params), "seq"), 8.0)
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "an option picked away from the chat's end: the list goes there, after the answer (as for words sent)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move_to(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  // where it is with the list at its end
  let (_, at_end, _, _) = t.rect_of("把首页和聊天页的截图都更新").unwrap()
  // moved on up a little: short of the end, the option still in view; picked
  t.wheel(195.0, 400.0, -120.0)
  let (_, up, _, _) = t.rect_of("把首页和聊天页的截图都更新").unwrap()
  assert_true(up > at_end + 100.0)
  t.tap_text("把首页和聊天页的截图都更新")
  t.run_for(dmax(0.0, t.rest_of("a list") - t.time()))
  // the list at its end again (the answer's row, when it comes, under it)
  let (_, now, _, _) = t.rect_of("把首页和聊天页的截图都更新").unwrap()
  assert_true(now <= at_end + 0.5, msg="the option at \{now}, at \{at_end} with the list at its end")
}

///|
test "忽略 lets the ask go (decision.dismiss), gone at once" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move_to(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("忽略") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  let felt = t.haptics().length()
  t.tap_text("忽略")
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm])
  // let go at once (what it showed only drawn as it closes up)
  t.frame()
  assert_eq(@sfpages.dismissed.count(), 1)
  // (not idle yet: its room closes on the rows' spring, close_gap, till mbui#25 declares its end)
}

///|
test "the chat's \"…\": the menu a row has, pinning it from it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-actions")
  assert_true(t.find("分享…") is Some(_))
  assert_true(t.find("重命名") is Some(_))
  t.tap_text("固定")
  let pinned = named(calls, "chat.pin")
  assert_eq(pinned.length(), 1)
  assert_true(flag(Some(pinned[0].params), "pinned"))
}

///|
test "the chat's own sheet: its agents, and on to the agent's card and its history; what is done with it is not in it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  assert_true(t.find("复制会话链接") is None)
  assert_true(t.find("Claude · Opus 5.5") is Some(_))
  t.tap_text("Claude · Opus 5.5")
  assert_true(t.find("费用估算") is Some(_))
  assert_true(t.find("共工作 1 小时 12 分") is Some(_))
  t.tap_text("共工作 1 小时 12 分")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    History(r, key, _) => {
      assert_eq(r.session, "s-c1")
      assert_eq(key, "s-c1")
    }
    _ => fail("not the history")
  }
  assert_true(t.find("执行历史") is Some(_))
  // (not idle yet: the chat's sheet is still sinking on its spring (kit/sheet.mbt), till mbui#25 declares its end)
}

///|
test "the chat's own sheet, on to its agent's card and to what was said in it: each a step further in, one sheet all the way; back is back to the chat's sheet" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  t.run_for(@ui.move_most_ms)
  let top0 = sheet_tops(t)
  assert_eq(top0.length(), 1)
  for further in [("Claude · Opus 5.5", "费用估算"), (@sf.t("web-main.things.title"), @sf.t("web-main.things.title"))] {
    let (row, shown) = further
    assert_true(t.find(row) is Some(_), msg=row)
    t.tap_text(row)
    assert_true(t.find(shown) is Some(_), msg=row)
    for _ in 0..<40 {
      t.run_for(@ui.frame_period_default)
      assert_eq(sheet_tops(t).length(), 1, msg="\{row}: \{Repr(sheet_tops(t))}")
    }
    // back: the chat's own sheet again, as tall as it was, never two sheets on the way
    t.back()
    assert_true(@sf.presenting(), msg=row)
    for _ in 0..<40 {
      t.run_for(@ui.frame_period_default)
      assert_eq(sheet_tops(t).length(), 1, msg="\{row}: \{Repr(sheet_tops(t))}")
    }
    assert_true(t.find("Claude · Opus 5.5") is Some(_), msg=row)
    assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{row}: \{Repr(sheet_tops(t))} \{Repr(top0)}")
  }
  // back from the chat's own sheet: closed
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(!@sf.presenting())
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
  // (its room closed on its way)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("moon test -p ui -f list_test.mbt") is None)
  t.tap_text("详情")
  assert_true(t.find("Claude Code 2.1.3") is Some(_))
  assert_true(t.find("MacBook Pro · macOS 26 · M1 Pro") is Some(_))
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "the desk's chat: 忽略 at the end of the line saying what an agent needs, with no card, lets it go (decision.dismiss)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-need", wide=true)
  // in the reminder's card at the chat's end, after its words, not under the post that asks
  let (x, y) = t.find_last("忽略").unwrap()
  let (said_x, said_y, said_w, said_h) = t.rect_of(@sffixture.need_state.2).unwrap()
  assert_true(x > said_x + said_w)
  assert_true(y >= said_y && y <= said_y + said_h)
  // its words and 忽略 on lines as high as the bell's column (an option's disc, 20), the bell in their middle: on the
  // state line's 18 laid from the top they stood 1 over it
  // (the one at the chat's end, the lowest drawn: a post's own 忽略 over it where one shows)
  let ends = t.words().filter(fn(w) { w.0 == "忽略" })
  let end = ends.iter().fold(init=ends[0], fn(a, w) { if w.2 > a.2 { w } else { a } })
  let (end_y, end_h) = (end.2, end.4)
  assert_eq((said_h, end_y, end_h), (20.0, said_y, 20.0))
  t.tap(x, y)
  let made = named(calls, "decision.dismiss")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "seq"), 12.0)
}

///|
test "the desk's history beside a chat: a group opens to its steps, a step to its call and what came back" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-history-side", wide=true)
  assert_true(t.find("moon test -p ui -f list_test.mbt") is None)
  t.tap_text("读了 src/ui/list.mbt 等 2 个文件，跑了测试")
  // (the group's room opened on its steps)
  t.run_for(@ui.move_most_ms)
  t.tap_text("跑一遍列表的测试")
  // what the core made of the call and what came back (history.tool, answered as it was asked after that frame), its
  // room opened on its way (reveal_node): the command, its timeout, its output
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("moon test -p ui -f list_test.mbt") is Some(_))
  assert_true(t.find("120000") is Some(_))
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is Some(_))
  // a step closed again, its room closed on its way
  t.tap_text("跑一遍列表的测试")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is None)
}

///|
test "a chat's link" {
  assert_eq(chat_link("ws1/st1", "chat:c-1"), "https://app.still.fail/o/ws1/st1/chat%3Ac-1")
}

///|
test "the chat's sheet and an agent's card as tall as what they show: their last row in it, no room under it to spare" {
  let calls : Array[Made] = []
  // (its last row: the lowest words read out in it, over its foot)
  // (its foot the presenters' sheet's, under what it holds: sheet_panel's)
  for mode in ["chat-info", "chat-agent"] {
    let t = decide_core(calls, mode)
    sheet_rested(t, "sf-present")
    let (sx, sy, sw, sh) = t.get(@ui.Role::Dialog).rect
    let foot = @sf.sheet_panel_foot + nav_foot()
    // (the words read out over its foot and bar: the composer under them is the page's, behind the sheet)
    let inside = t
      .words_said()
      .filter(fn(w) { w.0 != "" && w.5 > 0.0 && w.1 >= sx && w.1 < sx + sw && w.2 >= sy && w.2 + w.4 <= sy + sh - foot })
    assert_true(inside.length() > 0, msg="\{mode}: no words in the sheet")
    let mut last = inside[0]
    for w in inside {
      if w.2 + w.4 > last.2 + last.4 {
        last = w
      }
    }
    let (_, _, ly, _, lh, _) = last
    // under its last row's words: the rest of its row (and its card's padding), the sheet's foot, the bar's
    let under = sy + sh - (ly + lh)
    assert_true(under >= foot && under < foot + 40.0, msg="\{mode}: \{under} under \{last.0} (sheet \{sy}+\{sh}, row \{ly}+\{lh})")
    assert_true(sh < 844.0 * @sf.sheet_most, msg="\{mode}: \{sh}")
  }
}

///|
test "an options card: nothing drawn between two options (SettingParts.kt DecisionOptions)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move_to(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  let (_, above, _, above_h) = t.rect_of("这次只改列表，截图下次再说").unwrap()
  let (_, below, _, _) = t.rect_of("一起换").unwrap()
  // no hairline across the card between the first option's words and the second's
  assert_true(
    t
    .drawn_rects()
    .iter()
    .all(fn(r) { !(r.3 <= 1.5 && r.2 > 100.0 && r.1 > above + above_h && r.1 < below) }),
  )
}

///|
test "the history's post: where it went with its platform's mark, in the accent's ink, a chat here back to it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "history-link")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  app.nav.push(Chat(r))
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, h) = t.rect_of("整理发布清单").unwrap()
  // still.fail's mark (12) just before the name, on its line
  assert_true(
    t
    .shape_boxes()
    .iter()
    .any(fn(i) { i.3 >= 11.0 && i.3 <= 13.0 && i.1 + i.3 <= x && i.1 + i.3 >= x - 6.0 && i.2 < y + h && i.2 + i.4 > y }),
  )
  // the chat it went to is the one under the history: back to it
  t.tap_text("整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
}

///|
test "接力到频道 on a phone: the pages' relay as a sheet, the places the bots are in, one picked, relayed there (chat.relay)" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat-actions")
  let places : Json = {
    "connects": [
      {
        "id": "slack-1",
        "kind": "slack",
        "name": "星火助手",
        "team": "星火",
        "places": [
          { "id": "C1", "name": "dev", "kind": "channel", "used": 20 },
          { "id": "C2", "name": "ops", "kind": "channel", "private": true },
        ],
      },
    ],
  }
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match name {
        "chat.relayPlaces" => done(Ok(places))
        "chat.relay" => done(Ok({ "place": "#dev" }))
        // (what the sheet shows of them, the core's: kept, src/sfkept)
        "chat.relayView" => (base.call)(name, params, done)
        _ => done(Ok(Json::object({})))
      }
    },
  }
  open_fixture_over("chat-actions", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  open_share(t)
  t.tap_text("接力到频道…")
  assert_eq(named(calls, "chat.relayPlaces").length(), 1)
  // (the chat's menu goes, the relay's sheet comes up, to where it rests: the presenters')
  t.run_for(@sf.presented_rest() - t.time())
  // (with touch nothing takes the keyboard's focus as it opens: the keyboard would come up over the places)
  assert_true(!t.ctx().field_focused(), msg="a field focused as the relay opened on a phone")
  assert_true(t.find("接力到频道") is Some(_))
  assert_true(t.find("#dev") is Some(_))
  assert_true(t.find("🔒 #ops") is Some(_))
  // nothing picked: 接力 not lit
  t.tap_text("#dev")
  assert_true(t.find("接力到 #dev") is Some(_))
  assert_true(t.find("开头附一句（可选）") is Some(_))
  // (which bot replies there, under the place picked at its right; its picture before its name)
  let (via_x, _, via_w, _) = t.rect_of("那里由").unwrap()
  let (bot_x, _, _, _) = t.rect_of("星火助手").unwrap()
  // (the picture, 16 wide, between 「那里由」 and the name)
  assert_true(bot_x >= via_x + via_w + 16.0)
  relay_via_at_right(t)
  t.tap_text("接力到 #dev")
  let relayed = named(calls, "chat.relay")
  assert_eq(relayed.length(), 1)
  assert_eq(text(Some(relayed[0].params), "connect"), "slack-1")
  assert_eq(text(Some(relayed[0].params), "channel"), "C1")
  // the sheet leaving as it relayed (no more read out as one), where it went said
  t.frame()
  assert_true(relay_dialog(t) is None, msg="the sheet not leaving once relayed")
  // (said at once, read out: seen as it has come in, toast_said)
  assert_true(toast_said(t, "已接力到 #dev"))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已接力到 #dev") is Some(_))
  // the sheet gone once its way out is over (asserted after it, not in the press's frame: what it showed, the note
  // with it, is kept on that way, where it was emptied before it closed)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("开头附一句（可选）") is None)
}


///|
/// Where words `s` are drawn across (the first drawn so), if they are.
fn words_x(t : @ui.Tester, s : String) -> Double? {
  t.words().iter().find_first(fn(w) { w.0 == s }).map(fn(w) { w.1 })
}

///|
/// From the sheet `t` shows, `row` tapped: the next a page of the same sheet
/// sliding in from its end as the first slides off to its start, every frame one sheet and one scrim, the sheet's top
/// going from where it stood straight to where the next has it; back: the first sliding back where it was, the sheet
/// as tall as it was. `scroll`: the first scrolled so far first, as far scrolled after.
fn steps_in_one_sheet(t : @ui.Tester, row : String, scroll? : Double = 0.0) -> Unit raise {
  let top0 = sheet_tops(t)
  assert_eq(top0.length(), 1, msg="\{row}: \{Repr(top0)}")
  let in_window = fn() { t.words().filter(fn(w) { w.0.length() > 1 && w.1 >= 0.0 && w.1 < 390.0 }) }
  let shown0 = in_window()
  let before : Set[String] = Set::from_array(shown0.map(fn(w) { w.0 }))
  // (in and back once at rest, to know what the next shows of its own and where)
  t.tap_text(row)
  t.run_for(@sf.presented_rest() - t.time())
  let shown1 = in_window()
  let after : Set[String] = Set::from_array(shown1.map(fn(w) { w.0 }))
  let own = shown1.filter(fn(w) { !before.contains(w.0) })
  assert_true(own.length() > 0, msg="\{row}: nothing of its own in \{Repr(t.words().map(fn(w) { w.0 }))}")
  let (next, next_x) = (own[0].0, own[0].1)
  // (words of the first page alone: what it is told by as it slides)
  let firsts = shown0.filter(fn(w) { !after.contains(w.0) })
  assert_true(firsts.length() > 0, msg="\{row}: the first page's words all still shown")
  let (first, x0) = (firsts[0].0, firsts[0].1)
  let top1 = sheet_tops(t)[0]
  assert_true(t.query(Button, label="返回") is Some(_), msg="\{row}: no back key")
  t.back()
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(@sf.presenting(), msg="\{row}: back closed it")
  assert_true((words_x(t, first).unwrap() - x0).abs() < 0.5, msg="\{row}: \{first} back at \{Repr(words_x(t, first))}")
  // (scrolled, where it scrolls: as far scrolled as it comes back)
  let y0 = t.drawn_of(first).unwrap().1
  if scroll > 0.0 {
    t.wheel(195.0, 600.0, scroll)
    t.run_for(@ui.move_most_ms)
  }
  let y_scrolled = t.drawn_of(first).map(fn(p) { p.1 })
  // in, frame by frame
  t.tap_text(row)
  let mut first_x = x0
  let mut next_at = 10000.0
  let mut between = false
  let mut top = top0[0]
  let up = top1 < top0[0]
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    let tops = sheet_tops(t)
    assert_eq(tops.length(), 1, msg="\{row}: \{Repr(tops)}")
    assert_eq(scrim_drawn(t).length(), 1, msg="\{row}")
    // (its top one way only, from where it stood to where the next has it)
    if up {
      assert_true(tops[0] <= top + 0.5, msg="\{row}: \{tops[0]} after \{top}")
    } else {
      assert_true(tops[0] >= top - 0.5, msg="\{row}: \{tops[0]} after \{top}")
    }
    top = tops[0]
    match words_x(t, first) {
      Some(x) => {
        assert_true(x <= first_x + 0.5, msg="\{row}: \{first} at \{x} after \{first_x}")
        first_x = x
      }
      None => first_x = -10000.0
    }
    match words_x(t, next) {
      Some(x) => {
        assert_true(x <= next_at + 0.5, msg="\{row}: \{next} at \{x} after \{next_at}")
        if x > next_x + 20.0 && x < next_x + 370.0 {
          between = true
        }
        next_at = x
      }
      None => ()
    }
  }
  assert_true(between, msg="\{row}: \{next} never seen on its way in")
  assert_true(first_x < x0 - 300.0, msg="\{row}: \{first} not off to the start: \{first_x}")
  assert_true((next_at - next_x).abs() < 0.5, msg="\{row}: \{next} at \{next_at}, not \{next_x}")
  assert_true((top - top1).abs() < 0.5, msg="\{row}: top \{top}, not \{top1}")
  // back, frame by frame: the first in from the start, where it was left
  t.back()
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1, msg="\{row} back: \{Repr(sheet_tops(t))}")
    assert_eq(scrim_drawn(t).length(), 1, msg="\{row} back")
  }
  assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{row}: \{Repr(sheet_tops(t))} \{Repr(top0)}")
  assert_true((words_x(t, first).unwrap() - x0).abs() < 0.5, msg="\{row}: \{first} back at \{Repr(words_x(t, first))}")
  let y_back = t.drawn_of(first).map(fn(p) { p.1 })
  assert_true(
    match (y_back, y_scrolled) {
      (Some(a), Some(b)) => (a - b).abs() < 0.5
      (None, None) => true
      _ => false
    },
    msg="\{row}: \{first} not as it was left: \{Repr(t.drawn_of(first))}, \{Repr(y_scrolled)} (\{y0})",
  )
}

///|
test "小屏: the chat's own sheet on to its agent's card, what its agents wrote and what was said in it: each a page of the same sheet sliding in, the chat's sheet kept as it was left" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-letters-info")
  t.run_for(@sf.presented_rest() - t.time())
  for row in ["Claude · Opus 5.5", @sf.t("web-main.letters.title"), @sf.t("web-main.things.title")] {
    assert_true(t.find(row) is Some(_), msg=row)
    steps_in_one_sheet(t, row)
  }
  t.back()
  t.run_for(@sf.presented_rest() - t.time())
  assert_false(@sf.presenter_visible())
}

///|
test "小屏: the chat's 任务 on to a job: a page of the same sheet sliding in, the list kept as it was left" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-jobs")
  t.run_for(@sf.presented_rest() - t.time())
  steps_in_one_sheet(t, "盯 CI")
}
