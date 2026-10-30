///|
/// The made-up chat open over Home (chat_fixture.mbt), from its start: pushed in.
fn chat_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat opens at its end: its bar, its last messages, the composer's room under them" {
  let t = chat_tester("chat")
  assert_true(t.find("整理发布清单") is Some(_))
  // its people in the bar lettered as it calls them: the viewer 「你」, not their name (Parts.kt PeopleStack)
  let bar = t.words().filter(fn(w) { w.2 < 100.0 }).map(fn(w) { w.0 })
  assert_true(bar.contains("你"))
  assert_true(!bar.contains("林"))
  let (_, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  // the last message over the composer's capsule
  let (_, field_y) = t.find("发消息").unwrap()
  assert_true(y < field_y && y > 500.0)
  assert_true(t.find("发消息") is Some(_))
  // an options card, a login card, a failing notice
  assert_true(t.find("一起换") is Some(_))
  assert_true(t.find("在 Studio 上登录 gh") is Some(_))
  assert_true(t.find("Studio 上 codex 的登录已失效") is Some(_))
  // no way to the newest at the newest
  assert_true(!readings.get("ws1/st1\u{1}s-c1").unwrap().jump)
  t.assert_idle()
}

///|
test "scrolled up, the way to the newest shows; tapped, the list glides back to its end" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -900.0)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(rd.jump)
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None)
  // it comes up growing (its presence, "chat-jump"): tapped once it is there, as a person can only tap what shows
  t.run_for(t.rest_of("chat-jump") - t.time())
  // over the send button, the composer's room under it
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  // back at its end by the list's own rest (mbui's list_to_end: a glide solved in time, or at once from further than
  // its rows; and its scroll bar faded): what it says of itself
  let rest = t.rest_of("a list")
  assert_true(rest < @double.infinity)
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  assert_true(!rd.jump)
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "the viewer's words on the right, everyone else's under their name" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  // a bubble at the list's right (16 in: the web's narrow chatList), an agent's words from its left
  let (bx, _, bw, _) = t.rect_of("还有深色模式也看一下").unwrap()
  assert_true(bx > 195.0 && bx + bw <= 390.0 - 16.0 + 0.5 && bx + bw > 390.0 - 16.0 - 24.0)
  let (ax, _, _, _) = t.rect_of("高度先按 90 估").unwrap()
  assert_eq(ax, 16.0)
}

///|
test "what the viewer quotes is over their bubble at the right, no wider than the bubble may be" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  // (the agent's words it quotes are in the chat too: the card's are after whose they are)
  let quote = t.words().filter(fn(w) { w.0.has_prefix("Claude") && w.0.contains("其余的行按估计的高度占位") })
  assert_eq(quote.length(), 1)
  let (_, qx, _, qw, _, _) = quote[0]
  let (bx, _, bw, _) = t.rect_of("这里的高度是怎么估的？").unwrap()
  // the card's words in from its start (11, its mark and 4 after it): the card starts no further left than the bubble
  // under it may (as wide as the composer sets what is typed, its sides round it), and both end there
  assert_true(qx - 26.0 >= 390.0 - 16.0 - (@sfpages.composer_words_width(390.0) + 2.0 * 14.0) - 0.5)
  assert_true(qx + qw <= 390.0 - 16.0 - 11.0 + 0.5)
  assert_true(bx + bw > 390.0 - 16.0 - 24.0)
}

///|
test "near the top the page before comes in, and what is in view stays where it is" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  // up to the first message: the page before is asked for there, and comes in above it
  let mut tries = 0
  while t.find("Studio 上的 claude 已启动") is None && tries < 40 {
    t.wheel(195.0, 400.0, -300.0)
    tries = tries + 1
  }
  let (_, y0) = t.find("Studio 上的 claude 已启动").unwrap()
  // from here on it moves by what is scrolled, never more (the pages coming in above do not push it)
  let mut y = y0
  for _ in 0..<3 {
    t.wheel(195.0, 400.0, -100.0)
    let (_, y1) = t.find("Studio 上的 claude 已启动").unwrap()
    assert_true(y1 - y <= 100.5)
    y = y1
  }
  t.wheel(195.0, 400.0, -300.0)
  assert_true(t.find("第 1 页之前的第 10 条") is Some(_) || t.find("第 2 页之前的第 10 条") is Some(_))
}

///|
test "a reference to another chat is its chip, and opens that chat" {
  let t = chat_tester("chat")
  let scrolled = scroll_run_clear(t, "首页的列表改成按天分组")
  assert_true(t.find("@首页的列表改成按天分组") is Some(_))
  t.tap_run("首页的列表改成按天分组")
  assert_eq(app.nav.depth(), 3)
  match app.nav.top() {
    Chat(r) => {
      assert_eq(r.station, "ws1/st1")
      assert_eq(r.session, "s-c2")
    }
    _ => fail("not a chat")
  }
  // the chat pushed in
  t.run_for(@ui.move_most_ms)
  // and the scroll bar of the list under it gone: shown since its last wheel, then faded out
  if scrolled >= 0.0 {
    t.run_for(scrolled + @ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms - t.time())
  }
  // (the pictures of the chat under it brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "while the chat is read: its bar, the messages to come, the composer" {
  let t = chat_tester("chat-loading")
  // (what it shows not come: it slid in once it had waited the most a page opening waits, App.kt LOCAL_MS)
  t.run_for(page_local_ms)
  assert_true(t.find("发消息") is Some(_))
  // its bar with the title it was opened by (its row's), none of its messages
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None)
}

///|
test "references and addresses in plain words" {
  let runs = message_runs("看 [首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 和 https://example.com/a。", @sf.theme().p.accent)
  assert_eq(runs.length(), 6)
  assert_eq(runs[1].text, "@")
  assert_eq(runs[2].text, "首页")
  assert_eq(runs[2].link, "https://app.still.fail/w/ws1/s/st1/chats/s-c2")
  assert_eq(runs[3].text, " 和 ")
  assert_eq(runs[4].link, "https://example.com/a")
  assert_eq(runs[5].text, "。")
}

///|
test "references in plain words: a still.fail link's, and one linked bare reading as its message says its chat" {
  let old = "https://app.still.fail/o/ws1/st1/c-old"
  let runs = message_runs(
    "[首页](https://app.still.fail/o/ws1/st1/s-c2) 和 \{old} 还有 https://app.still.fail/o/ws1/st1/c-none",
    @sf.theme().p.accent,
    chat_title=fn(h) { if h == old { Some("旧的对话") } else { None } },
  )
  assert_eq(runs.map(fn(r) { r.text }), ["@", "首页", " 和 ", "@", "旧的对话", " 还有 ", "@", "https://app.still.fail/o/ws1/st1/c-none"])
  assert_eq(runs[4].link, old)
}

///|
test "what was sent from here draws the composer's marks as the references its message will have" {
  let accent = @sf.theme().p.accent
  let sent = message_runs("看 @[首页] 吧", accent, marks=[(2, 7)])
  let theirs = message_runs("看 [首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 吧", accent)
  assert_eq(sent.map(fn(r) { r.text }), theirs.map(fn(r) { r.text }))
  assert_eq(sent.map(fn(r) { r.color }), theirs.map(fn(r) { r.color }))
  // (words like a mark that the field did not hold as one stay as written)
  assert_eq(message_runs("看 @[首页] 吧", accent).map(fn(r) { r.text }), ["看 @[首页] 吧"])
}

///|
test "images take their own proportions before they load" {
  let a : Attachment = {
    name: "a.png",
    path: "a.png",
    size: 0.0,
    width: 1170.0,
    height: 2532.0,
    thumbhash: "",
    owner: "",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  assert_eq(@sfpages.image_box(a, @sfpages.image_least), (139.0, 300.0, false))
  assert_eq(@sfpages.image_box({ ..a, width: 1600.0, height: 900.0 }, @sfpages.image_least), (360.0, 203.0, false))
  assert_eq(@sfpages.image_box({ ..a, width: 0.0, height: 0.0 }, @sfpages.image_least), (240.0, 160.0, false))
  assert_eq(elapsed(200000.0), "3m 20s")
}

///|
/// (Here, after the chat's own: a chat scrolled leaves the made-up chat as it is for the tests after it.)
test "a file card in the chat opens its preview" {
  reset()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (the chat opened drawn at its moment, its push from there)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.move(195.0, 400.0)
  // (up the list till its card shows: its name's stem, its extension after it)
  let mut tries = 0
  while t.find(".log") is None && tries < 12 {
    t.wheel(195.0, 400.0, -300.0)
    tries += 1
  }
  // (clear of the bar over the list's top)
  match t.find(".log") {
    Some((_, y)) if y < 200.0 => t.wheel(195.0, 400.0, y - 400.0)
    _ => ()
  }
  t.tap_text(".log")
  assert_true(viewer.get() is Some(_))
  assert_eq(viewer.get().unwrap().file.name, "build.log")
  // the preview flown open, and left alone a while: its bars there still (only a tap hides them)
  t.run_for(@ui.move_most_ms)
  t.run_for(left_alone_ms)
  assert_true(viewer.get().unwrap().bars_shown())
  t.assert_idle()
}

///|
test "what waits to be decided and is out of view: a bell over the way to the end; tapped, the first one's post" {
  let t = chat_tester("chat")
  t.draw()
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  // both cards in view at the end: no bell
  assert_true(!rd.ask)
  // dragged down (a finger's: no easing to wait for), the cards below what shows
  t.drag(195.0, 150.0, 195.0, 750.0)
  t.drag(195.0, 150.0, 195.0, 750.0)
  assert_true(rd.ask)
  assert_true(rd.jump)
  // over the way to the end, once it has risen (the list, still flung, is stopped by a tap first: it takes that one)
  t.run_for(ask_lift_ms)
  let bell = @sf.t("web-main.chat.asks.go")
  if t.list_moving() {
    t.click(Button, label=bell)
  }
  assert_true(!t.list_moving())
  t.click(Button, label=bell)
  assert_eq(rd.flash, "ts8")
  // the next tap goes to the next one's
  assert_eq(@sfpages.ask_turns.get("ws1/st1\u{1}s-c1"), Some(1))
}

///|
test "a chat opened with a card to decide in view: its first frame lays the card out as it rests, nothing read back of it" {
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // (pressed and let go between frames, one frame drawn: the one the chat opens in)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.frame()
  // its first frames, the page set out to slide in: the card as wide as where it is from there, not its room read
  // back from a frame before (none, as a chat opens: laid out none wide, the list again in the next frame)
  assert_true(!t.wanted_why().contains("read back moved"), msg=t.wanted_why())
  t.frame()
  assert_true(!t.wanted_why().contains("read back moved"), msg=t.wanted_why())
  let first = t.rect_of("先不换")
  t.run_for(@ui.move_most_ms)
  let rest = t.rect_of("先不换")
  assert_true(rest is Some(_), msg="the card in view at rest")
  assert_eq(first.map(fn(r) { (r.2, r.3) }), rest.map(fn(r) { (r.2, r.3) }))
}

///|
test "a chat opened with what waits to be decided in view: no bell from its first frame on" {
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("整理发布清单")
  let bell = @sf.t("web-main.chat.asks.go")
  // its first frame, the list not laid out yet: nothing known to be out of view
  assert_true(t.query(Button, label=bell) is None, msg="a bell at its first frame")
  t.run_for(@ui.move_most_ms / 2.0)
  assert_true(t.query(Button, label=bell) is None, msg="a bell as it slides in")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label=bell) is None, msg="a bell at rest")
}

///|
test "a chat's place: told the core as the list comes to rest (the message at the top, its top's pixels below the list's); opened again there, it is where it was left" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  // scrolled up from its end, let be
  t.drag(200.0, 300.0, 200.0, 300.0 + place_drag)
  // to where its fling says it comes to rest
  t.run_for(t.rest_of("a list") - t.time())
  t.frame()
  let told = named(calls, "chat.place")
  assert_true(told.length() > 0)
  let p = told[told.length() - 1].params
  let seq = number(Some(p), "seq")
  let px = number(Some(p), "offset")
  assert_true(seq > 0.0)
  // opened again where the core says it was left (its `at` and `atOffset`, as it was told), the same place told back
  let again : Array[Made] = []
  let t2 = fake_core(again, over=fn(name, tp) {
    match (name, tp.value) {
      ("chat", Some(Object(m))) => {
        let v = m.copy()
        v["at"] = Json::number(seq)
        v["atOffset"] = Json::number(px)
        { ..tp, value: Some(Json::object(v)) }
      }
      _ => tp
    }
  })
  t2.run_for(@ui.move_most_ms)
  let back = named(again, "chat.place")
  assert_true(back.length() > 0)
  let q = back[back.length() - 1].params
  assert_eq(number(Some(q), "seq"), seq)
  assert_true((number(Some(q), "offset") - px).abs() <= 1.0)
  ignore(t)
}

///|
/// How far the list is dragged down from its end.
let place_drag : Double = 300.0

///|
test "a long title has what is left beside what follows it, which keeps its own width (Chat.kt BarFrame)" {
  reset()
  let t = @ui.Tester::new(
    fn(c) {
      bar_frame(
        c,
        "端到端测试的对话 post:你好，我是测试用的 agent",
        fn() { c.box(w=Px(60.0), fn() { c.text("尾", size=12.0, wrap=false) |> ignore }) |> ignore },
        fn() {  },
        true,
      )
    },
    w=390.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  let (tx, _, tw, _) = t.rect_of("端到端").unwrap()
  let (ax, _, _, _) = t.rect_of("尾").unwrap()
  // 390 - 16 (its end) - 34 (…) and the room before it (bar_keys_apart) - 8, the box of 60: what follows starts where
  // it would with a short title
  assert_eq(ax, 390.0 - 16.0 - 34.0 - bar_keys_apart() - 8.0 - 60.0)
  // the title cut to what is left, 8 before it
  assert_true(tx + tw <= ax - 8.0 + 0.5)
  assert_true(t.lines_of("端到端")[0].has_suffix("…"))
}

///|
test "a chat left lets go of all that holds its thread at the core: its view and its jobs (Chat.kt's rememberTopic)" {
  reset()
  let base = fixture("chat")
  let left : Array[(String, String)] = []
  let src : Source = {
    ..base,
    leave: fn(name, params) { left.push((name, Json::object(params).stringify())) },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(left, [])
  t.back()
  t.run_for(@ui.move_most_ms)
  let held = Json::object(chat_params(r)).stringify()
  // (else the core keeps the thread's window as first read: the chat opened again where it was first opened, not
  // where it was left)
  assert_true(left.contains(("chat", held)))
  assert_true(left.contains(("chatJobs", held)))
}

///|
test "left short of its end, a chat opens again where it was left, though the core still says where it first opened (Chat.kt kept)" {
  reset()
  let base = fixture("chat")
  let place : Ref[Map[String, Json]?] = Ref(None)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "chat.place" {
        match params {
          Object(p) => place.val = Some(p)
          _ => ()
        }
      }
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  open_chat(r)
  t.run_for(@ui.move_most_ms)
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -900.0)
  t.run_for(@ui.move_most_ms)
  let k = "ws1/st1\u{1}s-c1"
  let left_at = readings.get(k).unwrap().top_seq
  let left_off = readings.get(k).unwrap().top_off
  assert_true(left_at > 0.0 && !readings.get(k).unwrap().at_end)
  t.back()
  t.run_for(@ui.move_most_ms)
  // told where it was left
  assert_eq(place.val.map(fn(p) { p.get("seq") }), Some(Some(Json::number(left_at))))
  open_chat(r)
  t.run_for(@ui.move_most_ms)
  // opened there, not at its end where the core's view, kept a minute after the page left it, still opens it
  assert_eq(readings.get(k).unwrap().top_seq, left_at)
  assert_true((readings.get(k).unwrap().top_off - left_off).abs() < 0.5)
  assert_true(!readings.get(k).unwrap().at_end)
}

///|
/// The last `client.focus {chat}` of `calls`: whether its end shows, and the newest message it said was seen whole
/// (-1 none).
fn focus_seen(calls : Array[Made]) -> (Bool, Double) {
  let told = named(calls, "client.focus").filter(fn(m) { field(Some(m.params), "chat") is Some(Object(_)) })
  match told.last() {
    Some(m) => {
      let chat = field(Some(m.params), "chat")
      (
        field(chat, "end") == Some(Json::boolean(true)),
        match field(chat, "seen") {
          Some(Number(n, ..)) => n
          _ => -1.0
        },
      )
    }
    None => (false, -1.0)
  }
}

///|
/// How far the list is dragged down from its end to leave its last message short of whole.
let seen_drag : Double = 160.0

///|
test "opened short of its end, the core is told the messages shown whole: read up to there, the end not seen" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  // at its end: the end seen, and its newest shown whole
  let (end, newest) = focus_seen(calls)
  assert_true(end)
  assert_true(newest > 0.0)
  // scrolled up from its end, let be: the place it is at
  t.drag(200.0, 300.0, 200.0, 300.0 + seen_drag)
  t.run_for(t.rest_of("a list") - t.time())
  t.frame()
  let told = named(calls, "chat.place")
  let p = told[told.length() - 1].params
  let seq = number(Some(p), "seq")
  let px = number(Some(p), "offset")
  // opened again there (the core's `at`): the messages in view shown whole, the end not
  let again : Array[Made] = []
  let t2 = fake_core(again, over=fn(name, tp) {
    match (name, tp.value) {
      ("chat", Some(Object(m))) => {
        let v = m.copy()
        v["at"] = Json::number(seq)
        v["atOffset"] = Json::number(px)
        { ..tp, value: Some(Json::object(v)) }
      }
      _ => tp
    }
  })
  t2.run_for(@ui.move_most_ms)
  let (end2, seen) = focus_seen(again)
  assert_true(!end2)
  assert_true(seen >= 0.0)
  assert_true(seen < newest)
  ignore(t)
}

///|
test "a table wider than the message on a phone: at rest in line with the words, slid sideways out to the screen's edge" {
  let t = chat_tester("chat-md")
  let cell = "只排可见的行"
  let (x, y) = t.drawn_of(cell).unwrap()
  // at rest in line with the words (the list's 16 in), past the card's room before its cells (4) and the cell's 12
  assert_eq(x, 16.0 + 4.0 + 12.0)
  // slid to its end, held still before it is let go (no fling)
  t.press_at(360.0, y)
  for step in 1..=8 {
    t.move(360.0 - step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(40.0, y)
  // what went left shows out to the screen's edge, not cut at the words' margin
  let (shown, _, _, _) = t.shown_of(cell).unwrap()
  assert_eq(shown, 0.0)
}

///|
test "a table on a wide list, slid sideways: out over the margin, not cut at the words' column" {
  reset()
  let src = fixture("chat-md")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (a window whose list is wide, its table wider than its words with its key past it)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=760.0, h=800.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let cell = "只排可见的行"
  let (x, y) = t.drawn_of(cell).unwrap()
  // the words' column: the card's room before its cells (4) and the cell's 12 before the cell
  let column = x - 4.0 - 12.0
  t.press_at(x + 300.0, y)
  for step in 1..=8 {
    t.move(x + 300.0 - step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(x - 20.0, y)
  let (shown, _, _, _) = t.shown_of(cell).unwrap()
  assert_true(shown < column, msg="\{(shown, column)}")
}

///|
/// How soon after a chat is shown a message is said in it (the test's).
let said_soon_ms : Double = 100.0

///|
test "a message said just after the chat opened comes in with the list gliding after it: no half second first" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // a moment on (well within the half second the list once waited), someone says something in it (said while it
  // shows: new to the list)
  let words = "我也在看这个"
  fix_later(1.0, fn() {
    fix_chat("s-c1").sent.push(
      msg(150, "person", by_person("安娜"), words, "刚刚", { "ts": Json::string("ana150"), "said": true }),
    )
  })
  t.run_for(said_soon_ms)
  clock.val = clock.val + 1.0
  t.draw()
  let mut from : Double? = None
  let mut n = 0
  while from is None && n < 60 {
    t.frame()
    from = t.drawn_of(words).map(fn(d) { d.1 })
    n += 1
  }
  guard from is Some(y0) else { fail("「\{words}」 never came in") }
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  t.run_for(@sf.enter_ms)
  let (_, y1) = t.drawn_of(words).unwrap()
  // (more than its rise in: the list went up after it)
  assert_true(y0 - y1 > 20.0, msg="glided up after it: \{y0} → \{y1}")
  fix_clock.val = None
}

///|
test "what was said while the app was away, brought after its chat opened at its end: read from its unread line" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // a moment on, three come at once, more than a screen of them, said before it opened: caught up on, the unread line
  // over the first (the core's, attend.ts)
  let first = "这份清单在每次发布前过一遍"
  fix_later(said_soon_ms, fn() {
    let fc = fix_chat("s-c1")
    fc.sent.push(msg(150, "person", by_person("安娜"), fixture_markdown(), "刚刚", { "ts": Json::string("ana150") }))
    fc.sent.push(msg(151, "person", by_person("安娜"), long_reply, "刚刚", { "ts": Json::string("ana151") }))
    fc.sent.push(msg(152, "person", by_person("安娜"), long_reply, "刚刚", { "ts": Json::string("ana152") }))
    fc.line.val = 150
  })
  clock.val = said_soon_ms
  t.draw()
  t.run_for(@ui.move_most_ms)
  // the first of them from its top, under the line: not the list at the end of the newest
  guard t.drawn_of(first) is Some((_, y)) else { fail("the first of what came is not in view") }
  assert_true(y > bar_foot() && y < 844.0 / 2.0, msg="the first of what came, from its top: at \{y}")
  fix_clock.val = None
}

///|
test "a login card in a chat on a phone: as tall as what it holds, the next message right under it" {
  let t = chat_tester("chat-login")
  t.frame()
  let (_, by, _, bh) = t.rect_of("在浏览器里登录").unwrap()
  let (_, ny, _, _) = t.rect_of("5 分钟前").unwrap()
  assert_true(ny - (by + bh) < 60.0, msg="room between the card's key and the next message: \{ny - (by + bh)}")
}
