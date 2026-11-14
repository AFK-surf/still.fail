///|
/// The made-up chat open over Home (chat_fixture.mbt), from its start: pushed in.
fn chat_tester(mode : String, w? : Double = 390.0) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat opens at its end: its bar, its last messages, the composer's room under them" {
  let t = chat_tester("chat")
  assert_true(t.find("整理发布清单") is Some(_))
  // (what the bar shows: its words seen, not those its row left out for the title and its agent)
  let bar = fn(t : @ui.Tester) { t.words().filter(fn(w) { w.2 < 100.0 && w.5 > 0.0 }).map(fn(w) { w.0 }) }
  assert_true(bar(t).contains("你"), msg="its people with the room: \{Repr(bar(t))}")
  assert_true(!bar(t).contains("林"), msg="lettered as it calls them: \{Repr(bar(t))}")
  let (_, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  // the last message over the composer's capsule
  let (_, field_y) = t.find("发消息").unwrap()
  assert_true(y < field_y && y > 500.0)
  assert_true(t.find("发消息") is Some(_))
  // an options card, a login card, a failing notice
  assert_true(t.find("一起换") is Some(_))
  assert_true(t.find("在 Willow 上登录 gh") is Some(_))
  assert_true(t.find("Willow 上 codex 的登录已失效") is Some(_))
  // no way to the newest at the newest
  assert_true(!readings.get("ws1/st1\u{1}s-c1").unwrap().jump)
  t.assert_idle()
  // its people left out for its title where the bar is narrower
  let narrow = chat_tester("chat", w=350.0)
  assert_true(!bar(narrow).contains("你") && !bar(narrow).contains("林"), msg="its people left out for its title: \{Repr(bar(narrow))}")
}

///|
test "scrolled up, the way to the newest shows; tapped, the list glides back to its end" {
  let t = chat_tester("chat")
  t.move_to(195.0, 400.0)
  t.wheel(195.0, 400.0, -900.0)
  let jumps = fn(t : @ui.Tester) {
    t.semantics().iter().any(fn(s) { s.role == Button && s.label == @sf.t("web-main.chat.toLatest") })
  }
  assert_true(jumps(t))
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None)
  // it comes up growing: tapped once it is there, as a person can only tap what shows
  t.run_for(@ui.move_most_ms)
  // over the send button, the composer's room under it
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  // back at its end by the list's own rest (mbui's list_to_end: a glide solved in time, or at once from further than
  // its rows; and its scroll bar faded): what it says of itself
  let rest = t.rest_of("a list")
  assert_true(rest < @double.infinity)
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  assert_true(!jumps(t))
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
/// (the way to the newest's glide is this file's motion, counted here: motion_counted_wbtest.mbt; not judged in
/// chat_find_wbtest, where the outline's go-to and its place kept are)
test "a go-to in the chat keeps where the reader was: ↓ back there, ↓ again to the end, the place forgotten; reaching the end, or words sent, forget it" {
  // (the Tester made here, this file's: the long chat of the outline's modes, away from its end at 22)
  let outline_tester = fn(calls : Array[Made]) {
    new_run()
    let base = fixture("chat-outline-away")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        calls.push({ name, params, bytes: None, done })
        (base.call)(name, params, done)
      },
    }
    open_fixture_over("chat-outline-away", src)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    t
  }
  let back = fn(t : @ui.Tester) { t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" }) }
  // ↓ back, then ↓ again: at the end, nothing kept; a go-to from there keeps nothing
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(back(t))
  t.click(Button, label="回到刚才的位置")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_false(back(t))
  t.click(Button, label="跳到最新")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_reading().at_end)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_false(back(t))
  // a place kept, then the end reached by ↓ without going back: forgotten
  let t = outline_tester(calls)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(back(t))
  t.wheel(800.0, 400.0, 100000.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_reading().at_end)
  assert_false(back(t))
  // a place kept, then words sent: forgotten
  let t = outline_tester(calls)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(back(t))
  t.tap_text("发消息")
  t.type_text("好的")
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(named(calls, "composer.take").length() + named(calls, "chat.send").length() > 0)
  assert_false(back(t))
}

///|
test "the viewer's words on the right, everyone else's under their name" {
  let t = chat_tester("chat")
  t.move_to(195.0, 400.0)
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
  t.move_to(195.0, 400.0)
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
  t.move_to(195.0, 400.0)
  // up to the first message: the page before is asked for there, and comes in above it
  let mut tries = 0
  while t.find("Willow 上的 claude 已启动") is None && tries < 40 {
    t.wheel(195.0, 400.0, -300.0)
    tries = tries + 1
  }
  let (_, y0) = t.find("Willow 上的 claude 已启动").unwrap()
  // from here on it moves by what is scrolled, never more (the pages coming in above do not push it)
  let mut y = y0
  for _ in 0..<3 {
    t.wheel(195.0, 400.0, -100.0)
    let (_, y1) = t.find("Willow 上的 claude 已启动").unwrap()
    assert_true(y1 - y <= 100.5)
    y = y1
  }
  t.wheel(195.0, 400.0, -300.0)
  assert_true(t.find("第 1 页之前的第 10 条") is Some(_) || t.find("第 2 页之前的第 10 条") is Some(_))
}

///|
test "a chat whose latest page is all letters to other chats: the page before comes in, and it is never said to be empty" {
  // (the user, 2026-10-31: a chat its agents had written other chats a page of letters in showed a spinner for good,
  // over 在此发送消息…, its messages never coming)
  reset()
  let src = fixture("chat-letters")
  let empty = @sf.t("web-main.chat.empty")
  let said_empty = Ref(false)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.each_frame(Some(fn() { if t.find(empty) is Some(_) { said_empty.val = true } }))
  t.run_for(@ui.move_most_ms)
  t.each_frame(None)
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  assert_true(!said_empty.val)
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
  // (what it shows not come: it slid in once it had waited the most a page opening waits, page_local_ms)
  t.run_for(page_local_ms)
  assert_true(t.find("发消息") is Some(_))
  // its bar with the title it was opened by (its row's), none of its messages
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None)
}

///|
test "a person's words as the core gives them in runs: references to chats, one linked bare reading as its chat's title" {
  let accent = @sf.theme().p.accent
  let page = "https://app.still.fail/w/ws1/s/st1/chats/s-c2"
  let old = "https://app.still.fail/o/ws1/st1/c-old"
  let title = fn(h) { if h == old { Some("旧的对话") } else { None } }
  // (refLinks.ts personWords of `看 [首页](page) 和 https://example.com/a 还有 old`, as the core gives them)
  let parts : Array[Json] = [
    { "text": "看 " },
    { "text": "首页", "link": Json::string(page), "ref": true },
    { "text": " 和 " },
    { "text": "https://example.com/a", "link": "https://example.com/a" },
    { "text": " 还有 " },
    { "text": Json::string(old), "link": Json::string(old), "ref": true },
  ]
  let runs = words_runs(parts, accent, chat_title=title)
  assert_eq(runs.map(fn(r) { r.text }), ["看 ", "@", "首页", " 和 ", "https://example.com/a", " 还有 ", "@", "旧的对话"])
  assert_eq(runs[2].link, page)
  assert_eq(runs[2].color, accent)
  assert_eq(runs[4].link, "https://example.com/a")
  assert_eq(runs[7].link, old)
}

///|
test "what was sent from here draws the composer's marks as the references its message will have" {
  let accent = @sf.theme().p.accent
  // (draftWords of `看 @[首页] 吧`, and personWords of the words the core sends for it)
  let sent = words_runs([{ "text": "看 " }, { "text": "首页", "ref": true }, { "text": " 吧" }], accent)
  let theirs = words_runs(
    [{ "text": "看 " }, { "text": "首页", "link": "https://app.still.fail/w/ws1/s/st1/chats/s-c2", "ref": true }, { "text": " 吧" }],
    accent,
  )
  assert_eq(sent.map(fn(r) { (r.text, r.color) }), theirs.map(fn(r) { (r.text, r.color) }))
}

///|
test "images are sized before they load" {
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
  let box = fn(a : Attachment) {
    @sfpages.image_box(a, @sfpages.image_least, min_side=@sfpages.image_min_side)
  }
  assert_eq(box(a), (160.0, 300.0, false))
  assert_eq(box({ ..a, width: 1600.0, height: 900.0 }), (360.0, 203.0, false))
  assert_eq(box({ ..a, width: 0.0, height: 0.0 }), (240.0, 160.0, false))
  assert_eq(elapsed(200000.0), "3m 20s")
}

///|
/// (Here, after the chat's own: a chat scrolled leaves the made-up chat as it is for the tests after it.)
test "a file card in the chat opens its preview" {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  // (the chat opened drawn at its moment, its push from there)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.move_to(195.0, 400.0)
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
  let shows = fn(t : @ui.Tester, label : String) {
    t.semantics().iter().any(fn(s) { s.role == Button && s.label == label })
  }
  let bell = @sf.t("web-main.chat.asks.go")
  // both cards in view at the end: no bell
  assert_true(!shows(t, bell))
  // dragged down (a finger's: no easing to wait for), the cards below what shows
  t.drag(195.0, 150.0, 195.0, 750.0)
  t.drag(195.0, 150.0, 195.0, 750.0)
  assert_true(shows(t, bell))
  assert_true(shows(t, @sf.t("web-main.chat.toLatest")))
  // over the way to the end, once it has risen (the list, still flung, is stopped by a tap first: it takes that one)
  t.run_for(ask_lift_ms)
  let k = "ws1/st1\u{1}s-c1"
  t.click(Button, label=bell)
  // (the list, still flung, stopped by that tap where it takes it: the next one the bell's)
  if @sfpages.ask_turns.get(k) is None {
    t.click(Button, label=bell)
  }
  // (its post lit as it is gone to, from the middle of its hold)
  t.run_for((flash_in_ms + flash_held_ms) / 2.0)
  assert_true(lit_over(t, "高度先按 90 估") > 0.99)
  // the next tap goes to the next one's
  assert_eq(@sfpages.ask_turns.get(k), Some(1))
}

///|
test "a chat opened with a card to decide in view: its first frame lays the card out as it rests, nothing read back of it" {
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
test "words sent going up into the list tell the core where it is as the message at the top changes, not each frame" {
  // (each frame of their way up told the core where the chat was, and it wrote it down: 20 calls a send, 2026-11-08)
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  let calls : Array[Made] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  t.run_for(fix_answer_ms)
  fix_clock_set(clock, clock.val + fix_answer_ms)
  t.draw()
  t.run_for(Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() + Pose::Return.ms() + 2.0 * @ui.frame_period_default)
  assert_true(t.find("收到：「测试一下」") is Some(_))
  // told as the message at the top changed, not as it moved under it
  let told = named(calls, "chat.place").map(fn(m) { field(Some(m.params), "seq") })
  assert_true(told.length() > 0)
  for i in 1..<told.length() {
    assert_true(told[i] != told[i - 1], msg="told again with the same message at the top: \{Repr(told)}")
  }
  fix_clock.val = None
}

///|
/// How far the list is dragged down from its end.
let place_drag : Double = 300.0

///|
test "a long title has what is left beside what follows it, which keeps its own width (Chat.kt BarFrame)" {
  new_run()
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
  // 390 - 16 (its end) - 34 (…) and the room before it (bar_keys_apart) - 34 (ⓘ) and its room - 8, the box of 60: what
  // follows starts where it would with a short title
  assert_eq(ax, 390.0 - 16.0 - 34.0 - bar_keys_apart() - 34.0 - bar_keys_apart() - 8.0 - 60.0)
  // the title cut to what is left, 8 before it
  assert_true(tx + tw <= ax - 8.0 + 0.5)
  assert_true(t.lines_of("端到端")[0].has_suffix("…"))
}

///|
test "a chat left lets go of all that holds its thread at the core: its view and its jobs (Chat.kt's rememberTopic)" {
  new_run()
  let base = fixture("chat")
  let asked : Array[(String, String)] = []
  let left : Array[(String, String)] = []
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      asked.push((name, Json::object(params).stringify()))
      base.topic(name, params).get().snapshot()
    },
    leave: fn(name, params, __reason) {
      left.push((name, Json::object(params).stringify()))
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop() }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(left, [])
  let summary = chat_params(r)
  summary["summary"] = Json::boolean(true)
  let summary_key = Json::object(summary).stringify()
  assert_true(asked.contains(("chatJobs", summary_key)), msg="the bar reads only its jobs summary")
  assert_false(asked.contains(("chatJobs", Json::object(chat_params(r)).stringify())), msg="the unopened jobs page is not read")
  t.back()
  t.run_for(@ui.move_most_ms)
  let held = Json::object(chat_params(r)).stringify()
  // (else the core keeps the thread's window as first read: the chat opened again where it was first opened, not
  // where it was left)
  assert_true(left.contains(("chat", held)))
  assert_true(left.contains(("chatJobs", held)))
  assert_true(left.contains(("chatJobs", summary_key)))
}

///|
test "left short of its end, a chat opens again where it was left, though the core still says where it first opened (Chat.kt kept)" {
  new_run()
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
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.draw()
  open_chat(r)
  t.run_for(@ui.move_most_ms)
  t.move_to(195.0, 400.0)
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
  // at rest in line with the words (the list's 16 in: no card, no room before its first column's words)
  assert_eq(x, 16.0)
  // slid to its end, held still before it is let go (no fling)
  t.press_at(360.0, y)
  for step in 1..=8 {
    t.move_to(360.0 - step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(40.0, y)
  // what went left shows out to the screen's edge, not cut at the words' margin
  let (shown, _, _, _) = t.shown_of(cell).unwrap()
  assert_eq(shown, 0.0)
}

///|
test "a table on a wide list, slid sideways: out over the margin, not cut at the words' column" {
  new_run()
  let src = fixture("chat-md")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  // (a window whose list is wide, its table wider than its words with its key past it)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=760.0, h=800.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let cell = "只排可见的行"
  let (x, y) = t.drawn_of(cell).unwrap()
  // the words' column: the card's room before its cells (4) and the cell's 12 before the cell
  let column = x - 4.0 - 12.0
  t.press_at(x + 300.0, y)
  for step in 1..=8 {
    t.move_to(x + 300.0 - step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(x - 20.0, y)
  let (shown, _, _, _) = t.shown_of(cell).unwrap()
  assert_true(shown < column, msg="\{Repr((shown, column))}")
}

///|
/// How soon after a chat is shown a message is said in it (the test's).
let said_soon_ms : Double = 100.0

///|
test "a message said just after the chat opened comes in with the list gliding after it: no half second first" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
  fix_clock_set(clock, clock.val + 1.0)
  t.draw()
  // (what is over it: the card of the newest message before it, where it is drawn)
  let above = fn() { t.drawn_of("先不换").map(fn(d) { d.1 }) }
  guard above() is Some(a0) else { fail("nothing over it drawn") }
  // where its words are drawn seen (at an alpha over 0)
  let seen = fn() {
    t.words().iter().find_first(fn(w) { w.0 == words && w.5 > 0.0 }).map(fn(w) { w.2 })
  }
  // The list sets out in the frame after its cause, what is over it going up then; and from the first frame its words
  // are seen they only go up, to where they rest. Till 2026-11-14 this said its words went up more than 20 from where
  // they were first found (Tester::drawn_of, which reads no alpha): on the old page they were found at 676.88 in the
  // cause's frame at alpha 0, 26.4 over their rest; seen (alpha over 0) they go up 10.2 there, 9.8 on the page made
  // as nodes, which draws nothing of a row half open or less. So the 20 held only of words drawn unseen.
  let mut a1 : Double? = None
  let ys : Array[Double] = []
  let mut n = 0
  while n < 60 {
    t.frame()
    if n == 0 {
      a1 = above()
    }
    match seen() {
      Some(y) => ys.push(y)
      None => ()
    }
    n += 1
  }
  assert_true(a1 is Some(a) && a < a0 - 0.01, msg="set out in the frame after its cause: \{a0} → \{Repr(a1)}")
  guard ys.length() > 0 else { fail("「\{words}」 never seen") }
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  t.run_for(@sf.enter_ms)
  guard seen() is Some(y1) else { fail("「\{words}」 not seen at rest") }
  // (up only, within half a device pixel, to its rest: more than none of the way seen)
  for i, y in ys {
    let before = if i > 0 { ys[i - 1] } else { y }
    assert_true(y <= before + 0.25 && y >= y1 - 0.25, msg="frame \{i}: \{Repr(ys)}, at rest \{y1}")
  }
  assert_true(ys[0] - y1 > 1.0, msg="seen going up after it: \{ys[0]} → \{y1}")
  fix_clock.val = None
}

///|
test "what was said while the app was away, brought after its chat opened at its end: read from its unread line" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
  fix_clock_set(clock, said_soon_ms)
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

///|
test "a notice opened keeps the size of its words" {
  // (the user, 2026-11-03: a failing notice tapped, its words grew to a message's size)
  let t = chat_tester("chat")
  let words = "Willow 上 codex 的登录已失效"
  let before = t.run_rects("Willow")
  assert_true(before.length() > 0)
  let (x, y) = t.find(words).unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let after = t.run_rects("Willow")
  assert_true(after.length() > 0)
  assert_true((after[0].2 - before[0].2).abs() < 0.5)
  assert_true((after[0].3 - before[0].3).abs() < 0.5)
}

///|
test "a chat's run changed: what changed on a line, else what it runs on now; pressed, both runs whole" {
  // (the user, 2026-11-06: 默认按最小差异显示，点击查看完整信息，如果差异太大一行显示不了，就只显示变化后的信息)
  let t = chat_tester("chat-run-change")
  // (the words drawn, each whole: what a row left out is of no size)
  let shown = fn() { t.words().filter(fn(w) { w.3 > 0.0 }).map(fn(w) { w.0 }) }
  let first = shown()
  // each side after the mark of who made its model
  assert_true(first.contains("Opus 5.5 · 高") && first.contains("Sonnet 5.5 · 中"), msg=first.join(" | "))
  // too long for a phone's line: what it runs on now alone, whole, after 换成 and its mark
  assert_true(!first.contains("Claude Code · Sonnet 5.5 · 中 · 标准"), msg=first.join(" | "))
  assert_true(first.contains("换成") && first.contains("Codex · GPT-6 Astra · 高 · Fast"), msg=first.join(" | "))
  assert_eq(t.lines_of("Codex · GPT-6 Astra · 高 · Fast"), ["Codex · GPT-6 Astra · 高 · Fast"])
  let (x, y) = t.find("Opus 5.5 · 高").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("之前：Claude Code · Opus 5.5 · 高 · 自动 · lin@example.com") is Some(_))
  assert_true(t.find("现在：Claude Code · Sonnet 5.5 · 中 · 自动 · lin@example.com") is Some(_))
  assert_true(!shown().contains("→"))
}

///|
/// How long the bell rises over the way to the end as that comes, and goes back down.
let ask_lift_ms : Double = 200.0
