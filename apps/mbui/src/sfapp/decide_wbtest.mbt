// Slice 8 over a fake core: the fixture's topics (decide_fixture.mbt's modes), its calls kept for the test to look at.

///|
/// The app over the fixture in `mode` (its pages opened as sffix opens them), its calls kept in `calls` and answered;
/// in a desktop's window when `wide`.
fn decide_core(calls : Array[Made], mode : String, wide? : Bool = false) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      // the 奏 page's taken by the made-up core (its queue as the core keeps it); a chat's answered, nothing more
      // (and a call's parts as the core makes them, kept: history.tool)
      if mode.has_prefix("decisions") || name == "history.tool" {
        (base.call)(name, params, done)
      } else {
        done(Ok(Json::object({})))
      }
    },
  }
  if mode.has_prefix("chat") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  open_fixture(mode)
  let t = if wide {
    @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  }
  // the pages opened slid in
  t.run_for(@ui.nav_push_ms)
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
  t.run_for(@ui.nav_push_ms)
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
test "the desk's chat: 忽略 under an agent's need with no card lets it go (decision.dismiss)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-need", wide=true)
  // under the need, the chat's last post, past the card's own
  let (x, y) = t.find_last("忽略").unwrap()
  let (_, need_y) = t.find("你在手机上试一下新的列表，有问题截个图给我。").unwrap()
  assert_true(y > need_y)
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
test "the 奏 page: an option answers the card in front, the next comes in" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "decisions")
  assert_true(t.find("1 / 2") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  t.tap_text("把首页和聊天页的截图都更新")
  // answered at once, out of the deck: the text card in front now (the answered one only drawn going up)
  let made = named(calls, "decision.answer")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "option"), "一起换")
  assert_true(t.find("1 / 1") is Some(_))
  assert_true(t.find("第 4 个：支付的测试") is Some(_))
  t.run_for(card_up_ms)
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
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
  // let go: dismissed at once, the next in front
  t2.draw()
  assert_eq(named(calls2, "decision.dismiss").length(), 1)
  assert_eq(named(calls2, "decision.answer").length(), 0)
  assert_true(t2.find("1 / 1") is Some(_))
  t2.run_for(card_off_ms)
  t2.assert_idle()
}

///|
test "the 奏 page: the card turns as it is moved across, 4° a width about its top's middle, and on as it flies off" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "decisions")
  // (the deck as wide as the window)
  let width = 390.0
  assert_eq(t.turn_of("把首页和聊天页的截图都更新"), Some(0.0))
  t.press_at(100.0, 400.0)
  t.move(130.0, 400.0)
  t.move(200.0, 400.0)
  // held across: turned as far as it is moved (Decisions.kt rotationZ = drag / width * 4)
  assert_true(dui.drag > 0.0)
  let held = t.turn_of("把首页和聊天页的截图都更新").unwrap()
  assert_true((held - dui.drag / width * card_tilt).abs() < 1.0e-9, msg="\{held} at \{dui.drag}")
  // let go far across: it flies off turning on, the next one in front not turned
  t.move(360.0, 400.0)
  t.release(360.0, 400.0)
  t.run_for(card_off_ms / 2.0)
  assert_true(t.turn_of("把首页和聊天页的截图都更新").unwrap() > held)
  t.run_for(card_off_ms)
  assert_eq(t.turn_of("把首页和聊天页的截图都更新"), None)
  assert_true(t.find("1 / 1") is Some(_))
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "a step's brief, a chat's link" {
  assert_eq(plain_brief("## 标题\n- 一项 **重点**\n```sh\nls\n```"), "标题 一项 重点 ls")
  assert_eq(chat_link("ws1/st1", "ember:c-1"), "https://app.still.fail/o/ws1/st1/ember%3Ac-1")
}

///|
test "the chat's sheet and an agent's card as tall as Android reckons what they show (ChatInfo.kt, AgentSheet.kt fit)" {
  // an agent with turns, a job, a note besides a quota's: its head 22 + 52, its lines and figures 72 + 76, the note 8 +
  // 20, 12, four rows of 40, the foot 24
  let a : Json = {
    "jobs": [{ "id": "j" }],
    "turns": [{ "text": "3 步" }],
    "attention": [{ "kind": "quota" }, { "kind": "failed" }],
  }
  assert_eq(agent_sheet_fit(Some(a)), 446.0)
  // two agents (56 each), 置顶 and Slack and archive and the two always (40 each), its public links (may, two: 40 each
  // and 10), the head 22 + 84 and the foot 10 + 30
  let chat : Json = {
    "agents": [{ "id": 1 }, { "id": 2 }],
    "pinned": true,
    "slackUrl": "https://slack.example/x",
    "publish": { "may": true, "links": [{ "id": "a" }, { "id": "b" }] },
  }
  assert_eq(chat_info_fit(Some(chat), None), 588.0)
  // the sheets drawn that tall over the navigation bar, at rest
  let calls : Array[Made] = []
  for mode in ["chat-info", "chat-agent"] {
    let t = decide_core(calls, mode)
    sheet_rested(t, "decide-sheet")
    let (_, _, _, sh) = t.get(@ui.Dialog).rect
    let chat = (fixture(mode).topic)("chat", chat_params({ station: "ws1/st1", session: "s-c1", title: "", station_name: "" })).value
    let want = if mode == "chat-info" {
      let (view, _, _) = view_of_chat(fixture(mode), { station: "ws1/st1", session: "s-c1", title: "", station_name: "" })
      chat_info_fit(chat, view)
    } else {
      agent_sheet_fit(agent_json(chat, "s-c1"))
    }
    assert_true((sh - want - nav_foot()).abs() < 0.5, msg="\{mode}: \{sh} for \{want}")
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
  t.run_for(@ui.nav_push_ms)
  t.run_for(@ui.nav_push_ms)
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
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() is Chat(_))
}

///|
test "接力到频道: the places the station's bots are in, one picked, relayed there with a note (Relay.kt)" {
  reset()
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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_fixture("chat-info")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  t.tap_text("接力到频道…")
  assert_eq(named(calls, "chat.relayPlaces").length(), 1)
  // (the info sheet goes, the relay sheet comes up, to where it rests)
  t.run_for(@kit.sheet_rest("decide-sheet") - t.time())
  assert_true(t.find("接力到频道") is Some(_))
  assert_true(t.find("#dev") is Some(_))
  assert_true(t.find("🔒 #ops") is Some(_))
  // nothing picked: 接力 not lit
  t.tap_text("#dev")
  assert_true(t.find("接力到 #dev") is Some(_))
  assert_true(t.find("开头附一句（可选）") is Some(_))
  // (which bot replies there, under the place picked, in line with its name; its picture before its name)
  let (name_x, _, _, _) = t.rect_of("#dev").unwrap()
  let (via_x, _, via_w, _) = t.rect_of("那里由").unwrap()
  let (bot_x, _, _, _) = t.rect_of("星火助手").unwrap()
  // (the picture, 16 wide, between 「那里由」 and the name)
  assert_true(bot_x >= via_x + via_w + 16.0)
  assert_eq(via_x, name_x)
  t.tap_text("接力到 #dev")
  let relayed = named(calls, "chat.relay")
  assert_eq(relayed.length(), 1)
  assert_eq(text(Some(relayed[0].params), "connect"), "slack-1")
  assert_eq(text(Some(relayed[0].params), "channel"), "C1")
}

