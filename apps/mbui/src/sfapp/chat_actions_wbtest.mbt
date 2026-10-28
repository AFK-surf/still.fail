// What can be done with a chat, offered alike by its row's menu and its info (sfpages chat_actions.mbt; pengxiao,
// 2026-10-28): the chat's info beside its bar and its sheet offer what its row's menu does.

///|
test "wide: the chat's info offers what its row's menu does: 固定, 重命名, 保留, its link and sessions' files, 归档; 保留 keeps it (chat.keep)" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("chat-info")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  let words = t.words().map(fn(w) { w.0 })
  for item in ["固定", "重命名", "保留", "复制会话链接", "复制 session 文件路径", "分享给其他 workspace", "归档"] {
    assert_true(words.contains(item), msg="\{item}: \{words.join("|")}")
  }
  t.click(Button, label="保留")
  t.frame()
  let kept = named(calls, "chat.keep")
  assert_eq(kept.length(), 1)
  assert_true(flag(Some(kept[0].params), "kept"))
  // the info closed by it, opened again: its sessions' files copied
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.click(Button, label="复制 session 文件路径")
  t.frame()
  assert_true(named(calls, "session.transcript").length() > 0)
}

///|
test "the chat's sheet offers what its row's menu does: 保留 and its sessions' files beside 固定 and its link" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  for item in ["固定到列表顶部", "保留", "复制会话链接", "复制 session 文件路径", "归档对话"] {
    assert_true(t.find(item) is Some(_), msg=item)
  }
  t.tap_text("保留")
  assert_eq(named(calls, "chat.keep").length(), 1)
}
