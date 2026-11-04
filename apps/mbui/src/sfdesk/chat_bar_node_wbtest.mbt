///|
test "a station's corner dot keeps the original page-coloured edge" {
  for via in ["direct", "relay", "offline", "waiting"] {
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=100.0, h=100.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(part) {
        part.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
        @ui.old(part, fn(c) {
          c.with_theme(@sf.ui_theme(), fn() {
            c.box(style=corner_dot_of(via), fn() { }) |> ignore
          })
        }).grow(Is(1.0)) |> ignore
      }) |> ignore
      root.box(fn(dot) { chat_via_dot_node(dot, fn() { via }, 10.0, 2.0) }) |> ignore
    })
    t.draw()
    let dots = t.drawn_instances().filter(fn(b) { b[2] == 10.0 && b[3] == 10.0 })
    assert_eq(dots.length(), 2)
    let before = dots.iter().find_first(fn(b) { b[1] < 40.0 }).unwrap()
    let after = dots.iter().find_first(fn(b) { b[1] >= 40.0 }).unwrap()
    // Full and half the short side are the same circle: the renderer bounds the radius by the room.
    assert_eq(if after[4] < 5.0 { after[4] } else { 5.0 }, if before[4] < 5.0 { before[4] } else { 5.0 })
    // The actual kind, fill and edge sent to the renderer, apart from its position and clip.
    assert_eq(Array::makei(11, fn(i) { after[i + 5] }), Array::makei(11, fn(i) { before[i + 5] }))
  }
}
