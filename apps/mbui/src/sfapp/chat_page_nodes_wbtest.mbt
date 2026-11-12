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
