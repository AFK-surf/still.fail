// A chat's page made with its inside nodes (sfbase's chat_page_nodes on: chat_page_made's `body` and `foot`), as a
// skeleton: its messages the page's list, the composer in the list's foot in its old view, the way back to the newest
// over it and a message gone to. That it holds together, no more: what else the old page floats over its list, puts
// over its rows and flies over it is not made yet.

///|
/// The fixture's chat s-c1 opened with its page's inside nodes, `w` by `h` on `platform`, at rest.
fn chat_nodes_tester(w : Double, h : Double, platform : Int) -> (@ui.Tester, Source) {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: its last message drawn, the list at its foot, the composer under it taking what is typed" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let (t, src) = chat_nodes_tester(w, h, platform)
    let last = "做完了：列表、跳到最新的按钮"
    guard t.rect_of(last) is Some((_, ly, _, lh)) else {
      fail("\{name}: its last message not drawn")
    }
    // (the lowest field drawn: the composer's)
    let mut field : (Double, Double, Double, Double)? = None
    for s in t.semantics() {
      if s.role == @ui.Role::TextField && (field is None || field.unwrap().1 < s.rect.1) {
        field = Some(s.rect)
      }
    }
    guard field is Some((fx, fy, fw, fh)) else { fail("\{name}: no composer's field") }
    assert_true(ly + lh <= fy, msg="\{name}: the last message (\{ly}+\{lh}) over the composer (\{fy})")
    // at its foot: the wheel further down moves nothing
    t.move_to(w / 2.0, ly)
    t.wheel(w / 2.0, ly, 400.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.rect_of(last).map(fn(r) { r.1 }), Some(ly), msg="\{name}: at its foot")
    // the composer takes what is typed
    t.tap(fx + fw / 2.0, fy + fh / 2.0)
    t.run_for(@ui.move_most_ms)
    t.type_text("先看第三项")
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").text.get(), "先看第三项", msg=name)
    // drawn in the field where it is now (the composer opened as it was focused): its words as the draw list has them
    // (an old view's field is a node whose words are its placeholder, mbui's Ctx::editor; what is typed in it is drawn
    // as its own runs, which Tester::find does not read)
    let mut now : (Double, Double, Double, Double)? = None
    for s in t.semantics() {
      if s.role == @ui.Role::TextField && (now is None || now.unwrap().1 < s.rect.1) {
        now = Some(s.rect)
      }
    }
    guard now is Some((nx, ny, nw, nh)) else { fail("\{name}: no composer's field once typed in") }
    let typed = t.text_runs().filter(fn(r) { r.text.contains("先看第三项") })
    assert_true(
      typed.iter().any(fn(r) { r.top < ny + nh && r.bottom > ny && r.x0 >= nx && r.x0 < nx + nw }),
      msg="\{name}: what is typed drawn in the field at \{Repr((nx, ny, nw, nh))}: \{Repr(typed.map(fn(r) { (r.x0, r.top, r.bottom) }))}",
    )
  }
}

///|
/// The fixture's chat s-c1 (`fixture_mode` its fixture's) with its page's inside nodes, `w` by `h` on `platform`, at
/// rest, its last message the viewer's own where `mine`, the core's calls kept in `calls` (and answered as the
/// fixture's, but the chat's picture: chat.publishPreview left unanswered). Its messages without their files: no
/// picture's bytes handed to the host (this file has no bar for them, host_image_bytes_known_wbtest's), what a message
/// offers of itself the same. As many messages as `came` says come after its last (each a copy of it, its seq the next).
fn chat_nodes_calling(
  w : Double,
  h : Double,
  platform : Int,
  calls : Array[(String, Json)],
  mine? : Bool = false,
  fixture_mode? : String = "chat",
  came? : @signals.Signal[Int] = @signals.signal(0),
) -> (@ui.Tester, Source) {
  new_run()
  @sf.presenters_reset()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture(fixture_mode)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      guard name == "chat" && got.value is Some(Object(chat)) else { return got }
      let out = chat.copy()
      let messages = items(got.value, "messages")
      let n = messages.length()
      let kept = messages.mapi(fn(i, j) {
        guard j is Object(was) else { return j }
        let m = was.copy()
        m.remove("attachments")
        m.remove("placed")
        if mine && i == n - 1 {
          m["mine"] = Json::boolean(true)
        }
        Json::object(m)
      })
      let more = if text(Some(Json::object(params)), "session") == "s-c1" { came.get() } else { 0 }
      for k in 1..=more {
        guard kept[n - 1] is Object(last) else { break }
        let m = last.copy()
        let seq = number(Some(kept[n - 1]), "seq") + k.to_double()
        m["seq"] = Json::number(seq)
        m["ts"] = Json::string("ts\{seq}")
        kept.push(Json::object(m))
      }
      out["messages"] = Json::array(kept)
      { ..got, version: got.version + more, value: Some(Json::object(out)) }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      // (the chat's picture asked, kept unanswered: what the test asks is that it is asked, and a picture drawn would
      // hand the host its bytes)
      if name != "chat.publishPreview" {
        (base.call)(name, params, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
/// What a message's menu offers (sfbase's message_items, the old row's ⋯ and right click), each shown now.
fn message_menu_shown(t : @ui.Tester, name : String) -> Unit raise {
  for item in ["复制消息", "复制消息链接", "多选"] {
    assert_true(t.find(item) is Some(_), msg="\{name}: \{item}")
  }
}

///|
/// What a `client.focus {chat}` told says: its end seen, the last message seen whole.
fn chat_nodes_focus_told(j : Json) -> (Json?, Json?) {
  match j {
    Object(o) =>
      match o.get("chat") {
        Some(Object(ch)) => (ch.get("end"), ch.get("seen"))
        _ => (None, None)
      }
    _ => (None, None)
  }
}

///|
/// 多选 chosen: the chat's picture asked of the core once, of the whole chat (chat.publishPreview, its thread).
fn message_menu_publishes(calls : Array[(String, Json)], name : String) -> Unit raise {
  let asked = calls.filter(fn(c) { c.0 == "chat.publishPreview" })
  assert_eq(asked.length(), 1, msg=name)
  assert_eq(number(Some(asked[0].1), "thread"), 7.0, msg=name)
}

///|
test "大屏 with its inside nodes: an agent's message offers its ⋯ (named once) and a right click, an own message a right click, as the old rows did; 多选 asks the chat's picture" {
  for mine in [false, true] {
    let name = if mine { "own" } else { "agent's" }
    let calls : Array[(String, Json)] = []
    let (t, _) = chat_nodes_calling(1280.0, 800.0, 0, calls, mine~)
    let words = "做完了：列表、跳到最新的按钮"
    let (x, y, _, _) = t.rect_of(words).unwrap()
    t.move_to(x + 24.0, y + 8.0)
    t.frame()
    t.frame()
    let more = t.all(Button).filter(fn(s) { s.label == "更多操作" })
    assert_eq(more.length(), if mine { 0 } else { 1 }, msg="\{name}: its ⋯ \{Repr(more.map(fn(s) { s.rect }))}")
    if !mine {
      t.click(Button, label="更多操作")
      t.run_for(@ui.move_most_ms)
      message_menu_shown(t, name + " ⋯")
      t.tap_text("复制消息链接")
      t.frame()
      assert_eq(t.clipboard(), "https://app.still.fail/o/ws1/st1/s-c1?message=11", msg=name)
      t.run_for(@ui.move_most_ms)
      assert_true(t.find("复制消息链接") is None, msg="\{name}: its ⋯'s menu gone")
    }
    t.right_click(x + 24.0, y + 8.0)
    t.frame()
    t.frame()
    message_menu_shown(t, name + " right click")
    t.tap_text("多选")
    t.frame()
    message_menu_publishes(calls, name)
    @sf.close_all_presented()
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenting(), msg=name)
  }
}

///|
test "大屏 with its inside nodes: an agent's picture opens its card under a pointer, closed once the pointer has left it" {
  let (t, _) = chat_nodes_calling(1280.0, 800.0, 0, [], fixture_mode="chat-working")
  let card = "8 轮 · 共干了 1 小时 12 分"
  assert_true(t.find(card) is None)
  // (the picture of the last of the agent's messages: before its name, out in the margin)
  let names = t.all(Link).filter(fn(s) { s.label == "Claude" })
  guard names.last() is Some(at) else { fail("no agent's message") }
  let (nx, ny, _, nh) = at.rect
  t.move_to(nx - 20.0, ny + nh / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find(card) is Some(_), msg="its card over its picture")
  t.move_to(1.0, 1.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_true(t.find(card) is None, msg="closed")
}

///|
/// How far the composer's ground (the lowest wide glass drawn) stands under the chat's last message's words.
fn foot_gap(t : @ui.Tester) -> Double raise {
  let mut top : Double? = None
  for g in t.drawn_glass() {
    let (_, y, w, _, _, _) = g
    if w > 150.0 && (top is None || top.unwrap() < y) {
      top = Some(y)
    }
  }
  guard top is Some(top) else { fail("no composer drawn at \{t.time()}") }
  guard t.rect_of("做完了：列表、跳到最新的按钮") is Some((_, y, _, h)) else {
    fail("the last message gone from view at \{t.time()}")
  }
  top - (y + h)
}

///|
/// The composer's field focused and given a line more, as `platform` takes a new line in it.
fn foot_line_more(t : @ui.Tester, platform : Int) -> Unit {
  let mut field : (Double, Double, Double, Double)? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && (field is None || field.unwrap().1 < s.rect.1) {
      field = Some(s.rect)
    }
  }
  match field {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
  t.run_for(@ui.move_most_ms)
  t.type_text("第一行")
  if platform == 2 {
    t.enter()
  } else {
    t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  }
  t.type_text("第二行")
}

///|
/// Each step of what changes the composer's height or the room round it, on 小屏 (`platform` 2) or 大屏, and how far
/// its ground stands under the last message's words at rest after it, and what was on its way in the frame after the
/// window's step (idle_said's).
fn foot_steps(w : Double, h : Double, platform : Int) -> Array[(String, Double, String?)] raise {
  let (t, src) = chat_nodes_tester(w, h, platform)
  let draft = @sfbase.writing(src, "ws1/st1:s-c1")
  let steps : Array[(String, Double, String?)] = []
  let step_done = fn(name : String) -> Unit raise {
    t.run_for(@ui.move_most_ms)
    steps.push((name, foot_gap(t), None))
  }
  step_done("opened")
  foot_line_more(t, platform)
  step_done("a line more")
  @sfbase.writing_add(src, draft, "ws1/st1", "build.log", @utf8.encode("夜里的构建日志"))
  step_done("a file")
  // (a quote: the focus given to its own field, made in the list's foot; what comes after it followed as after a file)
  @sfbase.writing_quote(src, draft, { "author": "Claude", "text": "其余的行按估计的高度占位", "ts": "ts8" })
  step_done("a quote")
  @sfbase.writing_error(src, draft, "发送没有成功")
  step_done("an error")
  let moved = fn(name : String) -> Unit raise {
    t.frame()
    let said = t.idle_said()
    t.run_for(@ui.move_most_ms)
    steps.push((name, foot_gap(t), said))
  }
  if platform == 2 {
    t.set_ime_inset(300.0)
    t.resize_next(w, h - 300.0)
    step_done("the keyboard up")
    t.set_ime_inset(0.0)
    t.resize_next(w, h)
    step_done("the keyboard down")
  } else {
    t.resize(900.0, h)
    moved("the window narrower")
    t.resize(w, h)
    moved("the window wider")
    // (not walked yet: a side panel opened. As it slides in and the chat's width passes chat_narrow_w, a card's
    // button (先不换) steps 8 in its row in one frame, at 60 and 120 frames a second: the rows', nothing of the
    // composer's, to mend with the rows; the distance held after it, 36.2)
  }
  steps
}

///|
test "the composer in the list's foot, on 小屏 and 大屏: at its foot the last message as far over it after each change, nothing covered, nothing on its way after the window's" {
  let said : Array[String] = []
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let now = foot_steps(w, h, platform)
    // (opened with a line more: how far the last message stands over it at its foot, the room under the last row)
    let at_foot = now[1].1
    let wrong : Array[String] = []
    for i, s in now {
      let (step, gap, said) = s
      // (a capsule before it is opened: its ground lower in the same room, as far over it or further)
      let kept = if i == 0 { gap >= at_foot } else { (gap - at_foot).abs() <= 0.5 }
      if !kept || gap < 0.0 || said is Some(_) {
        wrong.push(step)
      }
    }
    if !wrong.is_empty() {
      // (a line a step: a runner cuts long lines)
      said.push("\{name}: \{Repr(wrong)} in")
      for s in now {
        said.push("  \{s.0}: \{s.1} \{Repr(s.2)}")
      }
    }
  }
  assert_true(said.is_empty(), msg=said.join("\n"))
}

///|
/// The long chat (chat_window_wbtest's) opened on screen `s` with its page's inside nodes, at rest.
fn foot_long_open(l : LongChat, s : (String, Double, Double, Int)) -> (@ui.Tester, Source) {
  let (_, w, h, platform) = s
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let src = long_source(l)
  open_chat(long_ref)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  long_run(t, l, long_opened_ms)
  (t, src)
}

///|
test "the composer in the list's foot, on 小屏 and 大屏: read up the list, a line more, a file, a quote or an error in the composer moves nothing of what is read" {
  for s in long_screens {
    let (name, w, h, platform) = s
    let l = long_chat()
    let (t, src) = foot_long_open(l, s)
    let draft = @sfbase.writing(src, "ws1/st1:s-c1")
    // (as the error comes in the composer under its quote, on 小屏, the quote's 「Claude」 is drawn under 「发送没有成功」
    // while it moves (words over words, 5100 at the default rate): the composer's to mend; what is read is held here as
    // a result)
    t.motion_unjudged(true)
    t.move_to(w / 2.0, h / 2.0)
    t.wheel(w / 2.0, h / 2.0, -600.0)
    long_run(t, l, long_rest_ms)
    // (a message's words in the middle of what shows)
    let mut read : (String, Double)? = None
    for n in 1..=long_count {
      let said = "第\{n}条："
      if read is None && t.rect_of(said) is Some((_, y, _, _)) && y > h / 3.0 && y < h / 2.0 {
        read = Some((said, y))
      }
    }
    guard read is Some((words, y)) else { fail("\{name}: nothing read in the middle of the list") }
    let at = fn(step : String) -> Unit raise {
      long_run(t, l, @ui.move_most_ms)
      let now = t.rect_of(words).map(fn(r) { r.1 })
      assert_true(
        now is Some(ny) && (ny - y).abs() < 0.5,
        msg="\{name}, \{step}: \{words} at \{y}, now \{Repr(now)}",
      )
    }
    foot_line_more(t, platform)
    at("a line more")
    @sfbase.writing_add(src, draft, "ws1/st1", "build.log", @utf8.encode("夜里的构建日志"))
    at("a file")
    @sfbase.writing_quote(src, draft, { "author": "Claude", "text": "其余的行按估计的高度占位", "ts": "ts8" })
    at("a quote")
    @sfbase.writing_error(src, draft, "发送没有成功")
    at("an error")
  }
}

///|
test "a chat's page made with its inside nodes tells the core what is read and where it is, on 小屏 and 大屏: at its foot, covered, read up, left" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let calls : Array[(String, Json)] = []
    let came = @signals.signal(0)
    let (t, src) = chat_nodes_calling(w, h, platform, calls, came~)
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    guard @sfbase.view_of_chat(src, r).0 is Some(v) && v.messages.last() is Some(last) else {
      fail("\{name}: the chat's view not read")
    }
    // (what is told of this chat: another's page tells of its own)
    let focus = fn() {
      calls
      .filter(fn(c) {
        c.0 == "client.focus" && @sfbase.text(@sfbase.field(Some(c.1), "chat"), "session") == r.session
      })
      .map(fn(c) { c.1 })
    }
    let places = fn() { calls.filter(fn(c) { c.0 == "chat.place" }).map(fn(c) { c.1 }) }
    // opened at its foot: it shows, its end seen, its last message seen whole
    guard focus().last() is Some(f) else {
      fail("\{name}: the chat shown told nothing: \{Repr(calls.map(fn(c) { c.0 }))}")
    }
    assert_eq(chat_nodes_focus_told(f), (Some(Json::boolean(true)), Some(Json::number(last.seq))), msg=name)
    // covered by another page: a message that comes tells nothing (it is not seen)
    @sfbase.open_page_over(Chat({ station: "ws1/st1", session: "s-c3", title: "另一个", station_name: "Willow" }))
    t.run_for(@ui.move_most_ms)
    let (told, placed) = (focus().length(), places().length())
    came.set(1)
    t.run_for(@ui.move_most_ms)
    assert_eq((focus().length(), places().length()), (told, placed), msg="\{name}: told while covered")
    // shown again: told once what is in sight then, the message that came seen whole
    assert_true(@sfbase.go_back(), msg=name)
    t.run_for(@ui.move_most_ms)
    let again = focus()[told:].to_owned()
    assert_eq(again.length(), 1, msg="\{name}: \{Repr(again.map(fn(j) { j.stringify() }))}")
    assert_eq(chat_nodes_focus_told(again[0]), (Some(Json::boolean(true)), Some(Json::number(last.seq + 1.0))), msg=name)
    // read up: at rest, its end not seen, where it is told with a message and its offset, as the message at the top
    // changes
    let placed = places().length()
    let (x, y) = (w * 0.6, h / 2.0)
    t.move_to(x, y)
    // (read up)
    t.wheel(x, y, -600.0)
    t.run_for(@ui.move_most_ms)
    guard focus().last() is Some(up) else { fail("\{name}: nothing told read up") }
    assert_eq(chat_nodes_focus_told(up).0, Some(Json::boolean(false)), msg=name)
    let read_up = places()[placed:].to_owned()
    guard read_up.last() is Some(p) else { fail("\{name}: where it is not told read up") }
    assert_true(
      @sfbase.number(Some(p), "seq") >= 0.0 && @sfbase.field(Some(p), "offset") is Some(_),
      msg="\{name}: \{p.stringify()}",
    )
    assert_eq(@sfbase.number(Some(p), "thread"), 7.0, msg=name)
    for i in 1..<read_up.length() {
      assert_true(
        @sfbase.field(Some(read_up[i]), "seq") != @sfbase.field(Some(read_up[i - 1]), "seq"),
        msg="\{name}: told again with the same message at the top: \{Repr(read_up.map(fn(j) { j.stringify() }))}",
      )
    }
    // left: told once it shows no more, and where it was left; nothing told of it after
    let before = places().length()
    let shown = focus().length()
    home()
    t.run_for(@ui.move_most_ms)
    let lefts = calls.filter(fn(c) {
      c.0 == "client.focus" && @sfbase.text(@sfbase.field(Some(c.1), "left"), "session") == r.session
    })
    assert_eq(lefts.length(), 1, msg=name)
    assert_true(places().length() <= before + 1, msg=name)
    guard places().last() is Some(at) else { fail("\{name}: no place") }
    assert_eq(@sfbase.field(Some(at), "seq"), @sfbase.field(Some(p), "seq"), msg="\{name}: left where it was read")
    assert_eq(focus().length(), shown, msg="\{name}: told it shows after it was left")
  }
}

///|
/// The long chat (chat_window_wbtest's) opened on screen `s` with its page's inside nodes, at rest (the Tester's screen:
/// 2 pixels a point); the core saying where it was left (`at`: the message's seq, its top under the list's in pixels, if
/// said) and its unread line at message `line` (none at 0) as it is read; `before` done as the run begins, before the chat
/// is opened (a message it is to go to).
fn place_long_open(
  l : LongChat,
  s : (String, Double, Double, Int),
  at? : (Double, Double?)? = None,
  line? : @signals.Signal[Int] = @signals.signal(0),
  before? : () -> Unit = fn() {  },
) -> @ui.Tester {
  let (_, w, h, platform) = s
  new_run()
  @sfbase.chat_page_nodes.set(true)
  before()
  let base = long_source(l)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = (base.topic_read)(name, params)
      guard name == "chat" && got.value is Some(Object(v)) else { return got }
      let out = v.copy()
      match at {
        Some((seq, px)) => {
          out["at"] = Json::number(seq)
          match px {
            Some(p) => out["atOffset"] = Json::number(p)
            None => ()
          }
        }
        None => ()
      }
      let n = line.get()
      if n > 0 {
        out["unreadLine"] = Json::number(n.to_double())
      }
      { ..got, value: Some(Json::object(out)), version: got.version + n * 1000000 }
    },
  }
  open_chat(long_ref)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  long_run(t, l, long_opened_ms)
  t
}

///|
/// The long chat left (back to the chats) and opened again, at rest: each step from outside the frames, as a press's,
/// and `meanwhile` (what the core says while it is away) between them.
fn place_left_and_opened(t : @ui.Tester, l : LongChat, meanwhile? : () -> Unit = fn() {  }) -> Unit {
  home()
  @ui.came_from_outside()
  long_run(t, l, long_opened_ms)
  meanwhile()
  open_chat(long_ref)
  @ui.came_from_outside()
  long_run(t, l, long_opened_ms)
}

///|
test "a chat's page made with its inside nodes opens where it was left, on 小屏 and 大屏: left at its end, at its end, what came since too; read up, at the same messages as far down" {
  for s in long_screens {
    let (name, w, h, _) = s
    // left at its end, with nothing come since and with a message come since
    for came in [0, 1] {
      let l = long_chat()
      let t = place_long_open(l, s)
      // (at its end as it opens: how far down its last message's words end)
      let foot_of = fn(n : Int) { t.rect_of("第\{n}条：").map(fn(r) { r.1 + r.3 }) }
      guard foot_of(long_count) is Some(end) else { fail("\{name}: its last message not drawn as it opens") }
      place_left_and_opened(t, l, meanwhile=fn() { if came > 0 { l.last.set(l.last.get() + came) } })
      let now = foot_of(long_count + came)
      assert_true(
        now is Some(y) && (y - end).abs() <= 1.0,
        msg="\{name}, \{came} come since: its last message at \{Repr(now)}, its end \{end}",
      )
    }
    // read up
    let l = long_chat()
    let t = place_long_open(l, s)
    t.move_to(w / 2.0, h / 2.0)
    t.wheel(w / 2.0, h / 2.0, -600.0)
    long_run(t, l, long_rest_ms)
    let seen : Array[(Int, Double)] = []
    for n in l.first.get()..=l.last.get() {
      if t.rect_of("第\{n}条：") is Some((_, y, _, _)) && y > h / 4.0 && y < h * 0.75 {
        seen.push((n, y))
      }
    }
    assert_true(seen.length() > 0, msg="\{name}: nothing read in the middle of the list")
    place_left_and_opened(t, l)
    let wrong = seen.filter(fn(p) { !(t.rect_of("第\{p.0}条：") is Some((_, y, _, _)) && (y - p.1).abs() <= 1.0) })
    assert_true(
      wrong.is_empty(),
      msg="\{name}: read up \{Repr(seen)}, now \{Repr(wrong.map(fn(p) { t.rect_of("第\{p.0}条：").map(fn(r) { r.1 }) }))}",
    )
  }
}

///|
test "a chat's page made with its inside nodes opens where the core says it was left, nothing kept this run, on 小屏 and 大屏: the first message at or after it, as far under the list's top as it says in the screen's pixels" {
  for s in long_screens {
    let (name, _, _, _) = s
    // (the message in the middle of the window it opens on: room over it and under it)
    let n = {
      let l = long_chat()
      place_long_open(l, s) |> ignore
      (l.first.get() + l.last.get()) / 2
    }
    let words = "第\{n}条："
    let ys : Array[Double] = []
    // (in the screen's pixels: as many again under the list's top moves it as far again, whatever the screen's scale)
    for px in [Some(120.0), Some(240.0), Some(360.0), None] {
      let l = long_chat()
      let t = place_long_open(l, s, at=Some((n.to_double() - 0.5, px)))
      guard t.rect_of(words) is Some((_, y, _, _)) else { fail("\{name}: \{words} not drawn opened at \{Repr(px)}") }
      ys.push(y)
    }
    let (h, step) = (s.2, ys[1] - ys[0])
    // (said on one line: a runner reads a failure's first line)
    let said = "\{name}: " + ys.map(fn(y) { y.to_string() }).join(" ")
    // (further down each time, by as much again, to a point: the row brought holds where it shows from as the rows
    // over it are measured, ListPlace::bring)
    assert_true(step > 10.0 && (ys[2] - ys[1] - step).abs() <= 1.0, msg=said)
    // (none said: its top just under the bar's room, in the upper half of what shows)
    assert_true(ys[3] > 0.0 && ys[3] < h / 2.0, msg=said)
  }
}

///|
test "a chat's page made with its inside nodes opens at its unread line before where it was left, on 小屏 and 大屏" {
  for s in long_screens {
    let (name, w, h, _) = s
    let l = long_chat()
    let line = @signals.signal(0)
    let t = place_long_open(l, s, line~)
    // (read up: the wheel's)
    t.move_to(w / 2.0, h / 2.0)
    t.wheel(w / 2.0, h / 2.0, -600.0)
    long_run(t, l, long_rest_ms)
    place_left_and_opened(t, l, meanwhile=fn() { line.set(l.first.get() + 3) })
    let at = t.rect_of("以下是新消息")
    assert_true(at is Some((_, y, _, _)) && y > 0.0 && y < h / 3.0, msg="\{name}: the unread line at \{Repr(at)}")
  }
}

///|
/// The way back to the newest of the long chat's page now (named 跳到最新, or 回到刚才的位置 where `back`), if shown.
fn to_newest_shown(t : @ui.Tester, back? : Bool = false) -> @ui.SemNode? {
  t.query(Button, label=if back { "回到刚才的位置" } else { "跳到最新" })
}

///|
/// The top of the lowest field drawn (the composer's), if any.
fn composer_top(t : @ui.Tester) -> Double? {
  let mut top : Double? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && (top is None || top.unwrap() < s.rect.1) {
      top = Some(s.rect.1)
    }
  }
  top
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the way back to the newest none at its end; read up, shown over the composer, named, pressed in 44 by 44; pressed, at its end again and gone" {
  for s in long_screens {
    let (name, w, h, _) = s
    let l = long_chat()
    let t = place_long_open(l, s)
    let last = "第\{long_count}条："
    guard t.rect_of(last) is Some((_, end, _, _)) else { fail("\{name}: its last message not drawn as it opens") }
    assert_true(to_newest_shown(t) is None, msg="\{name}: the way back to the newest shown at its end")
    // (read up)
    t.move_to(w / 2.0, h / 2.0)
    t.wheel(w / 2.0, h / 2.0, -600.0)
    long_run(t, l, long_rest_ms)
    guard to_newest_shown(t) is Some(b) else { fail("\{name}: the way back to the newest not shown read up") }
    let (_, by, bw, bh) = b.rect
    let field = composer_top(t)
    assert_true(
      bw >= 44.0 && bh >= 44.0 && by > h / 2.0 && field is Some(f) && by + bh <= f,
      msg="\{name}: the way back to the newest at \{Repr(b.rect)}, the composer's field at \{Repr(field)}",
    )
    t.click(Button, label="跳到最新")
    long_run(t, l, long_rest_ms)
    let now = t.rect_of(last).map(fn(r) { r.1 })
    assert_true(now is Some(y) && (y - end).abs() <= 1.0, msg="\{name}: pressed, its last message at \{Repr(now)}, its end \{end}")
    assert_true(to_newest_shown(t) is None, msg="\{name}: the way back to the newest shown at its end again")
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a message gone to among its rows just under its top; the way back to the newest back where the reader was first, then to its end" {
  for s in long_screens {
    let (name, w, h, _) = s
    let l = long_chat()
    let t = place_long_open(l, s)
    let last = "第\{long_count}条："
    guard t.rect_of(last) is Some((_, end, _, _)) else { fail("\{name}: its last message not drawn as it opens") }
    // (read up more than a screen: the wheel's)
    t.move_to(w / 2.0, h / 2.0)
    for _ in 0..<3 {
      t.wheel(w / 2.0, h / 2.0, -600.0)
      long_run(t, l, long_rest_ms)
    }
    let seen : Array[(Int, Double)] = []
    for n in l.first.get()..=l.last.get() {
      if t.rect_of("第\{n}条：") is Some((_, y, _, _)) && y > h / 4.0 && y < h * 0.75 {
        seen.push((n, y))
      }
    }
    assert_true(seen.length() > 0, msg="\{name}: nothing read in the middle of the list")
    // gone to inside the chat as it shows (a quote's, a row's state line): a message near the top of what it holds
    let target = l.first.get() + 3
    go_to(long_ref, target.to_double())
    @ui.came_from_outside()
    long_run(t, l, long_rest_ms)
    let at = t.rect_of("第\{target}条：")
    assert_true(at is Some((_, y, _, _)) && y > 0.0 && y < h / 3.0, msg="\{name}: \{target} gone to at \{Repr(at)}")
    assert_true(!@sfbase.go_tos.contains(long_ref.station + "\u{1}" + long_ref.session), msg="\{name}: still to go to")
    // back where the reader was, then to its end
    t.click(Button, label="回到刚才的位置")
    long_run(t, l, long_rest_ms)
    let wrong = seen.filter(fn(p) { !(t.rect_of("第\{p.0}条：") is Some((_, y, _, _)) && (y - p.1).abs() <= 1.0) })
    assert_true(
      wrong.is_empty(),
      msg="\{name}: read at \{Repr(seen)}, back at \{Repr(wrong.map(fn(p) { t.rect_of("第\{p.0}条：").map(fn(r) { r.1 }) }))}",
    )
    assert_true(to_newest_shown(t, back=true) is None, msg="\{name}: the way back still back once there")
    t.click(Button, label="跳到最新")
    long_run(t, l, long_rest_ms)
    let now = t.rect_of(last).map(fn(r) { r.1 })
    assert_true(now is Some(y) && (y - end).abs() <= 1.0, msg="\{name}: pressed again, its last message at \{Repr(now)}, its end \{end}")
    assert_true(to_newest_shown(t) is None, msg="\{name}: the way back to the newest shown at its end")
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: opened to go to a message before what it opens on, the pages before asked till it comes, it just under its top, nothing left to go to" {
  for s in long_screens {
    let (name, h) = (s.0, s.2)
    let target = 120
    let l = long_chat()
    let t = place_long_open(l, s, before=fn() { go_to(long_ref, target.to_double(), keep_place=false) })
    long_run(t, l, long_rest_ms)
    let older = l.asked.filter(fn(a) { a.has_prefix("older") })
    assert_true(older.length() > 0, msg="\{name}: asked \{@ui.list_text(l.asked)}")
    let at = t.rect_of("第\{target}条：")
    assert_true(
      at is Some((_, y, _, _)) && y > 0.0 && y < h / 3.0,
      msg="\{name}: \{target} at \{Repr(at)}, asked \{@ui.list_text(l.asked)}, first \{l.first.get()}",
    )
    assert_true(!@sfbase.go_tos.contains(long_ref.station + "\u{1}" + long_ref.session), msg="\{name}: still to go to")
  }
}

///|
/// The long chat opened on `s` with its page's inside nodes, read up from its end, nothing focused, at rest; its last
/// message's words and where they were at its end.
fn keys_long_open(l : LongChat, s : (String, Double, Double, Int)) -> (@ui.Tester, String, Double) raise {
  let (name, w, h, _) = s
  let t = place_long_open(l, s)
  let last = "第\{long_count}条："
  guard t.rect_of(last) is Some((_, end, _, _)) else { fail("\{name}: its last message not drawn as it opens") }
  t.ctx().blur()
  t.move_to(w / 2.0, h / 2.0)
  t.wheel(w / 2.0, h / 2.0, -600.0)
  long_run(t, l, long_rest_ms)
  assert_true(t.rect_of(last) is None, msg="\{name}: read up, its last message still at \{Repr(t.rect_of(last))}")
  (t, last, end)
}

///|
test "a chat's page made with its inside nodes, a page pushed over it on 小屏: ⌘↓, Space and ⌘U do nothing of the chat's" {
  let l = long_chat()
  let (t, last, _) = keys_long_open(l, ("小屏", 390.0, 844.0, 2))
  @sfbase.open_page(Archived)
  @ui.came_from_outside()
  long_run(t, l, long_opened_ms)
  let picks = t.pick_asks().length()
  t.key(@ui.key_code_down, mods=@ui.mod_cmd)
  t.key(@ui.key_space)
  t.key(@ui.key_of_char('u'), mods=@ui.mod_cmd)
  long_run(t, l, long_rest_ms)
  assert_true(!focus_said(t).contains("发消息"), msg="the composer focused: \{focus_said(t)}")
  assert_eq(t.pick_asks().length(), picks, msg="a picker asked")
  assert_true(@sfbase.go_back(), msg="no way back to the chat")
  @ui.came_from_outside()
  long_run(t, l, long_opened_ms)
  assert_true(t.rect_of(last) is None, msg="⌘↓ took the list to \{Repr(t.rect_of(last))}")
}

///|
test "大屏, a chat's page made with its inside nodes: ⌘↓ takes the list read up back to its end, Space puts the cursor in the composer, ⌘U asks the system's picker" {
  let l = long_chat()
  let (t, last, end) = keys_long_open(l, ("大屏", 1280.0, 800.0, 0))
  t.key(@ui.key_code_down, mods=@ui.mod_cmd)
  long_run(t, l, long_rest_ms)
  let now = t.rect_of(last).map(fn(r) { r.1 })
  assert_true(now is Some(y) && (y - end).abs() <= 1.0, msg="⌘↓: its last message at \{Repr(now)}, its end \{end}")
  t.ctx().blur()
  long_run(t, l, long_rest_ms)
  t.key(@ui.key_space)
  long_run(t, l, long_rest_ms)
  assert_eq(focus_said(t), "TextField 发消息")
  let picks = t.pick_asks().length()
  t.key(@ui.key_of_char('u'), mods=@ui.mod_cmd)
  long_run(t, l, long_rest_ms)
  assert_eq(t.pick_asks().length(), picks + 1, msg="⌘U")
}

///|
/// The fixture's chat s-c1 whose last message places a page (chat-viz: release.html, a fragment) with its page's inside
/// nodes, `w` by `h` on `platform`, at rest, its page not drawn by its host yet where `held` (viz_nodes_run), else as
/// the host draws it; what is asked of the
/// core (a call's name, a file's too) kept in `asked`. Its other messages without their files: no picture's bytes
/// handed to the host (chat_nodes_calling's).
fn viz_nodes_open(w : Double, h : Double, platform : Int, asked : Array[String], held? : Bool = true) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("chat-viz")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      guard name == "chat" && got.value is Some(Object(chat)) else { return got }
      let out = chat.copy()
      out["messages"] = Json::array(
        items(got.value, "messages").map(fn(j) {
          guard j is Object(was) && !(was.get("placed") is Some(Array([String("release.html"), ..]))) else { return j }
          let m = was.copy()
          m.remove("attachments")
          m.remove("placed")
          Json::object(m)
        }),
      )
      { ..got, value: Some(Json::object(out)) }
    },
    call: fn(name, params, done) {
      asked.push(name)
      (base.call)(name, params, done)
    },
    read_bytes: fn(name, params, done) {
      asked.push(name)
      (base.read_bytes)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, finish=!held)
  viz_nodes_run(t, @ui.move_most_ms, held)
  t
}

///|
/// Where the host has the message's page (x0, y0, x1, y1), shown; why not, where it is not.
fn viz_nodes_shown(t : @ui.Tester, page : @ui.NativeView) -> Result[(Double, Double, Double, Double), String] {
  match t.view_stands(page) {
    Some((x0, y0, x1, y1, true)) => Ok((x0, y0, x1, y1))
    Some((x0, y0, x1, y1, false)) => Err("hidden at \{x0} \{y0} \{x1} \{y1}")
    None => Err("not placed, or closed")
  }
}

///|
/// `ms` of frames, what the host was asked done as each begins (as a host does it), but a page's view while `held`: its
/// host done drawing it when the test says (Tester::finish).
fn viz_nodes_run(t : @ui.Tester, ms : Double, held : Bool) -> Unit {
  let from = t.time()
  while t.time() - from < ms - 1.0e-6 {
    for p in t.pending() {
      if !(held && p.0 == 2) {
        t.finish(p.0, p.1)
      }
    }
    t.run_for(@ui.frame_period_default)
  }
}

///|
/// Where the message's page is against its words (`t`'s now), on `name`: None where it is in its row, under the words
/// before it and over those after it.
fn viz_nodes_in_row(t : @ui.Tester, name : String, r : (Double, Double, Double, Double)) -> String? {
  let (_, y0, _, y1) = r
  match (t.rect_of("这周的发布节奏："), t.rect_of("流程是这样：")) {
    (Some((_, by, _, bh)), Some((_, ay, _, _))) if by + bh <= y0 + 1.0 && y1 <= ay + 1.0 => None
    (before, after) => Some("\{name}: the page at \{y0}…\{y1}, the words before it \{Repr(before)}, after it \{Repr(after)}")
  }
}

///|
/// Whether the line's grey (whatever its breath's alpha) is drawn over all of `r` in `t`'s frame now.
fn viz_nodes_covered(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool {
  let line = @sf.palette_of(false).line >> 8
  let (x0, y0, x1, y1) = r
  t.drawn_rects().iter().any(fn(d) {
    d.4 >> 8 == line && d.0 <= x0 + 1.0 && d.1 <= y0 + 1.0 && d.0 + d.2 >= x1 - 1.0 && d.1 + d.3 >= y1 - 1.0
  })
}

///|
/// The message's page's frame (viz_frames'), on `name`.
fn viz_nodes_frame(name : String) -> @sfbase.VizFrame raise {
  guard viz_frames.iter().find_first(fn(e) { e.0.has_suffix("/release.html") }) is Some((_, f)) else {
    fail("\{name}: no page made for the message's release.html")
  }
  f
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a placed page in its message, 120 high under its placeholder till it has drawn, then as tall as it says; moved with its row by the wheel, hidden out of sight, not closed" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let asked : Array[String] = []
    let t = viz_nodes_open(w, h, platform, asked)
    let page = viz_nodes_frame(name).view
    assert_eq(asked.filter(fn(a) { a == "station.file" }).length(), 1, msg="\{name}: its file asked once")
    let first = match viz_nodes_shown(t, page) {
      Ok(r) => r
      Err(why) => fail("\{name}: the page not shown at first: \{why}")
    }
    assert_eq(first.3 - first.1, 120.0, msg="\{name}: 120 high till it says")
    assert_eq(viz_nodes_in_row(t, name, first), None)
    assert_true(viz_nodes_covered(t, first), msg="\{name}: its placeholder over it")
    // its height said, its host not done drawing it: still held
    t.view_says(page.id(), "{\"vizMessage\":true,\"type\":\"height\",\"height\":231.4}")
    viz_nodes_run(t, @ui.move_most_ms, true)
    let said = viz_nodes_shown(t, page).unwrap()
    assert_eq(said.3 - said.1, 232.0, msg="\{name}: as tall as it says")
    assert_true(viz_nodes_covered(t, said), msg="\{name}: its placeholder over it till its host has drawn it")
    t.finish(2, page.id())
    viz_nodes_run(t, @ui.move_most_ms, false)
    let drawn = viz_nodes_shown(t, page).unwrap()
    assert_eq(drawn.3 - drawn.1, 232.0, msg=name)
    assert_eq(viz_nodes_in_row(t, name, drawn), None)
    assert_false(viz_nodes_covered(t, drawn), msg="\{name}: nothing over it once drawn")
    let (dx0, dy0, dx1, dy1) = drawn
    assert_true(
      t.holes().iter().any(fn(o) { (o.0 - dx0).abs() < 1.0 && (o.1 - dy0).abs() < 1.0 && (o.0 + o.2 - dx1).abs() < 1.0 && (o.1 + o.3 - dy1).abs() < 1.0 }),
      msg="\{name}: its hole drawn where the host has it, \{dx0} \{dy0} \{dx1} \{dy1}: " + t.holes().map(fn(o) { "\{o.0} \{o.1} \{o.2} \{o.3}" }).join(" | "),
    )
    // read up by the wheel: it goes with its row
    let (_, by, _, _) = t.rect_of("这周的发布节奏：").unwrap()
    t.move_to(w / 2.0, by)
    t.wheel(w / 2.0, by, -150.0)
    viz_nodes_run(t, @ui.move_most_ms, false)
    let up = viz_nodes_shown(t, page).unwrap()
    let (_, by2, _, _) = t.rect_of("这周的发布节奏：").unwrap()
    assert_true(by2 > by, msg="\{name}: read up")
    assert_eq(up.1 - drawn.1, by2 - by, msg="\{name}: moved with its row")
    // far up, out of sight: hidden, not closed
    for _ in 0..<12 {
      t.wheel(w / 2.0, h / 2.0, -400.0)
      viz_nodes_run(t, @ui.move_most_ms, false)
    }
    match t.view_stands(page) {
      Some((_, _, _, _, false)) => ()
      other => fail("\{name}: out of sight, the host has it \{Repr(other)}")
    }
    assert_false(t.views().contains("close \{page.id()}"), msg="\{name}: not closed out of sight")
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a placed page drawn is kept as the chat is left; opened again, the same view shown as it was, in its row, not loaded again" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let asked : Array[String] = []
    let t = viz_nodes_open(w, h, platform, asked, held=false)
    let page = viz_nodes_frame(name).view
    t.view_says(page.id(), "{\"vizMessage\":true,\"type\":\"height\",\"height\":231.4}")
    viz_nodes_run(t, @ui.move_most_ms, false)
    home()
    @ui.came_from_outside()
    viz_nodes_run(t, long_opened_ms, false)
    assert_false(t.views().contains("close \{page.id()}"), msg="\{name}: kept as the chat is left")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    @ui.came_from_outside()
    viz_nodes_run(t, long_opened_ms, false)
    assert_true(physical_equal(viz_nodes_frame(name).view, page), msg="\{name}: the same view")
    assert_eq(asked.filter(fn(a) { a == "station.file" }).length(), 1, msg="\{name}: not loaded again")
    let back = match viz_nodes_shown(t, page) {
      Ok(r) => r
      Err(why) => fail("\{name}: not shown again: \{why}")
    }
    assert_eq(back.3 - back.1, 232.0, msg=name)
    assert_eq(viz_nodes_in_row(t, name, back), None)
    assert_false(viz_nodes_covered(t, back), msg="\{name}: shown as it was, nothing over it")
  }
}
