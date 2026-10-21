// Sharing a chat with the viewer's other workspaces (xshare.mbt; ChatInfo.kt ShareRow, openShare) and archiving a
// chat that keeps watch from its sheet (ChatInfo.kt: asked first), over the fixture's chat.

///|
/// The chat's sheet over the fixture's chat, its `chat` topic as `over` makes it; calls kept and answered with nothing.
fn sheet_core(calls : Array[Made], over? : (Json?) -> Json? = fn(v) { v }) -> @ui.Tester {
  reset()
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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_fixture("chat-info")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "分享给其他 workspace: its row says where; the sheet ticks another and lets their agents send, 完成 says so" {
  let calls : Array[Made] = []
  let t = sheet_core(calls)
  assert_true(t.find("开源 · 只读") is Some(_))
  t.tap_text("分享给其他 workspace")
  t.run_for(@kit.sheet_rest("decide-sheet") - t.time())
  assert_true(t.find("所选 workspace 中的 agent 可读取此对话") is Some(_))
  t.tap_text("日常")
  t.tap_text("可发送消息")
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
  t.run_for(@kit.sheet_rest("decide-sheet") - t.time())
  // the one it is shared with let go: none left
  t.tap_text("开源")
  t.tap_text("可发送消息")
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
