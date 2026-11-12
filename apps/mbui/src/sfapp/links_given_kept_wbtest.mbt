// A link the system gives the running app (links_wbtest.mbt's, from outside), with the app built as a host builds it
// (Tester::check_looks(false)): a part kept as its nodes is drawn as kept, not built again whole after it, so what
// takes the link (narrow_shell.mbt's signed_in_frame, entry_tree.mbt's signed_out_tree) is built only as what it reads
// says one waits (sfbase's links_wait).

///|
test "kept as a host keeps it: an App Link's chat alone over its workspace's Home" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat", as_host=true)
  app.nav.push(Settings)
  t.run_for(@ui.move_most_ms)
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/o/ws1/st1/s-c2\"}")
  t.frame()
  let pages = app.nav.pages()
  assert_eq(pages.length(), 2)
  assert_true(pages[0] == Home)
  assert_true(top_chat() == Some(chat_ref("ws1/st1", "s-c2")))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("好的，我来处理。") is Some(_))
  // taken once
  t.frame()
  assert_eq(named(calls, "link.parse").length(), 1)
}

///|
test "kept as a host keeps it, on the wide frame: an App Link's chat on top" {
  for size in [(1280.0, 800.0), (900.0, 700.0)] {
    let calls : Array[Made] = []
    let t = links_core(calls, "chat", w=size.0, h=size.1, platform=0, as_host=true)
    t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/o/ws1/st1/s-c2\"}")
    t.frame()
    assert_true(top_chat() == Some(chat_ref("ws1/st1", "s-c2")), msg="the linked chat at \{size.0}")
    t.frame()
    assert_eq(named(calls, "link.parse").length(), 1, msg="taken once at \{size.0}")
  }
}

///|
test "kept as a host keeps it: an invitation's link, what it leads to, then joined" {
  let calls : Array[Made] = []
  let t = links_core(calls, "home", as_host=true)
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok1\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("加入「新的工作室」") is Some(_))
  assert_true(t.find("周邀请你以成员身份加入。") is Some(_))
  let read = named(calls, "invitation.preview")
  assert_eq(read.length(), 1)
  assert_eq(text(Some(read[0].params), "token"), "tok1")
  assert_eq(text(Some(read[0].params), "account"), "u1")
  t.tap_text("以 lin@example.com 加入")
  assert_eq(named(calls, "invitation.accept").length(), 1)
  assert_eq(app.picked.get(), "ws3")
  assert_true(toast_said(t, "已加入「新的工作室」"))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已加入「新的工作室」") is Some(_))
}

///|
test "kept as a host keeps it: an invitation that cannot be used, why" {
  let calls : Array[Made] = []
  let t = links_core(calls, "home", invitation=Err({ "code": "gone", "message": "邀请已过期" }), as_host=true)
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok2\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("邀请无效") is Some(_))
  assert_true(t.find("邀请已过期") is Some(_))
  assert_true(t.find("使用其他链接") is None)
  t.tap_text("关闭")
  assert_true(!sheet_open())
}

///|
test "kept as a host keeps it: an invitation's link opened signed out, sign in first" {
  let calls : Array[Made] = []
  let t = links_core(calls, "signin", as_host=true)
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok3\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("登录 still.fail") is Some(_))
  assert_true(t.find("你收到了一个 still.fail workspace 的邀请。先登录，再决定是否加入。") is Some(_))
  assert_eq(named(calls, "invitation.preview").length(), 0)
}
