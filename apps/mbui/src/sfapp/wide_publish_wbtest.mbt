// Sharing a chat as a picture with keyboard and mouse (sfpages publish.mbt): from the chat's
// info, over the whole window, the picture as it would be; 复制图片 puts it on the clipboard, one PNG of it all.

///|
test "wide: 分享图片 from the chat's info: the picture as it would be over the window under its bar; 复制图片, a button in words at its end, copies it whole" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat-info")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="更多")
  t.frame()
  t.frame()
  open_share(t)
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
  assert_true(ticks_before_words(t, @sf.message_avatar_reach), msg=Repr(t.all(Checkbox, label="放进图片").map(fn(n) { n.rect })).to_string())
  t.click(Button, label="复制图片")
  t.frame()
  assert_eq(t.shots().length(), 1)
  // the picture on the clipboard: as wide as the chat's column (760) at two pixels a point, as tall as it all is
  match t.clipboard_png() {
    Some(png) =>
      match png_size(png) {
        Some((pw, ph)) => {
          assert_true(pw == 1520 && ph > 600, msg="\{Repr((pw, ph))}")
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
  new_run()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let src = fixture("chat-info")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="更多")
  t.frame()
  t.frame()
  open_share(t)
  t.tap_text("分享图片")
  t.frame()
  t.frame()
  // (the words as the theme sets a meta line: the dot by that line's middle, not by a line of a height of its own; the
  // chat's own line under the picture's too)
  let lines = t.text_runs().filter(fn(r) { r.text.contains("本对话内") })
  assert_true(lines.length() > 0 && lines.all(fn(r) { r.text == "已允许使用 Axiom 查询 token · 本对话内" }), msg="\{Repr(lines)}")
  for r in lines {
    let mid = (r.top + r.bottom) / 2.0
    let dots = t.boxes().filter(fn(b) { b.w == 6.0 && b.h == 6.0 && b.x < r.x0 && b.y >= r.top - 6.0 && b.y <= r.bottom })
    assert_eq(dots.map(fn(b) { b.y + b.h / 2.0 }), [mid])
  }
}

///|
test "wide: right click copies the whole message for its author and the viewer, including Markdown and newlines" {
  let words = @sffixture.fixture_md
  for mine in [false, true] {
    new_run()
    let base = fixture("chat")
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let got = base.topic(name, params).get().snapshot()
        guard name == "chat" && got.value is Some(Object(chat)) else { return got }
        let out = chat.copy()
        let messages = items(got.value, "messages").copy()
        match messages[messages.length() - 1] {
          Object(last) => {
            let m = last.copy()
            m["text"] = Json::string(words)
            m["mine"] = Json::boolean(mine)
            messages[messages.length() - 1] = Json::object(m)
          }
          _ => ()
        }
        out["messages"] = Json::array(messages)
        { ..got, value: Some(Json::object(out)) }
      },
    }
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
    t.run_for(@ui.move_most_ms)
    let (x, y, _, _) = t.rect_of("截图换成").unwrap()
    t.right_click(x + 8.0, y + 8.0)
    t.frame()
    t.frame()
    t.tap_text("复制消息")
    t.frame()
    assert_eq(t.clipboard(), words)
    assert_true(toast_said(t, "已复制"))
  }
}

///|
test "wide: a message right clicked offers 多选, which opens the chat's picture with that message alone ticked (chat.publishPreview of the whole chat)" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.right_click(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  assert_true(t.find("复制消息链接") is Some(_))
  t.tap_text("多选")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // (the whole chat asked: the message ticked alone once it is read)
  assert_true(field(Some(asked[0].params), "turn") is None)
}

///|
test "wide: a link in a message right clicked opens its own menu alone, not the message's 多选 under it" {
  new_run()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // (Ana's message, up the list: scrolled to till it is in the list's middle)
  let link = "https://example.com/review/42"
  for _ in 0..<20 {
    match t.run_rects(link) {
      [(_, y, _, h), ..] if y + h / 2.0 > 160.0 && y + h / 2.0 < 600.0 => break
      [(_, y, _, h), ..] if y + h / 2.0 >= 600.0 => t.wheel(800.0, 400.0, 200.0)
      _ => t.wheel(800.0, 400.0, -300.0)
    }
  }
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.run_rects(link)[0]
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("复制链接") is Some(_))
  assert_true(t.find("多选") is None)
  assert_true(t.find("复制消息链接") is None)
  assert_true(t.find("复制消息") is None)
  // chosen, nothing comes after it
  t.tap_text("复制链接")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.clipboard(), link)
  assert_true(t.find("多选") is None)
}

///|
test "wide: the message header's ⋯ offers the same message actions as a right click" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let before = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  // (nothing on the head until the pointer rests on the message)
  assert_true(t.query(Button, label="更多操作") is None)
  t.move_to(x + 24.0, y + 8.0)
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
  t.tap_text("复制消息")
  t.frame()
  assert_eq(t.clipboard(), "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。")
  t.move_to(x + 24.0, y + 8.0)
  t.frame()
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  t.tap_text("复制消息链接")
  t.frame()
  assert_eq(t.clipboard(), "https://app.still.fail/o/ws1/st1/s-c1?message=11")
  assert_eq(named(calls, "chat.publishPreview").length(), 0)
  t.move_to(x + 24.0, y + 8.0)
  t.frame()
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  t.tap_text("多选")
  t.frame()
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // (the whole chat asked: the message ticked alone once it is read)
  assert_true(field(Some(asked[0].params), "turn") is None)
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
    new_run()
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
    t.run_for(@ui.move_most_ms)
    let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
    t.move_to(x + 24.0, y + 8.0)
    t.frame()
    t.frame()
    t.click(Button, label="更多操作")
    t.run_for(@ui.move_most_ms)
    let (_, mx, my, _, _, _) = t.words().filter(fn(w) { w.0 == "复制消息链接" })[0]
    if how == "escape" {
      t.key(@ui.key_escape)
    } else {
      // (the pointer away from the message, then a click there: the ⋯ shown only under it goes with the menu)
      t.move_to(400.0, 250.0)
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
test "wide: the message's ⋯ menu closed by its ⋯ pressed again, the pointer then off the message: goes out where it hung" {
  new_run()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.move_to(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  // (where the ⋯ is, read before its menu covers the page)
  let (bx, by, bw, bh) = t.get(Button, label="更多操作").rect
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  let (_, mx, my, _, _, _) = t.words().filter(fn(w) { w.0 == "复制消息链接" })[0]
  // (pressed again as the host hands it on, then the pointer off the message, no frame between)
  t.touch(0, bx + bw / 2.0, by + bh / 2.0)
  t.touch(2, bx + bw / 2.0, by + bh / 2.0)
  t.touch(1, 400.0, 250.0)
  t.frame()
  assert_eq(drawn_near(t, "复制消息链接", mx, my), Some(true), msg="the frame after")
  t.frame()
  assert_eq(drawn_near(t, "复制消息链接", mx, my), Some(true), msg="two frames after")
  t.run_for(@ui.move_most_ms)
  assert_eq(drawn_near(t, "复制消息链接", mx, my), None, msg="gone")
}

///|
test "touch: the message header has neither; the held bar copies its position link" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  assert_true(t.query(Button, label="分享图片") is None)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  // (the bar over what is held, its buttons, where the old page draws the chat; where it is made as nodes, the
  // system's text menu over it, the page's own items after its copy and select all)
  match t.query(Button, label="复制链接") {
    Some(_) => {
      assert_true(t.query(Button, label="多选") is Some(_))
      t.click(Button, label="复制链接")
    }
    None => {
      let own = t.text_menu_own()
      assert_true(own.contains("多选"), msg="\{Repr(own)}")
      guard own.search("复制链接") is Some(k) else { fail("no 复制链接 over what is held: \{Repr(own)}") }
      t.key(@hostapi.key_menu_own + k)
    }
  }
  assert_eq(t.clipboard(), "https://app.still.fail/o/ws1/st1/s-c1?message=11")
  assert_eq(pk.ts, "")
  assert_eq(@ui.picked_now(), None)
  assert_eq(named(calls, "chat.publishPreview").length(), 0)
}
