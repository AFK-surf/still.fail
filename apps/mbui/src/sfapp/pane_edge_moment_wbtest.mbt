// The sidebar's edge on 大屏 (the frame off the tape's, pane_view) in a mouse's hand, at its causes: down on it, moved,
// let go, as a host hands them on with their own times (no frame between, or frames all along), and pressed without
// moving: what each says as of its own moment, whichever frames come.

///|
/// What the sidebar's edge's run comes to (edge_run): held as it goes down; the sidebar's width after each move; held
/// after it is let go; folded after a press of it let go without moving (no frame after it), and once its move had its
/// while.
priv struct PaneEdgeSeen {
  down : Bool
  widths : Array[Double]
  after : Bool
  folded : Bool
  folded_rest : Bool
} derive(Eq, Show, Debug)

///|
/// 大屏 (1280 wide, a mouse's), the sidebar open at 240: down on its edge at `t0`, moved 10 wider each slow_drag_ms six
/// times, let go there; then down and up on the edge where it is then, without moving, slow_drag_ms after. Frames each
/// 16 between (`frames`) or none; each read as it is handed on, no frame after it.
fn pane_edge_seen(frames : Bool) -> PaneEdgeSeen raise {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  // (each event a mouse's, as the host says it)
  t.host_says_finger(Some(false))
  assert_eq((@sfdesk.wide.folded.get(), @sfdesk.wide.side_w.get()), (false, 240.0))
  let (ex, ey, ew, eh) = t.query(Button, label="调整侧边栏宽度 · 收起侧边栏").unwrap().rect
  let (x, y) = (ex + ew / 2.0, ey + eh / 2.0)
  let t0 = t.time() + between_frames_ms
  let to = fn(at : Double) {
    if frames {
      let mut f = t.time() + 16.0
      while f < at {
        t.frame_at(f)
        f = f + 16.0
      }
    }
    t.advance(at - t.time())
  }
  to(t0)
  t.touch_at(0, x, y, t0)
  assert_true(@ui.pointing() is Mouse, msg="a mouse's")
  let down = @sfdesk.wide.edge_held.get()
  let widths = []
  for i in 1..=6 {
    let at = t0 + slow_drag_ms * i.to_double()
    to(at)
    t.touch_at(1, x + 10.0 * i.to_double(), y, at)
    widths.push(@sfdesk.wide.side_w.get())
  }
  let up_at = t0 + slow_drag_ms * 7.0
  to(up_at)
  t.touch_at(2, x + 60.0, y, up_at)
  let after = @sfdesk.wide.edge_held.get()
  // (pressed where the edge is once 60 wider, without moving)
  let press_at = up_at + slow_drag_ms
  to(press_at)
  t.touch_at(0, x + 60.0, y, press_at)
  t.touch_at(2, x + 60.0, y, press_at)
  let folded = @sfdesk.wide.folded.get()
  t.frame_at(press_at + @ui.move_most_ms * 2.0)
  { down, widths, after, folded, folded_rest: @sfdesk.wide.folded.get() }
}

///|
test "大屏: the sidebar's edge held, dragged and let go by a mouse, then pressed: each so at its own moment, frames all along or none" {
  let want : PaneEdgeSeen = {
    down: true,
    widths: [250.0, 260.0, 270.0, 280.0, 290.0, 300.0],
    after: false,
    folded: true,
    folded_rest: true,
  }
  let stepped = pane_edge_seen(true)
  let none = pane_edge_seen(false)
  assert_eq(stepped, want, msg="frames all along: \{stepped}; no frame: \{none}")
  assert_eq(none, want, msg="no frame: \{none}")
}

///|
test "大屏: the sidebar's list's thumb shown where the edge's strip is: a mouse's press there the thumb's (the list scrolled, the sidebar's width as it was, the edge not in hand)" {
  let t = wide_tester([], h=360.0)
  t.draw()
  t.wheel(160.0, 250.0, 120.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let (ex, ey, ew, eh) = t.query(Button, label="调整侧边栏宽度 · 收起侧边栏").unwrap().rect
  guard side_thumb(t) is Some((tx, ty, tw, th, _)) else { fail("no thumb") }
  // (a point of both: within the thumb as the pointer takes it (ui's scroll_bar_grab, 4, round it) and the edge's strip)
  let g = 4.0
  let x0 = if tx - g > ex { tx - g } else { ex }
  let x1 = if tx + tw + g < ex + ew { tx + tw + g } else { ex + ew }
  assert_true(x1 > x0 && ty + th / 2.0 > ey && ty + th / 2.0 < ey + eh, msg="thumb \{(tx, ty, tw, th)} edge \{(ex, ey, ew, eh)}")
  let (px, py) = ((x0 + x1) / 2.0, ty + th / 2.0)
  let before = t.list_offset()
  t.move(px, py)
  t.run_for(@ui.scrollbar_fade_ms)
  t.press_at(px, py)
  for i in 1..=4 {
    t.move(px, py + 10.0 * i.to_double())
    t.run_for(@ui.drag_step_ms)
  }
  t.release(px, py + 40.0)
  t.frame()
  assert_true(t.list_offset() > before, msg="the list scrolled: \{before} to \{t.list_offset()}")
  assert_eq((@sfdesk.wide.side_w.get(), @sfdesk.wide.edge_held.get(), @sfdesk.wide.folded.get()), (240.0, false, false))
}
