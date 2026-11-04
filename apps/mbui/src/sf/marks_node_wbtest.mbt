///|
test "spokes as nodes: turning step by step, each step woken for; held at the first while motion is reduced, nothing woken for them" {
  for reduced in [false, true] {
    let env = if reduced { [("MBUI_REDUCE_MOTION", "1")] } else { [] }
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=200.0, h=200.0, platform=2, env~)
    @ui.set_view_app(fn(root) { spokes_node(root, 16.0, fn() { 0xF5B800FFL }) |> ignore })
    t.frame()
    let at = "reduced \{reduced}: \{t.wanted_why()}"
    assert_eq(t.wanted_after() == @double.infinity, reduced, msg=at)
  }
}
