// A chat's page made with its inside nodes (sfbase's chat_page_nodes on) as what the page is, not as it was made: a
// new chat become its chat in place (its first words sent) the new page from then, its old view let go; an agent's
// history, a service and a file asked as pages on 中屏 and 大屏 their chat's new page beside them, no old page built.

///|
/// The fixture's Home with chat_page_nodes as `nodes` says, `w` by `h` on `platform`.
fn made_tester(w : Double, h : Double, platform : Int, nodes : Bool) -> (@ui.Tester, Source) {
  new_run()
  @sfbase.chat_page_nodes.set(nodes)
  let src = fixture("home")
  (@ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~), src)
}

///|
/// A new chat opened (小屏: 令 tapped; 大屏: the page it lands on), `words` typed in it and sent; then as long as the
/// words take to land and the new chat's scene to leave. The chat it became.
fn made_new_chat_sent(t : @ui.Tester, small : Bool, words : String) -> ChatRef raise {
  if small {
    let (_, y) = bar_places_at()
    t.tap(195.0, y - 28.0 - 4.0)
  }
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is NewChat)
  t.tap_text("做任何事")
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.draw()
  guard app.nav.top() is Chat(r) else { fail("not become the chat") }
  t.run_for(new_leave_ms + flight_carry_after_ms + flight_carry_ms + @ui.move_most_ms)
  r
}

///|
/// Where words `s` are seen furthest right (the chat's own page's, right of a list beside it): their middle.
fn made_words_at(t : @ui.Tester, s : String) -> (Double, Double)? {
  let mut at : (Double, Double, Double, Double)? = None
  for w in t.words() {
    if w.0.contains(s) && w.5 > 0.5 && w.3 > 0.0 && (at is None || w.1 > at.unwrap().0) {
      at = Some((w.1, w.2, w.3, w.4))
    }
  }
  at.map(fn(a) { (a.0 + a.2 / 2.0, a.1 + a.3 / 2.0) })
}

///|
/// Whether words `s` are drawn (last) by the chat's new page: by a node of the window's tree made in its messages'
/// nodes (sfpages' chat_page_node, chat_body_node), which the old page has none of (its words an old view's, drawn by
/// what hosts it, not by the tree: Tester::sources_of).
fn made_by_nodes(t : @ui.Tester, s : String) -> Bool {
  let said = t.sources_of(s)
  said.contains("sfpages/chat_page_node.mbt") || said.contains("sfpages/chat_body_node.mbt")
}

///|
/// Whether an old view's list (Ctx::list, which only the old page's messages are) has a row over (x, y).
fn made_old_row_at(t : @ui.Tester, x : Double, y : Double) -> Bool {
  t.old_list_row_boxes().iter().any(fn(rows) { rows.iter().any(fn(b) { x >= b.0 && x < b.0 + b.2 && y >= b.1 && y < b.1 + b.3 }) })
}

///|
/// The lowest field drawn (the composer's).
fn made_composer_field(t : @ui.Tester) -> (Double, Double, Double, Double)? {
  let mut field : (Double, Double, Double, Double)? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && (field is None || field.unwrap().1 < s.rect.1) {
      field = Some(s.rect)
    }
  }
  field
}

///|
test "a new chat become its chat, on 小屏 and 大屏, with its inside nodes: the new page from then, what was sent a message of its list, the composer empty and taking what is typed, no old list" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let (t, src) = made_tester(w, h, platform, true)
    let words = "看下进度"
    let r = made_new_chat_sent(t, name == "小屏", words)
    guard made_words_at(t, words) is Some((x, y)) else { fail("\{name}: what was sent not seen") }
    assert_true(made_by_nodes(t, words), msg="\{name}: not the new page's: \{t.sources_of(words)}")
    assert_false(made_old_row_at(t, x, y), msg="\{name}: an old list's row under what was sent")
    // the composer there, empty, taking what is typed (the chat's draft, sfbase's writing, as the page reads it: by the
    // source it keeps, page_source_for_chat; a draft of another source is another's, writing_follow_wbtest)
    let draft = r.station + ":" + r.session
    let page = @sfbase.page_source_for_chat(src, r)
    assert_false(physical_equal(page, src), msg="\{name}: no page reads the chat")
    assert_eq(@sfbase.writing(page, draft).text.get(), "", msg="\{name}: the composer not empty")
    // (by its hint, as a hand finds it)
    t.tap_text("发消息")
    t.run_for(@ui.move_most_ms)
    t.type_text("先看第三项")
    t.run_for(@ui.move_most_ms)
    assert_eq(
      @sfbase.writing(page, draft).text.get(),
      "先看第三项",
      msg="\{name}: the host's field \{Repr(t.ime())}, the core's draft \{@sfbase.writing(src, draft).text.get()}",
    )
    guard made_composer_field(t) is Some((nx, ny, nw, nh)) else { fail("\{name}: no composer's field once typed in") }
    let typed = t.text_runs().filter(fn(run) { run.text.contains("先看第三项") })
    assert_true(
      typed.iter().any(fn(run) { run.top < ny + nh && run.bottom > ny && run.x0 >= nx && run.x0 < nx + nw }),
      msg="\{name}: what is typed not drawn in the field at \{Repr((nx, ny, nw, nh))}",
    )
    // what was sent still the new page's message
    assert_true(made_by_nodes(t, words), msg="\{name}: not the new page's once typed")
  }
}

///|
test "a new chat become its chat, on 小屏 and 大屏, chat_page_nodes off: the old page, as before" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = screen
    let (t, _) = made_tester(w, h, platform, false)
    let words = "看下进度"
    made_new_chat_sent(t, name == "小屏", words) |> ignore
    assert_true(made_words_at(t, words) is Some(_), msg="\{name}: what was sent not seen")
    assert_false(made_by_nodes(t, words), msg="\{name}: the new page's with the switch off")
  }
}

///|
test "大屏, an agent's history asked as a page with its inside nodes: its chat the new page" {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(older_history(4)), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="the page its chat's")
  let last = "做完了：列表、跳到最新的按钮"
  assert_true(made_words_at(t, last) is Some(_), msg="its last message not seen")
  assert_true(made_by_nodes(t, last), msg="not the new page's: \{t.sources_of(last)}")
}

///|
/// `mode`'s fixture, the history its agent's read as `older_history(4)` (what the history beside it shows), its chat
/// opened, `w` by `h`, chat_page_nodes as `nodes` says; after the chat's page has come. The chat.
fn made_beside_tester(mode : String, w : Double, h : Double, nodes : Bool) -> (@ui.Tester, Source, ChatRef) {
  new_run()
  @sfbase.chat_page_nodes.set(nodes)
  let base = fixture(mode)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(older_history(4)), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=0)
  t.run_for(@ui.move_most_ms)
  (t, src, r)
}

///|
/// `p` opened (as a link or a row of the chat's opens it: open_page) on Tester `t`, as long as a page takes to come:
/// how many of the frames drawn from then had an old view's list's rows (the old chat page's messages: the only
/// Ctx::list on the chats' place of 中屏 and 大屏).
fn made_old_frames_opening(t : @ui.Tester, p : Page) -> Int {
  let old = Ref(0)
  t.each_frame(Some(fn() { if t.old_list_row_boxes().iter().any(fn(l) { l.length() > 0 }) { old.val += 1 } }))
  open_page(p)
  t.run_for(@ui.move_most_ms)
  t.each_frame(None)
  old.val
}

///|
test "中屏 and 大屏, a chat's detail asked as a page (its agent's history, a service, a file) builds no old chat page from the frame it is opened: its chat the new page, it beside it in front, back where it went" {
  let file = @sfdesk.file_tab("s-c1", "work/s-c1/release.html", "release.html")
  let r0 : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let cases : Array[(String, Page, String, Bool)] = [
    ("chat", History(r0, "s-c1", None), "s-c1", false),
    ("chat-info", Service("ws1/st1", "j-web"), "service:j-web", true),
    ("chat-viz", PreviewFile("ws1/st1", "s-c1", "work/s-c1/release.html", "release.html"), file, true),
  ]
  for screen in [("大屏", 1280.0, 800.0), ("中屏", 720.0, 800.0)] {
    let (name, w, h) = screen
    for case in cases {
      let (mode, p, tab, under) = case
      let (t, src, r) = made_beside_tester(mode, w, h, true)
      let before = app.nav.pages()
      let old = made_old_frames_opening(t, p)
      let what = name + " " + @sfbase.page_kind(p)
      assert_eq(old, 0, msg="\{what}: frames with the old chat page's list")
      guard app.nav.top() is Chat(c) && c.station == r.station && c.session == r.session else {
        fail("\{what}: the page not its chat's: \{@sfbase.page_kind(app.nav.top())}")
      }
      assert_eq(@sfdesk.side_now(src, r).1, tab, msg="\{what}: not in front beside it")
      // (back where it went as before: to the chat it was asked from where it is that chat's, its own; else to that)
      let pages = app.nav.pages()
      assert_eq(pages.length(), before.length() + (if under { 0 } else { 1 }), msg="\{what}: \{Repr(pages.map(@sfbase.page_kind))}")
      for k, b in before {
        assert_true(pages[k] == b, msg="\{what}: under it \{Repr(pages.map(@sfbase.page_kind))}, was \{Repr(before.map(@sfbase.page_kind))}")
      }
      let last = "做完了：列表、跳到最新的按钮"
      assert_true(made_by_nodes(t, last), msg="\{what}: not the new page's: \{t.sources_of(last)}")
    }
  }
  // (what is read sees an old chat page where one is built: the switch off, the chat's page the old one)
  let (t, _, _) = made_beside_tester("chat", 1280.0, 800.0, false)
  assert_true(made_old_frames_opening(t, History(r0, "s-c1", None)) > 0, msg="the old chat page not seen")
}
