// The sidebar's edge on 大屏 (pane_view) as what it is said to be: pressed by the keyboard and a screen reader once a
// press; folded, a button's (its pointer, read out, the focus); its hold called off or its node gone, the sidebar as
// the hold left it, nothing of what followed it the edge's.

///|
/// The sidebar's edge as read out now (a button 12 across, saying what a press of it does), none where it is not.
fn side_edge(t : @ui.Tester) -> @ui.SemNode? {
  let words = [
    @sf.t("web-pages.workspace.resizeSidebar") + " · " + @sf.t("web-main.sidebar.close"),
    @sf.t("web-main.sidebar.open"),
  ]
  t
  .semantics()
  .iter()
  .find_first(fn(s) { s.role == Button && words.contains(s.label) && s.rect.2 == @ui.Space::px(S3) })
}

///|
/// The middle of the sidebar's edge.
fn side_edge_at(t : @ui.Tester) -> (Double, Double) raise {
  guard side_edge(t) is Some(s) else { fail("no edge") }
  let (x, y, w, h) = s.rect
  (x + w / 2.0, y + h / 2.0)
}

///|
test "大屏: the sidebar's edge with the focus: Enter, Space and a screen reader's Activate each fold or open the sidebar once, at its moment" {
  let t = wide_tester([])
  t.draw()
  guard side_edge(t) is Some(s) else { fail("no edge") }
  @ui.current().ask_action(s.id, Focus)
  t.draw()
  assert_eq(t.focused().map(fn(f) { f.id }), Some(s.id), msg="the edge has the focus")
  let tree = @ui.view_tree().unwrap()
  let edge = tree.focused_now().0
  assert_true(edge is Some(_), msg="the tree's focus on a node")
  // (folded, the focus where it is: as each is told, no frame after it; then once its frame is drawn)
  let seen = []
  let look = fn() { (@sfdesk.wide.folded.get(), tree.focused_now().0 == edge) }
  t.key_told(@ui.key_code_enter, 0, t.time())
  seen.push(look())
  t.draw()
  seen.push(look())
  t.key_told(@ui.key_space, 0, t.time())
  seen.push(look())
  t.draw()
  seen.push(look())
  @ui.current().ask_action(s.id, Activate)
  seen.push(look())
  t.draw()
  seen.push(look())
  assert_eq(seen, [(true, true), (true, true), (false, true), (false, true), (true, true), (true, true)])
  // (read out with the focus, its words what a press does now)
  assert_eq(t.focused().map(fn(f) { f.label }), Some(@sf.t("web-main.sidebar.open")))
}

///|
test "大屏: the sidebar's edge folded: the hand, as what takes presses, read out as a button that opens it, taking the focus; open, the resizing pointer" {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  let (x, y) = side_edge_at(t)
  t.move(x, y)
  t.frame()
  let open = t.cursor()
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms * 2.0)
  guard side_edge(t) is Some(s) else { fail("no edge folded") }
  let (fx, fy) = side_edge_at(t)
  t.move(fx, fy)
  t.frame()
  let folded = t.cursor()
  @ui.current().ask_action(s.id, Focus)
  t.draw()
  assert_eq(
    (open, folded, s.label, s.actions.contains(Activate), t.focused().map(fn(f) { f.id })),
    (ResizeX, Hand, @sf.t("web-main.sidebar.open"), true, Some(s.id)),
  )
}

///|
/// 大屏, the sidebar `folded` or not, a mouse's: down on its edge, moved 20 wider, `off` (calling the hold off or
/// taking its node away), then moved 20 more and let go there, then `back` (as it was again). The sidebar's width and
/// whether folded and its edge held, as it was called off and once let go after.
fn side_edge_off(
  folded : Bool,
  off : (@ui.Tester) -> Unit,
  back : (@ui.Tester) -> Unit,
) -> ((Double, Bool, Bool), (Double, Bool, Bool)) raise {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  if folded {
    @sfdesk.wide.folded.set(true)
  }
  t.run_for(@ui.move_most_ms * 2.0)
  let (x, y) = side_edge_at(t)
  let seen = fn() { (@sfdesk.wide.side_w.get(), @sfdesk.wide.folded.get(), @sfdesk.wide.edge_held.get()) }
  t.touch_at(0, x, y, t.time())
  t.advance(slow_drag_ms)
  t.touch_at(1, x + 20.0, y, t.time())
  off(t)
  let as_off = seen()
  t.advance(slow_drag_ms)
  t.touch_at(1, x + 40.0, y, t.time())
  t.advance(slow_drag_ms)
  t.touch_at(2, x + 40.0, y, t.time())
  back(t)
  (as_off, seen())
}

///|
test "大屏: the sidebar's edge held and dragged, the window put out of front: called off as the sidebar was, nothing after it the edge's" {
  let off = fn(t : @ui.Tester) { t.app_state(true, false) }
  let back = fn(t : @ui.Tester) { t.app_state(true, true) }
  assert_eq(side_edge_off(false, off, back), ((260.0, false, false), (260.0, false, false)))
  // (folded: its moves nothing, its end no press)
  assert_eq(side_edge_off(true, off, back), ((240.0, true, false), (240.0, true, false)))
}

///|
test "大屏: the sidebar's edge held and dragged, the window narrowed to 中屏 under it: the hold gone with it, nothing after it the edge's" {
  let off = fn(t : @ui.Tester) { t.resize(700.0, 800.0) }
  let back = fn(t : @ui.Tester) { t.resize(1280.0, 800.0) }
  assert_eq(side_edge_off(false, off, back), ((260.0, false, false), (260.0, false, false)))
  assert_eq(side_edge_off(true, off, back), ((240.0, true, false), (240.0, true, false)))
}

///|
test "大屏: the sidebar's edge pressed by a mouse and held long where it went down, let go there: a press of it (the sidebar folded), frames all along or none" {
  let seen = []
  for frames in [true, false] {
    let t = wide_tester([])
    t.host_says_finger(Some(false))
    t.run_for(@ui.move_most_ms * 2.0)
    let (x, y) = side_edge_at(t)
    let t0 = t.time() + between_frames_ms
    t.advance(t0 - t.time())
    t.touch_at(0, x, y, t0)
    let up_at = t0 + @ui.long_press_ms * 2.0
    if frames {
      let mut f = t.time() + 16.0
      while f < up_at {
        t.frame_at(f)
        f = f + 16.0
      }
    }
    t.advance(up_at - t.time())
    t.touch_at(2, x, y, up_at)
    seen.push((@sfdesk.wide.folded.get(), @sfdesk.wide.edge_held.get(), @sfdesk.wide.side_w.get()))
  }
  assert_eq(seen, [(true, false, 240.0), (true, false, 240.0)])
}

///|
test "大屏: the sidebar's edge pressed by a mouse and let go far from there, no move told and no frame between: the drag's end (the width where it was let go, not folded), across it or along it" {
  let seen = []
  for to in [(60.0, 0.0), (0.0, 100.0)] {
    let t = wide_tester([])
    t.host_says_finger(Some(false))
    t.run_for(@ui.move_most_ms * 2.0)
    let (x, y) = side_edge_at(t)
    let t0 = t.time() + between_frames_ms
    t.advance(t0 - t.time())
    t.touch_at(0, x, y, t0)
    t.advance(slow_drag_ms)
    t.touch_at(2, x + to.0, y + to.1, t0 + slow_drag_ms)
    seen.push((@sfdesk.wide.side_w.get(), @sfdesk.wide.folded.get(), @sfdesk.wide.edge_held.get()))
  }
  assert_eq(seen, [(300.0, false, false), (240.0, false, false)])
}
