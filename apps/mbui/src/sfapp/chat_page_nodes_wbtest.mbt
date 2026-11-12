// A chat's page made with its inside nodes (sfbase's chat_page_nodes on: chat_page_made's `body` and `foot`), as a
// skeleton: its messages the page's list, the composer under it in its old view. That it holds together, no more: what
// the old page floats over its list, puts over its rows and flies over it is not made yet.

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
