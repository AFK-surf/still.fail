// Sharing a chat as a picture with keyboard and mouse (sfpages publish.mbt, Publish.tsx PublishDialog): from the chat's
// info, over the whole window, the picture as it would be; 复制图片 puts it on the clipboard, one PNG of it all.

///|
test "wide: 分享图片 from the chat's info: the picture as it would be over the window under its bar; 复制图片, a button in words at its end, copies it whole" {
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
  // its bar across the top, as a file opened has: what it is and how much was hidden
  assert_true(t.find("共隐藏 1 处疑似机密") is Some(_))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  // its messages as the chat's list draws them (the viewer's own at its end, an agent's vault request as it ended)
  assert_true(picture_mine_at_end(t), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("已允许使用「Axiom 查询 token」") is Some(_))
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
  // its button says so a moment, in words
  t.frame()
  assert_true(t.find("已复制") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "wide: a message right clicked offers 分享这一轮, which shares its turn as a picture (chat.publishPreview by its seq)" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("chat")
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
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.right_click(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  t.tap_text("分享这一轮")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  assert_eq(number(Some(asked[0].params), "turn"), 11.0)
}

///|
test "wide: hovering a message offers 分享这一轮, which shares its turn as a picture (chat.publishPreview by its seq)" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("chat")
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
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let before = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.move(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  assert_eq(t.rect_of("做完了：列表、跳到最新的按钮").unwrap(), before)
  let button = t.get(Button, label="分享这一轮").rect
  // Beside the author's name and time, above the words, rather than at their far end.
  assert_true(button.1 + button.3 <= before.1)
  assert_true(button.0 < before.0 + 200.0)
  t.move(button.0 + button.2 / 2.0, button.1 + button.3 / 2.0)
  t.frame()
  assert_true(t.query(Button, label="分享这一轮") is Some(_))
  t.click(Button, label="分享这一轮")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  assert_eq(number(Some(asked[0].params), "turn"), 11.0)
}
