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
      calls.push({ name, params, bytes: None, done, heard: None })
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
  t.move(195.0, 400.0)
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
  t.move(195.0, 400.0)
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
  t.move(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("忽略") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("忽略")
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  // let go at once (what it showed only drawn as it closes up)
  t.frame()
  assert_eq(@sfpages.dismissed.length(), 1)
  // (not idle yet: its room closes on the rows' spring, close_gap, till mbui#25 declares its end)
}

///|
test "the chat's own sheet: its agents, pinning it, and on to the agent's card and its history" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  assert_true(t.find("复制会话链接") is Some(_))
  assert_true(t.find("Claude · Opus 5.5") is Some(_))
  t.tap_text("固定到列表顶部")
  let pinned = named(calls, "chat.pin")
  assert_eq(pinned.length(), 1)
  assert_true(flag(Some(pinned[0].params), "pinned"))
  t.tap_text("Claude · Opus 5.5")
  assert_true(t.find("费用估算") is Some(_))
  assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is Some(_))
  t.tap_text("8 轮 · 共干了 1 小时 12 分")
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
test "the history: a group opens to its steps, a step to its call and what came back" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "history")
  // opened by the fixture: the command and its output, the edit as a diff
  assert_true(t.find("moon test -p ui -f list_test.mbt") is Some(_))
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is Some(_))
  // a step closed again
  t.tap_text("跑一遍列表的测试")
  assert_true(t.find("moon test -p ui -f list_test.mbt") is None)
  t.tap_text("详情")
  assert_true(t.find("Claude Code 2.1.3") is Some(_))
  assert_true(t.find("Mac Studio · macOS 26 · M2 Max") is Some(_))
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
  let (_, end_y, _, end_h) = t.rect_of("忽略").unwrap()
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
  t.tap_text("跑一遍列表的测试")
  // what the core made of the call and what came back (history.tool, answered as it was asked after that frame): the
  // next frame shows the command, its timeout, its output
  t.frame()
  assert_true(t.find("moon test -p ui -f list_test.mbt") is Some(_))
  assert_true(t.find("120000") is Some(_))
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is Some(_))
  // a step closed again
  t.tap_text("跑一遍列表的测试")
  assert_true(t.find("Total tests: 9, passed: 9, failed: 0.") is None)
}

///|
test "a chat's link" {
  assert_eq(chat_link("ws1/st1", "ember:c-1"), "https://app.still.fail/o/ws1/st1/ember%3Ac-1")
}

///|
test "the chat's sheet and an agent's card as tall as what they show: their last row in it, no room under it to spare" {
  let calls : Array[Made] = []
  // (the chat's last: its public links' last, Bob's)
  // (its foot the presenters' sheet's, under what it holds: sheet_panel's)
  for case in [("chat-info", "Bob"), ("chat-agent", "后台")] {
    let (mode, last) = case
    let t = decide_core(calls, mode)
    sheet_rested(t, "sf-present")
    let (_, sy, _, sh) = t.get(@ui.Role::Dialog).rect
    let (_, ly, _, lh) = t.rect_of(last).unwrap()
    // under its last row's words: the rest of its row (and its card's padding), the sheet's foot, the bar's
    let under = sy + sh - (ly + lh)
    let foot = @sf.sheet_panel_foot + nav_foot()
    assert_true(under >= foot && under < foot + 40.0, msg="\{mode}: \{under} under \{last} (sheet \{sy}+\{sh}, row \{ly}+\{lh})")
    assert_true(sh < 844.0 * @sf.sheet_most, msg="\{mode}: \{sh}")
  }
}

///|
test "an options card: nothing drawn between two options (SettingParts.kt DecisionOptions)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  t.move(195.0, 400.0)
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
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
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
  let base = fixture("chat-info")
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
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "chat.relayPlaces" => done(Ok(places))
        "chat.relay" => done(Ok({ "place": "#dev" }))
        // (what the sheet shows of them, the core's: kept, src/sfkept)
        "chat.relayView" => (base.call)(name, params, done)
        _ => done(Ok(Json::object({})))
      }
    },
  }
  open_fixture_over("chat-info", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("接力到频道…")
  assert_eq(named(calls, "chat.relayPlaces").length(), 1)
  // (the info sheet goes, the relay's sheet comes up, to where it rests: the presenters')
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
  // the sheet gone, where it went said
  t.frame()
  assert_true(t.find("开头附一句（可选）") is None)
  // (said at once, read out: seen as it has come in, toast_said)
  assert_true(toast_said(t, "已接力到 #dev"))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已接力到 #dev") is Some(_))
}

