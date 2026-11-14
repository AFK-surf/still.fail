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

///|
test "OpenCode's mark as a node: its frame, half as wide as its size and two thirds as high, edged 1.5 in the words' colour" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=100.0, h=100.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.lines_up(Is(Some(Start))) |> ignore
    provider_logo_node(root, "claude", "opencode-go", 24.0, "") |> ignore
  })
  t.draw()
  assert_eq(edge_round(t, 12.0, 12.0), (1.5, @ui.tree_theme().color(Fg)))
}

///|
/// The edge drawn round (x, y) (its width, its colour RRGGBBAA), of the least rect drawn there with one: none, (0, 0).
fn edge_round(t : @ui.Tester, x : Double, y : Double) -> (Double, Int64) {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  let mut best : (Double, Double, Int64)? = None
  for a in t.drawn_instances() {
    if a[5] == 0.0 && a[6] > 0.0 && a[15] > 0.0 && x >= a[0] && x <= a[0] + a[2] && y >= a[1] && y <= a[1] + a[3] {
      let color = (ch(a[12]) << 24) | (ch(a[13]) << 16) | (ch(a[14]) << 8) | ch(a[15])
      match best {
        Some((area, _, _)) if area <= a[2] * a[3] => ()
        _ => best = Some((a[2] * a[3], a[6], color))
      }
    }
  }
  match best {
    Some((_, w, c)) => (w, c)
    None => (0.0, 0L)
  }
}
