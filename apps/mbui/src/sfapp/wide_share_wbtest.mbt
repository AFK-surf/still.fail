// Sharing a chat with keyboard and mouse (sfpages xshare.mbt, ChatPage.tsx ShareDialog: the presenters' dialog): from the chat's info, the workspaces
// it may be shared with, ticked as it is shared; 完成 tells the core (chat.xshare).

///|
test "wide: 分享给其他 workspace from the chat's info: a dialog lists the workspaces, ticked as shared; 完成 sends chat.xshare" {
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.tap_text("分享给其他 workspace")
  // (the dialog come in, @kit.dialog_in, and still: the corner rule holds every frame drawn so, its tick rows' boxes
  // clear of their corners)
  t.run_for(@kit.dialog_ms)
  t.frame()
  assert_eq(t.corner_faults(), [])
  assert_true(t.find("日常") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("开源") is Some(_))
  let (dx, dy, dw, dh) = t.query(Button, label="完成").unwrap().rect
  t.tap(dx + dw / 2.0, dy + dh / 2.0)
  t.frame()
  let sent = named(calls, "chat.xshare")
  assert_eq(sent.length(), 1)
  assert_eq(field(Some(sent[0].params), "to"), Some(Json::array([Json::string("ws3")])))
  // (the dialog goes as a presenter does: back the way it came, @kit.pop_out)
  t.run_for(@kit.pop_out_ms)
  t.frame()
  assert_true(t.find("日常") is None, msg="the dialog gone")
}
