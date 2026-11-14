// A new chat's first words (new_chat.mbt new_send, flight.mbt carried): the page the chat from the frame they are sent,
// they on screen where they were typed, then into their bubble over the composer with the chat's list coming up out of
// it (480 ms after 90, Ease.Arrive), the scene leaving from the same moment: however late the core answers (a phone's,
// a round trip later each, its first view of the chat later still), never gone for a frame nor drawn twice apart.

///|
/// Where words `s` are seen now under the bar (each copy of exactly them, not see-through): (x, y).
fn seen_words(t : @ui.Tester, s : String) -> Array[(Double, Double)] {
  t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 && w.2 > 60.0 }).map(fn(w) { (w.1, w.2) })
}

///|
/// Where words `s` are seen now: once (copies drawn over each other count as one), else the test fails.
fn seen_once(t : @ui.Tester, s : String) -> (Double, Double) raise {
  let at = seen_words(t, s)
  guard at.length() > 0 else { fail("「\{s}」 not seen at \{t.time()}") }
  for p in at {
    if (p.0 - at[0].0).abs() > 0.5 || (p.1 - at[0].1).abs() > 0.5 {
      fail("「\{s}」 seen twice apart at \{t.time()}: \{Repr(at)}")
    }
  }
  at[0]
}

///|
#callsite(autofill(loc))
fn assert_at(was : (Double, Double), now : (Double, Double), loc~ : SourceLoc) -> Unit raise {
  if (was.0 - now.0).abs() > 0.5 || (was.1 - now.1).abs() > 0.5 {
    fail("moved from \{Repr(was)} to \{Repr(now)} (\{loc})")
  }
}

///|
/// Home over the made-up chats with the core's answers to `newChat.create` and `chat.send` kept (`held`, by name: what
/// gives each), and the chat made unread while `unread` says (told as the test sets it): as a phone's core gives them,
/// a round trip later. In a phone's window, or `w` by `h` on `platform`.
fn held_core(
  held : Map[String, () -> Unit],
  unread : @signals.Signal[Bool],
  w? : Double = 390.0,
  h? : Double = 844.0,
  platform? : Int = 2,
) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "newChat.create" | "chat.send" =>
          (base.call)(name, params, fn(r) { held[name] = fn() { done(r) } })
        _ => (base.call)(name, params, done)
      }
    },
    topic_read: fn(name, params) {
      let t = base.topic(name, params).get().snapshot()
      let made = match params.get("session") {
        Some(String(s)) => s.has_prefix("new:")
        _ => false
      }
      if name == "chat" && made && unread.get() {
        { value: None, error: None, version: 0 }
      } else {
        t
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
}

///|
/// 令 tapped, `words` typed in the new chat and sent: where they are seen the frame after (over the field, the field
/// emptied under them).
fn new_chat_sent(t : @ui.Tester, words : String) -> (Double, Double) raise {
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.draw()
  let (_, field, _, _) = t.ime()
  assert_eq(field, "")
  let at = seen_once(t, words)
  // (in the composer, at the screen's foot)
  assert_true(at.1 > 700.0)
  at
}

///|
/// The frames from now till `until` (ms on the test's clock): each where words `s` are seen, and going one way only,
/// up or down as the first step goes (a frame's step at most `most`): from where they were typed into their bubble over
/// the composer at the chat's foot, the chat's rows standing at its end (Ctx::list's `from_end`).
fn one_way_till(t : @ui.Tester, s : String, until : Double, most : Double) -> (Double, Double) raise {
  let mut at = seen_once(t, s)
  let mut way = 0.0
  while t.time() < until {
    t.frame()
    let now = seen_once(t, s)
    let d = now.1 - at.1
    if d.abs() > most || (way != 0.0 && d * way < 0.0 && d.abs() > 0.5) {
      fail("「\{s}」 from \{Repr(at)} to \{Repr(now)} in a frame at \{t.time()}")
    }
    if d.abs() > 0.5 {
      way = d
    }
    at = now
  }
  at
}


///|
test "wide: a new chat's first words sent: its field's hint not drawn over them in the frame they go" {
  // (frame by frame as a host draws them, one build each: the core a round trip late, as a phone's)
  let src = @sffixture.round_trip(fixture_app("chat"), 60.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let carried = Ref(0)
  let hinted : Array[Double] = []
  let look = fn(t : @ui.Tester) {
    if seen_words(t, "把发布说明写一下").length() > 0 {
      carried.val += 1
      if hint_seen(t, hint="做任何事") {
        hinted.push(t.time())
      }
    }
  }
  t.drive(
    "timeout 20000\nuntil 新建对话\ntap 新建对话\nuntil 做任何事\ntap 做任何事\ntype 把发布说明写一下\ntap icon:arrow-up\n",
    each=look,
  )
  |> ignore
  // each frame of the words' way out of the field, till the page has become the chat and past it
  let till = t.time() + @sfbase.flight_desk_ms
  while t.time() < till {
    t.frame()
    look(t)
  }
  assert_true(carried.val > 10)
  assert_true(app.nav.top() is Chat(_))
  assert_eq(hinted, [])
}

///|
test "a new chat's first words go into their bubble from the frame they are sent, the core's answers and its view of the chat however late" {
  let held : Map[String, () -> Unit] = Map([])
  let unread = @signals.signal(true)
  let t = held_core(held, unread)
  let words = "把发布说明写一下"
  let typed = new_chat_sent(t, words)
  // the page the chat at once, by the key the core keeps for it, nothing of the core's answered
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "new:1")
    _ => fail("not the chat")
  }
  let sent = t.time()
  t.run_for(flight_carry_after_ms - 20.0)
  assert_at(typed, seen_once(t, words))
  // up with the list, no frame where they are not, nor a jump
  let landed = one_way_till(t, words, sent + flight_carry_after_ms + flight_carry_ms + 34.0, 120.0)
  assert_true(send_flight.get() is None)
  // in their bubble, over the composer at the chat's foot (its rows at its end, the room over them)
  assert_true(landed.1 < typed.1 && landed.1 > typed.1 - 200.0, msg="landed at \{Repr(landed)} from \{Repr(typed)}")
  assert_true((landed.0 - typed.0).abs() > 1.0)
  // the chat made, the message sent to it, its view read: they stay in their bubble (up only as what comes under them
  // opens its room, its agent's line)
  for name in ["newChat.create", "chat.send"] {
    match held.get(name) {
      Some(give) => give()
      None => fail("\{name} not asked")
    }
    t.draw()
    assert_at(landed, seen_once(t, words))
  }
  unread.set(false)
  t.draw()
  t.frame()
  let after = seen_once(t, words)
  assert_true(after.0 == landed.0 && after.1 <= landed.1 + 0.5 && landed.1 - after.1 < 12.0, msg="\{Repr(landed)} then \{Repr(after)}")
}

///|
/// The soft keyboard up over a phone's window (as a host says it, the app laid out above it): `h` of its 844.
fn keyboard_up(t : @ui.Tester, h : Double) -> Unit {
  t.set_ime_inset(h)
  t.resize_next(390.0, 844.0 - h)
  t.run_for(@ui.move_most_ms)
}

///|
test "a new chat's first words sent with the keyboard up: no words over others on any frame, the core however late" {
  // (words over words on any frame where something moves fail the test: words_over.mbt)
  let held : Map[String, () -> Unit] = Map([])
  let unread = @signals.signal(true)
  let t = held_core(held, unread)
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  keyboard_up(t, 336.0)
  let words = "把发布说明写一下"
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  let typed = seen_once(t, words)
  let landed = one_way_till(t, words, t.time() + flight_carry_after_ms + flight_carry_ms + 34.0, 120.0)
  assert_true(landed.1 < typed.1, msg="landed at \{Repr(landed)} from \{Repr(typed)}")
  for name in ["newChat.create", "chat.send"] {
    match held.get(name) {
      Some(give) => give()
      None => fail("\{name} not asked")
    }
    t.draw()
  }
  unread.set(false)
  t.run_for(new_leave_ms)
  assert_at(landed, seen_once(t, words))
}

///|
test "a new chat's restored picture travels from its composer into its first message" {
  let base = fixture_app("newchat-attach")
  let src : Source = {
    ..base,
    draft_picture: fn(_, _) {
      @ui.add_image("mem:test/new-restored", png_head())
      "mem:test/new-restored"
    },
    topic_read: fn(name, params) {
      let now = base.topic(name, params).get().snapshot()
      if name != "composer" { return now }
      // The fixture's draft comes with an in-memory picture, as one picked here. After a restart the app keeps none:
      // its source is the kept draft's, from the first read of it on.
      @sfbase.writing_pictures.remove("seed-0")
      let m = match now.value { Some(Object(v)) => v.copy(); _ => return now }
      m["files"] = Json::array(items(now.value, "files").map(fn(file) {
        guard file is Object(o) else { return file }
        let waiting = o.copy()
        waiting.remove("done")
        waiting["waits"] = Json::boolean(true)
        Json::object(waiting)
      }))
      { value: Some(Json::object(m)), error: now.error, version: now.version }
    },
    call: fn(name, params, done) {
      match name {
        // Hold creation so the first row remains local while it is checked.
        "newChat.create" => ()
        _ => (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.drive("timeout 20000\nuntil 想让 agent 做什么？\n") |> ignore
  t.run_for(@ui.image_fade_ms)
  assert_true(t.locate("img:mem:test/new-restored").length() > 0)
  tap_send(t)
  let flying = send_flight.get().unwrap().files
  assert_true(flying.iter().any(fn(f) { f.key == "upload:seed-0" && f.picture == Some("mem:test/new-restored") }))
  let row = sending_of(send_flight.get().unwrap().turns)[0].row
  assert_eq(sent_picture("ws1/st1", row.attachments[0]), Some("mem:test/new-restored"))
}

///|
test "a new chat's first words and picture sent with the keyboard up: no words over others on any frame" {
  let src = fixture_app("newchat-attach")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.drive("timeout 20000\nuntil 想让 agent 做什么？\n") |> ignore
  keyboard_up(t, 336.0)
  tap_send(t)
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  t.run_for(flight_carry_after_ms + flight_carry_ms + new_leave_ms)
  assert_true(send_flight.get() is None)
}

///|
test "a new chat's first words sent on a short page: nothing of its scene the foot hid is seen as the foot fades" {
  // (the scene longer than the page: its combinations under the band, frosted, and under the composer, hidden)
  let src = fixture_app("newchat-crowded")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=470.0, platform=2)
  t.drive("timeout 20000\nuntil 想让 agent 做什么？\n") |> ignore
  t.tap_text("做任何事")
  t.type_text("把发布说明写一下")
  t.run_for(@ui.move_most_ms)
  // the foot's top: what is seen under it is the choices' and the composer's alone
  let top = 470.0 - @motion.measured(t.ctx(), "new/foot").unwrap()
  let under = fn() { t.glyphs_seen().filter(fn(g) { g.3 > top + 1.0 }).length() }
  let before = under()
  tap_send(t)
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  // as it is sent, halfway through the choices' fading (the band's), as they have gone, as the scene is half gone
  for i, ms in [0.0, new_fade_ms / 2.0, new_fade_ms / 2.0, new_leave_ms / 2.0 - new_fade_ms] {
    if i > 0 {
      t.run_for(ms)
    }
    let now = under()
    if now > before {
      fail("\{now - before} glyphs more seen under the foot's top at \{t.time()} than before the words were sent")
    }
  }
}

///|
test "a new chat's first words sent: its scene fades where it is from then, as they go, not once the chat is made" {
  let held : Map[String, () -> Unit] = Map([])
  let t = held_core(held, @signals.signal(true))
  let title = "想让 agent 做什么？"
  new_chat_sent(t, "把发布说明写一下") |> ignore
  let at = seen_once(t, title)
  // halfway, the chat not made yet (the core's answers kept), the page it already: where it was, half faded
  t.run_for(new_leave_ms / 2.0)
  assert_true(app.nav.top() is Chat(_))
  match t.words().filter(fn(w) { w.0 == title }) {
    [w] => {
      assert_at(at, (w.1, w.2))
      assert_true(w.5 > 0.05 && w.5 < 0.95, msg="fading: \{w.5}")
    }
    ws => fail("「\{title}」 seen \{ws.length()} times")
  }
  t.run_for(new_leave_ms / 2.0)
  t.frame()
  assert_true(t.words().filter(fn(w) { w.0 == title && w.5 > 0.0 }).is_empty())
  // made and sent to: the page the chat, the scene not back over it
  match held.get("newChat.create") {
    Some(give) => give()
    None => fail("no chat asked for")
  }
  t.draw()
  match held.get("chat.send") {
    Some(give) => give()
    None => fail("the message not sent")
  }
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  t.run_for(new_leave_ms)
  assert_true(t.words().filter(fn(w) { w.0 == title && w.5 > 0.0 }).is_empty())
}

///|
test "a new chat's first words hold its composer as tall as it was while they are in it, its chat's, till they set out" {
  let held : Map[String, () -> Unit] = Map([])
  let unread = @signals.signal(true)
  let t = held_core(held, unread)
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text("第一行\n第二行\n第三行")
  t.run_for(@ui.move_most_ms)
  let box = fn() { @motion.measured(t.ctx(), "composer/content").unwrap() }
  let tall = box()
  tap_send(t)
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  assert_eq(box(), tall)
  // let go of as they set out, the core's answers kept the while
  let go = match app.nav.top() {
    Chat(r) => @sfbase.flight_lets_go(r.station + ":" + r.session).map(fn(l) { l.0 }).unwrap_or(@double.infinity)
    _ => @double.infinity
  }
  assert_true(go > t.time() && go < @double.infinity, msg="\{go} \{t.time()}")
  t.run_for(go - t.time())
  assert_true(box() < tall, msg="\{box()} \{tall}")
  ignore((held, unread))
}

///|
test "a new chat's first words with the core at once: never gone, into their bubble over the composer with the list" {
  let t = tester("home")
  let words = "把发布说明写一下"
  let typed = new_chat_sent(t, words)
  let sent = t.time()
  let landed = one_way_till(t, words, sent + flight_carry_after_ms + flight_carry_ms + 100.0, 120.0)
  assert_true(send_flight.get() is None)
  // over the composer at the chat's foot
  assert_true(landed.1 < typed.1 && landed.1 > typed.1 - 200.0, msg="landed at \{Repr(landed)} from \{Repr(typed)}")
}

///|
test "a new chat's first words not sent (the chat not made): the page the new chat again, they back in its field" {
  let held : Map[String, () -> Unit] = Map([])
  let unread = @signals.signal(true)
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "newChat.create" =>
          held[name] = fn() {
            done(Err({ "code": Json::string("unavailable"), "message": Json::string("Willow 离线") }))
          }
        _ => (base.call)(name, params, done)
      }
    },
  }
  ignore(unread)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let words = "把发布说明写一下"
  new_chat_sent(t, words) |> ignore
  // (the page the chat meanwhile, its scene gone)
  assert_true(app.nav.top() is Chat(_))
  t.run_for(new_leave_ms)
  match held.get("newChat.create") {
    Some(give) => give()
    None => fail("no chat asked for")
  }
  t.draw()
  assert_true(send_flight.get() is None)
  assert_true(app.nav.top() is NewChat)
  let (_, back, _, _) = t.ime()
  assert_eq(back, words)
  // its scene, gone as they were sent, back as it was
  t.run_for(new_leave_ms)
  t.frame()
  seen_once(t, "想让 agent 做什么？") |> ignore
  assert_true(t.words().filter(fn(w) { w.0 == "想让 agent 做什么？" && w.5 < 0.99 }).is_empty())
}

///|
/// Home over the made-up chats with the new chat's stations not read while `reading` says (the core's `newChat` with
/// no `stations`: only the station it last started on, `kept`), the new chats asked for counted in `made`.
fn reading_core(reading : @signals.Signal[Bool], made : Ref[Int]) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "newChat.create" {
        made.val += 1
      }
      (base.call)(name, params, done)
    },
    topic_read: fn(name, params) {
      if name == "newChat" && reading.get() {
        // (the key its chat is to be made under, as the core gives it whatever it has read)
        let next = text(base.topic(name, params).get().snapshot().value, "next")
        {
          value: Some({
            "kept": "st1",
            "next": Json::string(next),
            "any": false,
            "waiting": false,
          }),
          error: None,
          version: 0,
        }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
test "a new chat while its stations are read: its page as it will be, its first words sent at once to the station it last started on" {
  let reading = @signals.signal(true)
  let made = Ref(0)
  let t = reading_core(reading, made)
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  // the page's own words and its composer, nothing said of a station not known yet
  assert_true(t.find("想让 agent 做什么？") is Some(_))
  assert_true(t.find("它会在") is None)
  assert_true(t.find("没有可用模型") is None)
  // sent while they are read: made at once on the station it last started on (the owner, 2026-11-14: 「new chat 发消息
  // 任何时候都应该立即发出去」), the field emptied, never a press taken for nothing
  t.tap_text("做任何事")
  t.type_text("先写一半")
  t.draw()
  tap_send(t)
  t.draw()
  assert_eq(made.val, 1)
  let (_, field, _, _) = t.ime()
  assert_eq(field, "")
  assert_true(app.nav.top() is Chat(_))
  // read meanwhile: nothing more made
  reading.set(false)
  t.draw()
  assert_eq(made.val, 1)
}

///|
test "a new chat's first words: the room under its rows goes down to where the composer comes to stand, never at once" {
  let t = tester("home")
  // (three lines: the composer held as tall for them till they set out, lines more than it comes to stand at)
  let words = "第一行\n第二行\n第三行"
  ignore(new_chat_sent(t, words))
  // (every frame drawn from the press on, as a display draws them: the composer let go of as the words set out, its
  // room under the rows on the list's way with it, not a step)
  // (the chat's list's, the last list drawn, once it is the only one: the new chat's page has a list of its own
  // before, leaving as the chat comes)
  let foot = fn() {
    let lists = t.list_row_boxes()
    if !(app.nav.top() is Chat(_)) || lists.length() != 1 || lists[0].length() == 0 {
      -1.0
    } else {
      lists[0][lists[0].length() - 1].3
    }
  }
  let mut was = foot()
  let end = t.time() + flight_carry_after_ms + flight_carry_ms + @ui.move_most_ms
  while t.time() < end {
    t.frame()
    let now = foot()
    if was >= 0.0 && now >= 0.0 {
      assert_true((now - was).abs() < newchat_foot_step, msg="at \{t.time()}: the room under the rows \{was} → \{now}")
    }
    was = now
  }
}

///|
/// The most the room under a new chat's rows may change in a frame on its way (points): a line's at once is a step.
let newchat_foot_step : Double = 8.0

///|
test "unfolded: a new chat's long first words sent: the room under the chat's rows never below 0" {
  // (a foldable opened, laid out Medium with touch: the chat's list keeps the composer's room as it comes to stand,
  // composer_room's `settled`, from the frame the new chat becomes the chat; that room measured the new chat's tall
  // composer against a foot never measured on a chat's page, -200 under 0: 0.1.8569's crash, chat_list's Foot row
  // `Exact(<0>)`)
  let src = @sffixture.round_trip(fixture_app("chat"), 60.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=864.0, h=954.0, platform=2)
  // (what is held here is that it is drawn at all; how the composer opens at this width is not this test's)
  t.motion_unjudged(true)
  let words = "把发布说明写一下，" + "先列出这次改了什么、为什么改、谁会注意到，再按页面分组，每组写清楚旧的和新的样子。".repeat(6)
  t.drive("timeout 20000\nuntil 新建对话\ntap 新建对话\nuntil 做任何事\ntap 做任何事\n") |> ignore
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.draw()
  let till = t.time() + @sfbase.flight_desk_ms + new_leave_ms + @sfbase.sent_down_ms
  while t.time() < till {
    t.frame()
  }
  assert_true(app.nav.top() is Chat(_))
}
