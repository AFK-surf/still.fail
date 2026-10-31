// The edge beside the page on the tape (中屏) in a finger's hand, at its causes: a finger down on it, held, moved, let
// go, as a host hands them on with their own times (no frame between, or frames all along), and a press on what shows
// of the page right after: what each says as of its own moment, whichever frames come.

///|
/// What an edge's run comes to (edge_seen): whether the edge is held as the finger goes down; held once the tree is
/// brought to the hold's end; the sidebar's width after each move; held after the release; the pane in use as the press
/// on the page is let go (no frame after it), and once the tape's move had its while.
priv struct EdgeSeen {
  down : Bool
  held : Bool
  widths : Array[Double]
  after : Bool
  pressed : @sfdesk.TapePane
  rest : @sfdesk.TapePane
} derive(Eq, Show, Debug)

///|
/// 中屏 on the tape (a finger's, 720 wide), the sidebar in use: a finger down on the sidebar's edge at `t0`, held
/// long_press_ms twice over, moved 10 wider each slow_drag_ms six times, let go there; a press on what shows of the
/// page 10 after (down and up then), where the edge reaches over it. Frames each 16 between (`frames`) or none; each
/// read as it is handed on, no frame after it.
fn edge_seen(frames : Bool) -> EdgeSeen raise {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  assert_eq((@sfdesk.wide.tape_at.get(), @sfdesk.wide.side_w.get()), (@sfdesk.TapePane::Side, 240.0))
  let tree = @ui.view_tree().unwrap()
  let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
  // (where the page shows from before: the press after at where it shows from once 60 wider, the same in each run)
  let page_from = covered(t, "收起侧边栏").unwrap().0
  let (sx, _, sw, _) = said_at(t, "调整侧边栏宽度").unwrap()
  let t0 = t.time() + between_frames_ms
  // (to `at`: frames each 16 on the way, or none, the clock there)
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
  t.touch_raw(0, 1, ex, ey, t0)
  let down = @sfdesk.wide.edge_held.get()
  // (the hold's end: the tree brought there, what is due by then done)
  let held_at = t0 + @ui.long_press_ms * 2.0
  to(held_at)
  tree.bring_to(held_at)
  let held = @sfdesk.wide.edge_held.get()
  let widths = []
  for i in 1..=6 {
    let at = held_at + slow_drag_ms * i.to_double()
    to(at)
    t.touch_raw(1, 1, ex + 10.0 * i.to_double(), ey, at)
    widths.push(@sfdesk.wide.side_w.get())
  }
  let up_at = held_at + slow_drag_ms * 7.0
  to(up_at)
  t.touch_raw(2, 1, ex + 60.0, ey, up_at)
  let after = @sfdesk.wide.edge_held.get()
  // (what shows of the page just past the gap where the sidebar now ends, where the edge reaches over it: a press there
  // the page's, as one without the edge would be)
  let press_at = up_at + between_frames_ms
  to(press_at)
  tree.bring_to(press_at)
  // (where the edge reaches over the page once 60 wider: as it was before, 60 on)
  let px = page_from + 60.0 + 1.0
  assert_true(px > sx + 60.0 && px < sx + 60.0 + sw, msg="the press where the edge reaches over the page: \{px} in \{sx + 60.0}+\{sw}")
  t.touch_raw(0, 2, px, ey, press_at)
  t.touch_raw(2, 2, px, ey, press_at)
  let pressed = @sfdesk.wide.tape_at.get()
  t.frame_at(press_at + @ui.move_most_ms * 2.0)
  { down, held, widths, after, pressed, rest: @sfdesk.wide.tape_at.get() }
}

///|
test "中屏: the sidebar's edge on the tape held, dragged and let go by a finger, a press on the page after: each so at its own moment, frames all along or none" {
  let stepped = edge_seen(true)
  let want : EdgeSeen = {
    down: true,
    held: true,
    widths: [250.0, 260.0, 270.0, 280.0, 290.0, 300.0],
    after: false,
    pressed: @sfdesk.TapePane::Page,
    rest: @sfdesk.TapePane::Page,
  }
  let none = edge_seen(false)
  assert_eq(stepped, want, msg="frames all along: \{stepped}; no frame: \{none}")
  assert_eq(none, want, msg="no frame: \{none}")
}

///|
/// 中屏 on the tape (a finger's), the sidebar in use at rest: a press (down and up at `t0`, as a host hands them on) on
/// what shows of the page just past the gap, where the sidebar's edge reaches over it: the pane in use as it is let go
/// (no frame after it), and once the tape's move had its while; frames each 16 before it (`frames`) or none.
fn edge_page_pressed(frames : Bool) -> (@sfdesk.TapePane, @sfdesk.TapePane) raise {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let tree = @ui.view_tree().unwrap()
  let (_, ey) = edge_middle(t, "调整侧边栏宽度")
  let px = covered(t, "收起侧边栏").unwrap().0 + 1.0
  let (sx, _, sw, _) = said_at(t, "调整侧边栏宽度").unwrap()
  assert_true(px > sx && px < sx + sw, msg="the press where the edge reaches over the page: \{px} in \{sx}+\{sw}")
  let t0 = t.time() + between_frames_ms * 6.0
  if frames {
    let mut f = t.time() + 16.0
    while f < t0 {
      t.frame_at(f)
      f = f + 16.0
    }
  }
  t.advance(t0 - t.time())
  tree.bring_to(t0)
  t.touch_raw(0, 1, px, ey, t0)
  t.touch_raw(2, 1, px, ey, t0)
  let pressed = @sfdesk.wide.tape_at.get()
  t.frame_at(t0 + @ui.move_most_ms * 2.0)
  (pressed, @sfdesk.wide.tape_at.get())
}

///|
test "中屏: what shows of the page where the sidebar's edge reaches over it pressed by a finger: the page brought over as it is let go, frames before or none" {
  let want = (@sfdesk.TapePane::Page, @sfdesk.TapePane::Page)
  let stepped = edge_page_pressed(true)
  let none = edge_page_pressed(false)
  assert_eq(stepped, want, msg="frames before: \{stepped}; none: \{none}")
  assert_eq(none, want, msg="none: \{none}")
}

///|
/// 中屏 on the tape (a finger's), the sidebar in use: a finger down on the sidebar's edge where it reaches over the page,
/// swiped across `by` at once (no hold: 10 a move, input_step_ms apart, as a host hands them on), frames between or none:
/// the sidebar's width, which pane is pulled and how far after the moves (no frame after them), and after it is let go
/// and the tape's move had its while: the width, the pane in use, and whether anything of the page was picked.
fn edge_swiped(by : Double, frames : Bool) -> (Double, @sfdesk.TapePane?, Bool, Double, @sfdesk.TapePane, String) raise {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  assert_eq((@sfdesk.wide.tape_at.get(), @sfdesk.wide.side_w.get()), (@sfdesk.TapePane::Side, 240.0))
  let (_, ey) = edge_middle(t, "调整侧边栏宽度")
  let px = covered(t, "收起侧边栏").unwrap().0 + 1.0
  let t0 = t.time() + between_frames_ms
  t.advance(t0 - t.time())
  t.touch_raw(0, 1, px, ey, t0)
  let steps = (by.abs() / 10.0).to_int()
  for i in 1..=steps {
    let at = t0 + @ui.input_step_ms * i.to_double()
    if frames {
      t.frame_at(at - @ui.input_step_ms / 2.0)
    }
    t.advance(at - t.time())
    t.touch_raw(1, 1, px + by / steps.to_double() * i.to_double(), ey, at)
  }
  let width = @sfdesk.wide.side_w.get()
  let pulled = @sfdesk.wide.tape_pull.get()
  let dragged = @sfdesk.wide.tape_drag.get() != 0.0
  let up = t0 + @ui.input_step_ms * (steps + 1).to_double()
  t.advance(up - t.time())
  t.touch_raw(2, 1, px + by, ey, up)
  t.frame_at(up + @ui.move_most_ms * 2.0)
  (width, pulled, dragged, @sfdesk.wide.side_w.get(), @sfdesk.wide.tape_at.get(), @sfbase.pk.ts)
}

///|
test "中屏: a finger swiped across the sidebar's edge on the tape at once, not held first: the edge's width as it was; the page under it pulled, as a swipe there without the edge; nothing picked; frames or none" {
  for frames in [true, false] {
    let (width, pulled, dragged, after, _, picked) = edge_swiped(-80.0, frames)
    assert_eq((width, pulled, dragged, after, picked), (240.0, Some(@sfdesk.TapePane::Page), true, 240.0, ""), msg="frames \{frames}")
  }
}

///|
test "中屏: the sidebar's edge held by a finger, the touch called off by the system: no longer held, its width as it was; the pointer rested on it, its tip shown, then the page brought over: the edge gone, its tip with it" {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
  let t0 = t.time() + between_frames_ms
  t.advance(t0 - t.time())
  t.touch_raw(0, 1, ex, ey, t0)
  assert_true(@sfdesk.wide.edge_held.get(), msg="held as it goes down")
  let off = t0 + @ui.long_press_ms * 2.0
  t.advance(off - t.time())
  t.touch_raw(3, 1, ex, ey, off)
  assert_eq((@sfdesk.wide.edge_held.get(), @sfdesk.wide.side_w.get()), (false, 240.0), msg="called off")
  // (a mouse's, its tip by the pointer)
  let m = tape_chat(0, 720.0, 840.0)
  let (mx, my) = edge_middle(m, "调整侧边栏宽度")
  let tip = fn() { m.semantics().filter(fn(s) { s.role == Tooltip && s.label == "调整侧边栏宽度" }).length() }
  m.move(mx, my)
  m.run_for(@sf.edge_tip_ms * 2.0)
  assert_eq(tip(), 1, msg="its tip shown")
  @ui.view_tree().unwrap().event(m.time(), fn() { @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page)) })
  m.run_for(@ui.move_most_ms * 2.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq((tip(), said_at(m, "调整侧边栏宽度") is None), (0, true), msg="gone with the edge")
}
