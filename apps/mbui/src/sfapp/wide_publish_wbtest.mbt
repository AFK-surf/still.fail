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
  t.run_for(@ui.move_most_ms)
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
  assert_true(t.find("已允许使用 Axiom 查询 token") is Some(_))
  // each message's box to tick in a column of its own before them (and before their pictures out in the margin)
  assert_true(ticks_before_words(t, @sf.message_avatar_reach), msg=t.all(Checkbox, label="放进图片").map(fn(n) { n.rect }).to_string())
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
test "wide: a vault request's outcome line has its dot in the middle of its words' line, its name set apart without quotes" {
  reset()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, fixture("chat-info")) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.tap_text("分享图片")
  t.frame()
  t.frame()
  // (the words as the theme sets a meta line: the dot by that line's middle, not by a line of a height of its own; the
  // chat's own line under the picture's too)
  let lines = t.text_runs().filter(fn(r) { r.text.contains("本对话内") })
  assert_true(lines.length() > 0 && lines.all(fn(r) { r.text == "已允许使用 Axiom 查询 token · 本对话内" }), msg="\{lines}")
  for r in lines {
    let mid = (r.top + r.bottom) / 2.0
    let dots = t.boxes().filter(fn(b) { b.w == 6.0 && b.h == 6.0 && b.x < r.x0 && b.y >= r.top - 6.0 && b.y <= r.bottom })
    assert_eq(dots.map(fn(b) { b.y + b.h / 2.0 }), [mid])
  }
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
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.right_click(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  assert_true(t.find("复制消息链接") is Some(_))
  t.tap_text("分享这一轮")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  assert_eq(number(Some(asked[0].params), "turn"), 11.0)
}

///|
test "wide: the message header's ⋯ offers 复制消息链接 and 分享这一轮, the two a right click offers" {
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
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let before = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  // (nothing on the head until the pointer rests on the message)
  assert_true(t.query(Button, label="更多操作") is None)
  t.move(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  assert_eq(t.rect_of("做完了：列表、跳到最新的按钮").unwrap(), before)
  // one ⋯ on the header line, no bare marks beside it
  let more = t.get(Button, label="更多操作").rect
  assert_true(more.1 + more.3 <= before.1)
  assert_true(t.query(Button, label="分享图片") is None)
  assert_true(t.query(Button, label="复制链接") is None)
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  t.tap_text("复制消息链接")
  t.frame()
  assert_eq(t.clipboard(), "https://app.still.fail/o/ws1/st1/s-c1?message=11")
  assert_eq(named(calls, "chat.publishPreview").length(), 0)
  t.move(x + 24.0, y + 8.0)
  t.frame()
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  t.tap_text("分享这一轮")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  assert_eq(number(Some(asked[0].params), "turn"), 11.0)
}

///|
/// Whether `words` are drawn now within 24 of (x, y) (a panel going out shrinks a little toward where it hangs): None
/// where they are not drawn.
fn drawn_near(t : @ui.Tester, words : String, x : Double, y : Double) -> Bool? {
  for w in t.words() {
    if w.0 == words {
      return Some((w.1 - x).abs() < 24.0 && (w.2 - y).abs() < 24.0)
    }
  }
  None
}

///|
test "wide: the message's ⋯ menu goes out where it hung, closed by Escape or a click away" {
  for how in ["escape", "away"] {
    reset()
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
    let t = @ui.Tester::new(fn(c) { view(c, fixture("chat")) }, w=1280.0, h=800.0, platform=0)
    t.run_for(@ui.move_most_ms)
    let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
    t.move(x + 24.0, y + 8.0)
    t.frame()
    t.frame()
    t.click(Button, label="更多操作")
    t.run_for(@ui.move_most_ms)
    let (_, mx, my, _, _, _) = t.words().filter(fn(w) { w.0 == "复制消息链接" })[0]
    if how == "escape" {
      t.key(@ui.key_escape)
    } else {
      // (the pointer away from the message, then a click there: the ⋯ shown only under it goes with the menu)
      t.move(400.0, 250.0)
      t.frame()
      t.tap(400.0, 250.0)
    }
    // its exit's first frames: drawn, where it was (not cut off, not from the window's corner)
    t.frame()
    assert_eq(drawn_near(t, "复制消息链接", mx, my), Some(true), msg="\{how}: the frame after")
    t.frame()
    assert_eq(drawn_near(t, "复制消息链接", mx, my), Some(true), msg="\{how}: two frames after")
    t.frame()
    assert_eq(drawn_near(t, "复制消息链接", mx, my), Some(true), msg="\{how}: three frames after")
    t.run_for(@ui.move_most_ms)
    assert_eq(drawn_near(t, "复制消息链接", mx, my), None, msg="\{how}: gone")
  }
}

///|
test "touch: the message header has neither; the held bar copies its position link" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  assert_true(t.query(Button, label="分享图片") is None)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(t.query(Button, label="分享这一轮") is Some(_))
  t.click(Button, label="复制链接")
  assert_eq(t.clipboard(), "https://app.still.fail/o/ws1/st1/s-c1?message=11")
  assert_eq(pk.ts, "")
  assert_eq(named(calls, "chat.publishPreview").length(), 0)
}
