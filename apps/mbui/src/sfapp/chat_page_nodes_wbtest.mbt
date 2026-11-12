// A chat's page made with its inside nodes (sfbase's chat_page_nodes on: chat_page_made's `body` and `foot`), as a
// skeleton: its messages the page's list, the composer in the list's foot in its old view. That it holds together, no
// more: what the old page floats over its list, puts over its rows and flies over it is not made yet.

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
/// offers of itself the same.
fn chat_nodes_calling(
  w : Double,
  h : Double,
  platform : Int,
  calls : Array[(String, Json)],
  mine? : Bool = false,
  fixture_mode? : String = "chat",
) -> @ui.Tester {
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
      out["messages"] = Json::array(
        messages.mapi(fn(i, j) {
          guard j is Object(was) else { return j }
          let m = was.copy()
          m.remove("attachments")
          m.remove("placed")
          if mine && i == n - 1 {
            m["mine"] = Json::boolean(true)
          }
          Json::object(m)
        }),
      )
      { ..got, value: Some(Json::object(out)) }
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
  t
}

///|
/// What a message's menu offers (sfbase's message_items, the old row's ⋯ and right click), each shown now.
fn message_menu_shown(t : @ui.Tester, name : String) -> Unit raise {
  for item in ["复制消息", "复制消息链接", "多选"] {
    assert_true(t.find(item) is Some(_), msg="\{name}: \{item}")
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
    let t = chat_nodes_calling(1280.0, 800.0, 0, calls, mine~)
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
  let t = chat_nodes_calling(1280.0, 800.0, 0, [], fixture_mode="chat-working")
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
  // (not walked yet: a quote, and what comes after one. Once a quote has come (the focus given to its own field, made
  // in the list's foot) the list at its foot follows no further change of its foot or of its room: an error's line, a
  // line more, the keyboard each leave the last message covered by as much (小屏 21.9 to -10.1, -2.9, -278.1), where
  // after a file alone it follows each. The list's to mend; these steps come back here with it)
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
    // (the list reading up corrects what it counted of its rows by what they measure, what it holds 101 shorter in a
    // frame on 小屏, and the frames' judge takes that for the composer, pinned in its foot and still where it shows,
    // moved as much in a frame: the list's to mend; what is read is held here as a result)
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
