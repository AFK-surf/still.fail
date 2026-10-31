// still.fail's motion over its made-up chats, frame by frame (docs/motion.md): Home's rows as the list
// changes, words sent flying into their bubble, the way to the newest coming and going.

///|
test "Home: a chat with news goes to the top: it closes where it was and opens there, never across the rows it passes" {
  // (the clock set after reset, which puts the fixture's own back)
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("home-motion")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let (_, y_top) = t.drawn_of("整理发布清单").unwrap()
  // its news comes (the fixture's first step)
  clock.val = 2001.0
  t.frame()
  // half way: the first row, pushed down a row as the room at the top opens, on its way there; the chat with news
  // coming there where it is (as far shown as its room is open), and leaving where it was (2026-10-31 the user:
  // 「原地缩下去再从目标点挤出来更合理」)
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, f1) = t.drawn_of("整理发布清单").unwrap()
  assert_true(f1 > y_top && f1 < y_top + 66.0, msg="\{f1} \{y_top}")
  let ci = t.words().filter(fn(w) { w.0 == "盯着 CI，绿了告诉我" })
  assert_eq(ci.length(), 2)
  for w in ci {
    assert_true(w.5 < 1.0, msg="\{w}")
  }
  // its room open, the copy where it was gone
  t.run_for(@ui.row_size_ms)
  let ci = t.words().filter(fn(w) { w.0 == "盯着 CI，绿了告诉我" })
  assert_eq(ci.length(), 1)
  assert_true((ci[0].2 - y_top).abs() < 0.5, msg="\{ci[0]} \{y_top}")
  let (_, f2) = t.drawn_of("整理发布清单").unwrap()
  assert_true((f2 - y_top - 66.0).abs() < 0.5)
  fix_clock.val = None
}

///|
/// Whether a row of Home's list moves now: its place, its coming in, its passing over others, a copy of one gone.
fn home_moving(t : @ui.Tester) -> Array[String] {
  t.moving().filter(fn(m) { m.contains("a row lifted") || (m.contains("chats/") && m.contains("\u{1}")) })
}

///|
test "Home: back from a chat to the list changed meanwhile, the list drawn as it is: nothing in it moves" {
  // (Home.kt: the list composed anew as it is come back to, its ListMotion new: nothing moves the first time)
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("home-motion")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.tap_text("整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("搜索全部内容") is None)
  // while the chat shows: news in 盯着 CI, which goes to the top; a new chat
  clock.val = 3601.0
  t.frame()
  t.back()
  let end = t.time() + @ui.move_most_ms + 600.0
  while t.time() < end {
    assert_eq(home_moving(t), [])
    for words in ["盯着 CI，绿了告诉我", "看一下新的崩溃报告", "整理发布清单"] {
      let (_, y, _, _) = t.rect_of(words).unwrap()
      let (_, dy) = t.drawn_of(words).unwrap()
      assert_true((dy - y).abs() < 0.5, msg="\{words}: drawn at \{dy}, laid out at \{y}")
    }
    t.frame()
  }
  fix_clock.val = None
}

///|
test "Home: a new chat its station makes keeps its row (its clientKey): it neither leaves nor comes in" {
  new_run()
  let made = Ref::new(false)
  let base = fixture("home")
  let src = {
    ..base,
    topic: fn(name, params) {
      let tv = (base.topic)(name, params)
      match (name, tv.value) {
        ("chats", Some(Object(v))) => {
          let row : Map[String, Json] = {
            "id": Json::string(if made.val { "c20" } else { "k-20" }),
            "clientKey": "k-20",
            "session": Json::string(if made.val { "s-c20" } else { "k-20" }),
            "title": "新会话的第一句",
            "agents": [],
            "unread": false,
            "mine": true,
            "lastActiveAt": 0,
            "station": "ws1/st1",
            "stationName": "Studio",
          }
          if !made.val {
            row["pending"] = Json::boolean(true)
          }
          let days = match v.get("days") {
            Some(Array(d)) => d.copy()
            _ => []
          }
          let first = match days[0] {
            Object(d) => d
            _ => abort("no day")
          }
          let rows = match first.get("items") {
            Some(Array(r)) => r.copy()
            _ => []
          }
          rows.insert(0, Json::object(row))
          let day = first.copy()
          day["items"] = Json::array(rows)
          days[0] = Json::object(day)
          let out = v.copy()
          out["days"] = Json::array(days)
          { value: Some(Json::object(out)), error: tv.error, version: tv.version * 2 + (if made.val { 1 } else { 0 }) }
        }
        _ => tv
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  assert_true(t.find("新会话的第一句") is Some(_))
  made.val = true
  // (the frame the list changes in: a row leaving or coming would be set going there)
  t.frame()
  assert_eq(home_moving(t), [])
  assert_true(t.find("新会话的第一句") is Some(_))
}

///|
test "Home: a row swiped off is archived once it has gone, and leaves no copy of it behind" {
  let t = tester("home")
  t.scroll_to(12)
  t.draw()
  let (x, y, _, h) = t.rect_of("把旧的截图都换成新的").unwrap()
  ignore(x)
  t.drag(300.0, y + h / 2.0, 300.0 - 390.0 * 0.6, y + h / 2.0, steps=12)
  // going off: not archived yet
  t.run_for(@ui.move_most_ms / 2.0)
  assert_true(t.find("把旧的截图都换成新的") is Some(_))
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(t.locate("=把旧的截图都换成新的").is_empty())
  // gone with no copy fading where it was; the rows under it close over the room
  assert_true(t.moving().iter().all(fn(m) { !m.contains("c8 leaving") }), msg="\{t.moving()}")
}

///|
test "words sent fly from the field into their bubble" {
  // the fixture's own station takes what is sent: the outbox at once, the message after
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
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
  fix_clock.val = None
}

///|
test "words sent: the composer stays as it was while they are in it, and comes down as they let go of it, not from under them" {
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("第一行\n第二行\n第三行")
  // (its box grown to the three lines)
  t.run_for(@ui.move_most_ms)
  let box = fn() { @motion.measured(t.ctx(), "composer/content").unwrap() }
  let reshaping = fn() { t.moving().iter().any(fn(m) { m.contains("layout composer/") }) }
  let tall = box()
  let room = @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1")
  tap_send(t)
  t.frame()
  // sent, its words on their way: the composer as tall as it was, nothing in it moving (its field emptied where it
  // was, its ＋ and send where they were), the list's room under its last row as it was
  assert_true(flight_of("ws1/st1:s-c1") is Some(f) && f.placed)
  assert_eq(box(), tall)
  assert_true(!reshaping(), msg="\{t.moving()}")
  assert_eq(@sfpages.composer_room(t.ctx(), "ws1/st1:s-c1"), room)
  // let go of once the words are on their way: it comes down from as tall as it was, its field with it
  let go = t.rest_of("composer/held-box/")
  assert_true(go > t.time() && go < @double.infinity, msg="\{go} \{t.time()}")
  t.run_for(go - t.time())
  assert_true(
    flight_of("ws1/st1:s-c1") is Some(f) && flight_p(t.ctx(), f) > 0.0,
    msg="the words not yet on their way",
  )
  assert_true(box() < tall, msg="\{box()} \{tall}")
  assert_true(reshaping(), msg="\{t.moving()}")
  // and its room under the list down with it, on the same curve
  t.run_for(t.rest_of("composer/hold/") - t.time())
  assert_true(@sfpages.composer_room(t.ctx(), "ws1/st1:s-c1") < room)
  fix_clock.val = None
}

///|
test "words sent set out from where they were typed and land where their message has them, set alike all the way" {
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  let words = "第一行\n第二行\n第三行"
  t.type_text(words)
  t.run_for(@ui.move_most_ms)
  tap_send(t)
  t.frame()
  // as they set out: a piece a line, each drawn where it was in the field (a copy of the message's words, cut to it)
  let f = flight_of("ws1/st1:s-c1").unwrap()
  let typed = f.lines.unwrap()
  let (pieces, laid) = @sfbase.flight_pieces(t.ctx(), f).unwrap()
  assert_eq(pieces.length(), 3)
  // set alike: the field's lines as high as the message's
  assert_eq(typed.line_h(), laid.layout.line_h[0])
  let copies = t.words().filter(fn(w) { w.0 == words && w.5 > 0.99 })
  for p in pieces {
    let (fx, fy) = typed.place(f.lead + p.a)
    assert_true(
      copies.iter().any(fn(w) { (w.1 + p.at.0 - fx).abs() < 0.5 && (w.2 + p.at.1 - fy).abs() < 0.5 }),
      msg="\{p.a}: \{fx},\{fy} \{copies}",
    )
  }
  // landed: the message's own words where it has them, nothing else of them drawn
  t.run_for(f.way.ends() - t.time())
  t.frame()
  assert_true(flight_of("ws1/st1:s-c1") is None)
  let drawn = t.words().filter(fn(w) { w.0 == words && w.5 > 0.01 })
  assert_eq(drawn.length(), 1, msg="\{drawn}")
  fix_clock.val = None
}

///|
test "words sent break their lines in their message where the composer broke them: a paragraph goes a line a piece" {
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("帮我看一下登录按钮在深色模式下的颜色是不是不对，还有注册页输入框的边框也要再核对一遍")
  t.run_for(@ui.move_most_ms)
  tap_send(t)
  t.frame()
  let f = flight_of("ws1/st1:s-c1").unwrap()
  let typed = f.lines.unwrap()
  // more than a line in the field, and as many in the message, each its own piece
  assert_true(typed.starts.length() > 1)
  let (pieces, laid) = @sfbase.flight_pieces(t.ctx(), f).unwrap()
  assert_eq(laid.layout.line_count(), typed.starts.length())
  assert_eq(pieces.length(), typed.starts.length())
  fix_clock.val = None
}

///|
test "Home: the first rows, after the list waited, come as they are and a tap on one opens it at once" {
  new_run()
  let src = fixture("home")
  let waiting = Ref::new(true)
  let src = {
    ..src,
    topic: fn(name, params) {
      // (made up as it is read: followed by its version, as the core's by what it says)
      topic_as_read(name, params, if name == "chats" && waiting.val {
        { value: None, error: None, version: 0 }
      } else {
        (src.topic)(name, params)
      })
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
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
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

// What leaves is only drawn (docs/motion.md): a sheet going down and its scrim fading, the bar
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
  assert_true(!@sf.presenting())
  // still going down, drawn over the field
  assert_true(@sf.presented_drawn())
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
  assert_true(!@sf.presenting() && !@sf.presented_drawn())
}

///|
test "the workspaces' sheet sinking takes no tap: the bar's 文件 tapped under it opens its page" {
  let t = tester("home")
  t.tap_text("星火工作室")
  assert_true(@sf.presenting())
  t.tap_once(195.0, 60.0)
  t.frame()
  assert_true(!@sf.presenting())
  // sinking, drawn over the bar
  assert_true(@sf.presented_drawn())
  let (xs, y) = bar_places_at()
  t.tap_once(xs[1], y)
  assert_true(app.nav.top() == Files)
}

///|
test "a row's sheet going down takes no tap: its 重命名 tapped meanwhile does nothing" {
  let t = drive_tester("drive")
  // the drive pushed in over Home
  t.run_for(@ui.move_most_ms)
  // held: what can be done to it, a sheet from the foot
  hold(t, "季度数据.csv")
  assert_true(t.find("重命名") is Some(_))
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
  tap_once_on(t, "夜里的构建又失败了")
  // the chat half way in (its composer in the window: a page's Move across the phone), the bar still going down over it
  t.run_for(phone_page_ms / 2.0)
  assert_true(bar.vis.value > 0.01 && bar.vis.value < 0.5, msg="\{bar.vis.value}")
  let (x, y, w, h) = t.rect_of("发消息").unwrap()
  assert_true(y + h > 844.0 - 22.0 - 56.0)
  t.tap_once(x + w / 2.0, y + h / 2.0)
  let (active, _, _, _) = t.ime()
  assert_true(active)
}
