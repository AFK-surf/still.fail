// still.fail's motion over its made-up chats, frame by frame (docs/stillfail-motion.md): Home's rows as the list
// changes, words sent flying into their bubble, the way to the newest coming and going.

///|
test "Home: a chat with news goes to the top on the rows' spring, the rows it passes going down" {
  // (the clock set after reset, which puts the fixture's own back)
  reset()
  let clock = Ref::new(0.0)
  fix_clock.val = fn() { clock.val }
  fix_wake.val = fn(_) {  }
  let src = fixture("home-motion")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.draw()
  let (_, y_ci) = t.drawn_of("盯着 CI，绿了告诉我").unwrap()
  let (_, y_top) = t.drawn_of("整理发布清单").unwrap()
  // its news comes (the fixture's first step)
  clock.val = 2001.0
  t.frame()
  // laid out at the top already, drawn where it was
  let (_, y0) = t.drawn_of("盯着 CI，绿了告诉我").unwrap()
  assert_true((y0 - y_ci).abs() < 0.5, msg="\{y0} \{y_ci}")
  t.frame()
  t.frame()
  t.frame()
  let (_, y1) = t.drawn_of("盯着 CI，绿了告诉我").unwrap()
  assert_true(y1 < y0 - 1.0 && y1 > y_top, msg="\{y1}")
  // the first row, pushed down a row, goes there too
  let (_, f1) = t.drawn_of("整理发布清单").unwrap()
  assert_true(f1 > y_top && f1 < y_top + 66.0, msg="\{f1}")
  // the rows' spring at rest
  t.run_for(@motion.row_spring.duration(y_ci - y_top, 0.0, 0.0))
  let (_, y2) = t.drawn_of("盯着 CI，绿了告诉我").unwrap()
  assert_true((y2 - y_top).abs() < 0.5)
  let (_, f2) = t.drawn_of("整理发布清单").unwrap()
  assert_true((f2 - y_top - 66.0).abs() < 0.5)
  fix_clock.val = fix_frame_clock
  fix_wake.val = fix_frame_wake
}

///|
test "words sent fly from the field into their bubble" {
  // the fixture's own station takes what is sent: the outbox at once, the message after
  reset()
  let clock = Ref::new(0.0)
  fix_clock.val = fn() { clock.val }
  fix_wake.val = fn(_) {  }
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  // the chat pushed in over Home
  t.run_for(@ui.nav_push_ms)
  t.tap_text("发消息")
  t.type_text("发布前再看一眼签名")
  t.tap_once(390.0 - 10.0 - 8.0 - 18.0, 844.0 - 10.0 - 8.0 - 18.0)
  // the words as typed, over the field, until their row is in the list
  let (fx, fy) = t.drawn_of("发布前再看一眼签名").unwrap()
  // until their row is in the list, the words stay where they were typed
  let mut landed = false
  let mut moved = false
  // frame by frame until the flight is over (at most its wait for the row and its own time)
  let end = t.time() + flight_wait_ms + flight_ms
  while t.time() < end && flight_of("ws1/st1:s-c1") is Some(_) {
    t.frame()
    match t.drawn_of("发布前再看一眼签名") {
      Some((x, y)) => {
        if (x - fx).abs() > 2.0 || (y - fy).abs() > 2.0 {
          moved = true
        }
        match t.rect_of("发布前再看一眼签名") {
          Some(r) =>
            if (x - r.0).abs() < 0.5 && (y - r.1).abs() < 0.5 && moved {
              landed = true
            }
          None => ()
        }
      }
      None => ()
    }
  }
  assert_true(moved && landed, msg="\{moved} \{landed}")
  fix_clock.val = fix_frame_clock
  fix_wake.val = fix_frame_wake
}

///|
test "Home: the first rows, after the list waited, come as they are and a tap on one opens it at once" {
  reset()
  let src = fixture("home")
  let waiting = Ref::new(true)
  let src = {
    ..src,
    topic: fn(name, params) {
      if name == "chats" && waiting.val {
        { value: None, error: None, version: 0 }
      } else {
        (src.topic)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("整理发布清单") is None)
  // the list is read: its rows are there, drawn where they are laid out, from the first frame (as the e2e's drive
  // taps them: where they are, as soon as they are still)
  waiting.val = false
  t.frame()
  let (x, y, w, h) = t.rect_of("整理发布清单").unwrap()
  let (dx, dy) = t.drawn_of("整理发布清单").unwrap()
  assert_true((dx - x).abs() < 0.5 && (dy - y).abs() < 0.5, msg="\{dx},\{dy} \{x},\{y}")
  t.frame()
  t.tap_once(x + w / 2.0, y + h / 2.0)
  assert_eq(app.nav.depth(), 2)
}

///|
test "send tapped while the composer grows goes at once, the field emptied" {
  // what the e2e caught: the capsule growing to two lines more (260 ms) when send is tapped; send is laid out on the
  // capsule's bottom edge from the first frame, so the tap is send's and the words go by chat.send
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一行\n第二行\n第三行")
  t.frame()
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "第一行\n第二行\n第三行")
  let (_, after, _, _) = t.ime()
  assert_eq(after, "")
  // the words sent wait for their row, which this core never gives; the composer's room let go after
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
}

///|
test "＋'s sheet going down takes no tap: the field tapped meanwhile is the field's" {
  // what the e2e caught: the field tapped while the sheet, let go of, still went down under its scrim
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap(10.0 + 8.0 + 18.0, 844.0 - 10.0 - 8.0 - 18.0)
  assert_true(cui.attach)
  // the scrim, tapped: let go of (a frame, not settled: it is still going down)
  t.touch(0, 195.0, 200.0)
  t.touch(2, 195.0, 200.0)
  t.frame()
  assert_true(!cui.attach)
  t.frame()
  // still going down, drawn over the field
  assert_true(t.find("文件") is Some(_))
  t.tap_text("发消息")
  let (active, _, _, _) = t.ime()
  assert_true(active)
  t.type_text("还在下去的时候")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "还在下去的时候")
  // the words sent wait for their row, which this core never gives; the composer's room let go after
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
}

///|
test "a quote's line for a comment, tapped while the capsule grows round it, takes the words" {
  // what the e2e caught: the line laid out above where the growing capsule was drawn yet, tapped there at once
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let (x, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  t.press_at(x, y)
  t.run_for(long_press_ms)
  t.release(x, y)
  t.tap_text("引用")
  t.frame()
  t.tap_text("添加说明（可选）")
  let (active, _, _, _) = t.ime()
  assert_true(active)
  t.type_text("长出来的时候点的")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  match field(Some(sent[0].params), "quotes") {
    Some(Array([q])) => assert_eq(text(Some(q), "comment"), "长出来的时候点的")
    _ => fail("no quote went")
  }
  // the words sent wait for their row, which this core never gives; the composer's room let go after
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
}

// What leaves is only drawn (docs/stillfail-motion.md, the rule): a sheet going down and its scrim fading, the bar
// going down under a page pushed. A tap meanwhile is what is under them's.

///|
/// A tap on `s` where it is drawn, and the frame after it, nothing settled.
fn tap_once_on(t : @ui.Tester, s : String) -> Unit {
  let (x, y) = t.find(s).unwrap()
  t.tap_once(x, y)
}

///|
test "the chat's sheet going down takes no tap: the field tapped through it is the field's" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  assert_true(t.find("复制会话链接") is Some(_))
  // the scrim, tapped: let go of
  t.tap_once(195.0, 60.0)
  t.frame()
  assert_true(dui.sheet is None)
  // still going down, drawn over the field
  assert_true(dui.leaving is Some(_))
  assert_true(t.find("复制会话链接") is Some(_))
  let (x, y, w, h) = t.rect_of("发消息").unwrap()
  t.tap_once(x + w / 2.0, y + h / 2.0)
  let (active, _, _, _) = t.ime()
  assert_true(active)
  // nothing of the sheet was tapped on the way
  assert_eq(named(calls, "chat.pin").length(), 0)
}

///|
test "the chat's sheet going down: its own rows take no tap, the scrim none" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  t.tap_once(195.0, 60.0)
  t.frame()
  tap_once_on(t, "固定到列表顶部")
  t.tap_once(195.0, 60.0)
  // sunk: on the sheet's spring, at most the window's height
  t.run_for(@motion.sheet_spring.duration(844.0, 0.0, 0.0))
  assert_eq(named(calls, "chat.pin").length(), 0)
  assert_true(dui.sheet is None && dui.leaving is None)
}

///|
test "the workspaces' sheet sinking takes no tap: the bar's 文件 tapped under it opens its page" {
  let t = tester("home")
  t.draw()
  t.tap_text("星火工作室")
  assert_true(sheet_open())
  t.tap_once(195.0, 60.0)
  t.frame()
  assert_true(!sheet_open())
  // sinking, drawn over the bar
  assert_true(sheet_host.shown != NoSheet)
  let (xs, y) = bar_places_at()
  t.tap_once(xs[1], y)
  assert_true(app.nav.top() == Files)
}

///|
test "a drive sheet going down takes no tap: its 重命名 tapped meanwhile does nothing" {
  let t = drive_tester("drive")
  // the drive pushed in over Home
  t.run_for(@ui.nav_push_ms)
  hold(t, "季度数据.csv")
  let log = t.drive("tap icon:more\nuntil 重命名\n")
  assert_true(log.contains("EXIT 0"))
  t.draw()
  t.tap_once(195.0, 60.0)
  t.frame()
  assert_true(t.find("重命名") is Some(_))
  tap_once_on(t, "重命名")
  // no rename sheet came
  assert_true(t.find("保存") is None)
}

///|
test "the bar going down under a page pushed takes no tap: the field tapped where it was is the field's" {
  let t = tester("home")
  t.draw()
  tap_once_on(t, "夜里的构建又失败了")
  // the chat half way in (its composer in the window), the bar still going down over it
  t.run_for(@ui.nav_push_ms / 2.0)
  assert_true(bar.vis.value > 0.01 && bar.vis.value < 0.5, msg="\{bar.vis.value}")
  let (x, y, w, h) = t.rect_of("发消息").unwrap()
  assert_true(y + h > 844.0 - 22.0 - 56.0)
  t.tap_once(x + w / 2.0, y + h / 2.0)
  let (active, _, _, _) = t.ime()
  assert_true(active)
}
