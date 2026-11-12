// A plan call's checklist in the history (history_steps_node.mbt plan_node), and an agent's in the panel of its work:
// an item long enough to wrap wraps in its own column, at the default size of words and at 1.3.

///|
test "a checklist's long item wraps within its column, never wider than it, at the default size of words and at 1.3" {
  // (a column as wide as the panel of an agent's work holds its checklist: 224)
  let column = 224.0
  let long = "core 的 agentCard 加上后台和清单，再把 web 和 mbui 两边都画出来，截图对照"
  for scale in [1.0, 1.3] {
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=400.0, platform=2)
    if scale != 1.0 {
      t.set_font_scale(scale)
    }
    let list : Array[Json] = [
      { "text": Json::string("读 claude.ts 里的 task 帧"), "status": Json::string("completed") },
      { "text": Json::string(long), "status": Json::string("in_progress") },
      { "text": Json::string("截图"), "status": Json::string("pending") },
    ]
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(b) {
        b.width(Is(Some(column))) |> ignore
        plan_node(b, fn() { list })
      })
      |> ignore
    })
    t.run_for(@ui.move_most_ms)
    let at = "at \{scale}"
    guard t.words().iter().find_first(fn(w) { w.0 == long }) is Some(w) else { fail("\{at}: \{Repr(t.words())}") }
    guard t.words().iter().find_first(fn(w) { w.0 == "截图" }) is Some(one) else { fail(at) }
    // wrapped: more than one line, as high as two of a short item's at least
    assert_true(w.4 >= one.4 * 2.0 - 0.5, msg="\{at}: \{Repr(w)} \{Repr(one)}")
    // within its column: after its mark, ending at the column's end at most
    assert_true(w.1 + w.3 <= column + 0.01, msg="\{at}: \{Repr(w)} past \{column}")
    assert_eq(t.room_faults() + t.tree_room_faults() + t.squeeze_faults(), [], msg=at)
  }
}
