// The bar across the top of a file opened over a wide window (viewer_bar), its way back pointed at by a mouse in a
// window 16 round with none of the system's buttons at its left: its hover ground, drawn, in the window's top left
// corner keeps the corner rule, concentric with it as the bar's last tool at its right is; in a square window, as it
// stands alone.

///|
/// The bar's corner faults, its way back pointed at, in a window `corner` round; and whether its hover ground is drawn
/// there then (what is held to the rule: no ground, nothing to hold).
fn back_pointed_faults(corner : Double) -> (Bool, Array[String]) {
  let ink : ViewerInk = {
    ground: 0x222222FFL,
    ink: 0xFFFFFFFFL,
    muted: 0xAAAAAAFFL,
    line: 0x444444FFL,
    hover: 0x2427E70FL,
    chosen: 0x2427E71FL,
  }
  let t = @ui.Tester::new(
    fn(c) { viewer_bar(c, "bar", "整理发布清单", "a.png", "18 KB", false, ink, fn() {  }) |> ignore },
    w=1280.0,
    h=800.0,
    window_corner=corner,
    platform=0,
    corners_held=false,
  )
  t.draw()
  let (x, y, w, h) = t.rect_of("整理发布清单").unwrap()
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.frame()
  let lit = t.drawn_rects().iter().any(fn(r) { r.4 == ink.hover && r.0 <= x && r.1 <= y && r.0 + r.2 >= x + w && r.1 + r.3 >= y + h })
  (lit, t.corner_faults())
}

///|
test "the viewer's bar across the top: its way back pointed at, its hover ground drawn, in a window 16 round keeps the corner rule" {
  let (lit, faults) = back_pointed_faults(16.0)
  assert_eq((lit, faults), (true, []), msg=faults.join("\n"))
}

///|
test "the viewer's bar across the top: its way back pointed at, its hover ground drawn, in a square window keeps the corner rule" {
  let (lit, faults) = back_pointed_faults(0.0)
  assert_eq((lit, faults), (true, []), msg=faults.join("\n"))
}
