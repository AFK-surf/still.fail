// A chat's messages made once as nodes (sfpages chat_list_node): from the list's end, its last message over its foot.

///|
test "a chat's messages made once: at their end, the last message over the list's foot" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=700.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(b) {
      b.width(Is(Some(390.0))).height(Is(Some(700.0))) |> ignore
      match workspace_in_view(src).0 {
        Some(w) =>
          @sfpages.chat_list_node(
            b,
            src,
            r,
            fn() { view_of_chat(src, r).0 },
            fn() { view_of_chat(src, r).1 },
            fn() { 0.0 },
            fn() { 0.0 },
            settings_core(src, w),
          )
          |> ignore
        None => ()
      }
    })
    |> ignore
  })
  t.run_for(@ui.move_most_ms)
  match t.find("做完了：列表、跳到最新的按钮") {
    Some((_, y)) => assert_true(y > 500.0 && y < 700.0, msg="\{y}: \{t.words().map(fn(w) { w.0 })}")
    None => fail("not drawn: \{t.words().map(fn(w) { (w.0, w.2) })}")
  }
}
