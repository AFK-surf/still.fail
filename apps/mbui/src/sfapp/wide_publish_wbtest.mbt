// Sharing a chat as a picture with keyboard and mouse (sfpages publish.mbt, Publish.tsx PublishDialog): from the chat's
// info, over the whole window, the picture as it would be; 复制图片 puts it on the clipboard, one PNG of it all.

///|
test "wide: 分享图片 from the chat's info: the picture as it would be over the window under its bar; 复制图片 copies it whole" {
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
  t.tap_text("分享图片")
  t.frame()
  t.frame()
  assert_eq(named(calls, "chat.publishPreview").length(), 1)
  assert_true(t.find("部署登录页") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  t.click(Button, label="复制图片")
  t.frame()
  assert_eq(named(calls, "chat.publish").length(), 0)
  assert_eq(t.shots().length(), 1)
  // the picture on the clipboard: as wide as the chat's column (760) at two pixels a point, as tall as it all is
  match t.clipboard_png() {
    Some(png) =>
      match png_size(png) {
        Some((pw, ph)) => {
          assert_true(pw == 1520 && ph > 600, msg="\{(pw, ph)}")
          assert_eq(t.clipboard_label(), "still.fail")
        }
        None => fail("not a PNG")
      }
    None => fail("no picture copied")
  }
}
