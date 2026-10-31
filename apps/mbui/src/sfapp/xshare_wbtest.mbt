// Sharing a chat with the viewer's other workspaces on a phone (sfpages' xshare.mbt, its row xshare.mbt) and archiving a
// chat that keeps watch from its sheet (ChatInfo.kt: asked first), over the fixture's chat.

///|
/// The chat's sheet over the fixture's chat, its `chat` topic as `over` makes it; calls kept and answered with nothing.
fn sheet_core(calls : Array[Made], over? : (Json?) -> Json? = fn(v) { v }) -> @ui.Tester {
  new_run()
  let base = fixture("chat-info")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      done(Ok(Json::object({})))
    },
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      if name == "chat" {
        { ..t, value: over(t.value) }
      } else {
        t
      }
    },
  }
  open_fixture_over("chat-info", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "分享给其他 workspace: its row says where; the sheet ticks another and lets their agents send, 完成 says so" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  assert_true(t.find("开源 · 只读") is Some(_))
  t.tap_text("分享给其他 workspace")
  // (the chat's sheet put down, the presenters' sheet up: its own end)
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
  t.tap_text("分享给其他 workspace")
  // (the chat's sheet put down, the presenters' sheet up: its own end)
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
test "归档对话 from the sheet: a chat keeping watch is archived only once asked" {
  let calls : Array[Made] = []
  let t = sheet_core(calls, over=fn(v) {
    match v {
      Some(Object(m)) => {
        let o = m.copy()
        o["watch"] = { "ask": "它还在盯着 CI，归档后会继续盯。" }
        Some(Json::object(o))
      }
      v => v
    }
  })
  t.tap_text("归档对话")
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("它还在盯着 CI，归档后会继续盯。") is Some(_))
  assert_true(t.find("归档「整理发布清单」？") is Some(_))
  // its 归档, beside 取消
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "分享给其他 workspace on a phone: its rows a finger's, 完成 across the sheet in a thumb's reach" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  t.tap_text("分享给其他 workspace")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
  assert_true(grounds.iter().any(fn(r) { r.2 >= 390.0 - 2.0 * 24.0 }), msg="完成 not across the sheet: \{grounds}")
}

///|
/// A phone's buttons are drawn as the large screen's, 34 (button_height: the user, 2026-10-31, 「按钮既然缩，那就跟大屏一致
/// 呗」); a finger reaches one from a fingertip round it all the same (mbui's press_reach: a target under 44 grown to it
/// round its middle where the finger is on nothing else).
test "分享给其他 workspace on a phone: 完成 drawn as the large screen's, reached past its edge" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  t.tap_text("分享给其他 workspace")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
