// The desktop's publishing (sfdesk publish.mbt, Publish.tsx PublishDialog): from the chat's info, over the whole
// window, what a snapshot would hold; 发布 publishes it (chat.publish), the link in a small dialog after.

///|
test "wide: 公开分享 from the chat's info: the snapshot's messages over the window under its bar; 发布 publishes it, its link to copy after" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("chat-info")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "chat.publish" => done(Ok({ "id": "p3", "link": "https://share.still.fail/#st.p3.key" }))
        _ => (base.call)(name, params, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.tap_text("公开分享")
  t.frame()
  t.frame()
  assert_eq(named(calls, "chat.publishPreview").length(), 1)
  assert_true(t.find("持有链接的任何人都可查看这些消息；station 离线时无法打开") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  let (bx, by, bw, bh) = t.query(Button, label="发布").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let sent = named(calls, "chat.publish")
  assert_eq(sent.length(), 1)
  assert_eq(number(Some(sent[0].params), "upto"), 9.0)
  assert_true(t.find("https://share.still.fail/#st.p3.key") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}
