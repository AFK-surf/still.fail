///|
test "a message newly uncovered by the composer is read without moving its row" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let foot = @signals.signal(300.0, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=700.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(b) {
      b.width(Is(Some(390.0))).height(Is(Some(700.0))) |> ignore
      match workspace_in_view(src).0 {
        Some(w) => @sfpages.chat_list_node(
          b, src, r, fn() { view_of_chat(src, r).0 }, fn() { 0.0 }, fn() { foot.get() }, settings_core(src, w),
        ) |> ignore
        None => ()
      }
    }) |> ignore
  })
  t.run_for(@ui.move_most_ms)
  t.wheel(195.0, 350.0, -500.0)
  t.run_for(@ui.move_most_ms)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  let (before, at) = (rd.top_seq, rd.top_off)
  // Begin an unread observation with almost all of the original cover still present, then remove it. The second
  // report must advance beyond the messages that were already visible under the first cover.
  rd.seen_whole = -1.0
  foot.set(299.0)
  t.draw()
  let seen_before = rd.seen_whole
  foot.set(0.0)
  t.draw()
  assert_eq((rd.top_seq, rd.top_off), (before, at), msg="the same row remains in place")
  assert_true(rd.seen_whole > seen_before, msg="newly uncovered visible messages are reported: \{seen_before} -> \{rd.seen_whole}")
}
