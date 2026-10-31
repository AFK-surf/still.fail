// The wide frame off the tape as nodes of the window's tree (sfdesk's pane_view.mbt): its shell, row, column and page
// made once; the block's move committed at its cause, set out from where the move before had it then, whatever frames
// were drawn between; the tape left mid-move for a place with no sidebar of its own, the block closing from where the
// tape had it then.

///|
/// Where the block's move has it at `at` (how far across, the column), as committed.
fn fold_at(at : Double) -> (Double, Double) {
  @sfdesk.pane_fold_at(at).unwrap_or((-1.0, -1.0))
}

///|
/// The tree brought to `at` (what was told by then committed, at its moment).
fn bring(at : Double) -> Unit {
  match @ui.view_tree() {
    Some(tree) => tree.bring_to(at)
    None => ()
  }
}

///|
/// The sidebar folded (⌘\'s state) at `t0 + 10` between frames, `then` at `t0 + 120` while the block goes (opened
/// again, or shown a while), each told between frames; frames drawn at `t0 +` each of `frames` between: the column at
/// `t0 + 400`; where the move to the bar had the block at `t0 + 120` and where the next sets out from then.
fn pane_turned(frames : Array[Double], then : () -> Unit) -> (Double, (Double, Double), (Double, Double)) {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let t0 = t.time()
  t.advance(between_frames_ms)
  @sfdesk.wide.folded.set(true)
  for f in frames {
    if f < 120.0 {
      t.frame_at(t0 + f)
    }
  }
  t.advance(t0 + 120.0 - t.time())
  bring(t0 + 120.0)
  let was = fold_at(t0 + 120.0)
  then()
  bring(t0 + 120.0)
  let from = fold_at(t0 + 120.0)
  for f in frames {
    if f > 120.0 {
      t.frame_at(t0 + f)
    }
  }
  t.frame_at(t0 + 400.0)
  match @sfdesk.pane_seen() {
    Some((_, col)) => (col, was, from)
    None => (-1.0, was, from)
  }
}

///|
test "大屏: the sidebar folded and opened again while the block goes: from where it is then, the same at a moment whichever frames came between" {
  let reopen = fn() { @sfdesk.wide.folded.set(false) }
  let one = pane_turned([], reopen)
  let many = pane_turned([12.0, 20.0, 40.0, 70.0, 100.0, 150.0, 210.0, 300.0], reopen)
  let late = pane_turned([115.0, 390.0], reopen)
  assert_eq((many, late), (one, one))
  let (col, was, from) = one
  // (set out back from where the fold had the block at that moment, its column on its way between)
  assert_eq(from, was)
  assert_true(was.1 > @sfdesk.rail_w && was.1 < col, msg="at the turn \{was}, open \{col}")
}

///|
/// Where the block is drawn across and how wide (its box: the dock's).
fn dock_drawn(t : @ui.Tester) -> (Double, Double) {
  match t.boxes().iter().find_first(fn(b) { b.moves == "dock" }) {
    Some(b) => (b.x, b.w)
    None => (-1.0, -1.0)
  }
}

///|
/// Folded and at rest; shown a while at `t0 + 10`, let go again at `t0 + 120` while it comes (each told between
/// frames), frames at `t0 +` each of `frames` (before 120) between: how wide the block was drawn at `t0 + 120`; where
/// the move had its right margin, the page's move aside, the edge and the sidebar shown then and where the next sets
/// out from; how wide it is drawn at `t0 + 700`.
fn pane_peek_let_go(frames : Array[Double]) -> (Double, (Double, Double, Double, Double)?, (Double, Double, Double, Double)?, Double) {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  let t0 = t.time()
  t.advance(between_frames_ms)
  @sfdesk.wide.peeking.set(true)
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 120.0)
  let mid = dock_drawn(t).1
  bring(t0 + 120.0)
  let was = @sfdesk.pane_reach_at(t0 + 120.0)
  @sfdesk.wide.peeking.set(false)
  bring(t0 + 120.0)
  let from = @sfdesk.pane_reach_at(t0 + 120.0)
  t.frame_at(t0 + 700.0)
  (mid, was, from, dock_drawn(t).1)
}

///|
test "大屏: folded, shown a while and let go again while it comes: the block drawn between the two, set back from where it is then, the same whichever frames came between" {
  // the two ends: folded at rest, shown a while at rest
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  let folded = dock_drawn(t).1
  // (shown a while, the block reaches past its column as far as the sidebar is wide: its right margin less it)
  let shown = folded + @sfdesk.wide.side_w.get()
  let one = pane_peek_let_go([])
  let many = pane_peek_let_go([12.0, 30.0, 60.0, 90.0, 110.0])
  assert_eq(many, one)
  let (mid, was, from, end) = one
  // (on its way out at the turn: drawn between folded and shown; the move back set out from where it was then)
  assert_true(mid > folded + 0.5 && mid < shown - 0.5, msg="at the turn \{mid}, folded \{folded}, shown \{shown}")
  assert_eq(from, was)
  assert_eq(end, folded)
}

///|
/// Folded and at rest; at moments of the tree's timeline (View::at_moment, each done as of its own moment): opened at
/// `t0 + 10`, the sidebar 40 wider at `t0 + 100` (no cause of a move: put where it goes), folded again at `t0 + 200`
/// while it opens. `stepping`: frames all along; else the host's clock straight on to `t0 + 900`, past where the
/// opening would have ended, what is due done there in its order. Where the folding back set out from (at `t0 + 200`),
/// where it has the block at `t0 + 900`, how wide the block is drawn then.
fn pane_dues(stepping : Bool) -> ((Double, Double)?, (Double, Double)?, Double) {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  let t0 = t.time()
  let n = @sfdesk.pane_node().unwrap()
  n.at_moment(t0 + 10.0, fn() { @sfdesk.wide.folded.set(false) }) |> ignore
  n.at_moment(t0 + 100.0, fn() { @sfdesk.wide.side_w.set(@sfdesk.wide.side_w.get() + 40.0) }) |> ignore
  n.at_moment(t0 + 200.0, fn() { @sfdesk.wide.folded.set(true) }) |> ignore
  if stepping {
    let mut f = 16.0
    while f < 900.0 {
      t.frame_at(t0 + f)
      f = f + 16.0
    }
  } else {
    // (the host's clock on to t0 + 900 at once, the tree brought there between frames: what is due done in its order,
    // each as of its own moment, the host's now past them all)
    t.advance(t0 + 900.0 - t.time())
    bring(t0 + 900.0)
  }
  t.frame_at(t0 + 900.0)
  (@sfdesk.pane_fold_from(), @sfdesk.pane_fold_at(t0 + 900.0), dock_drawn(t).1)
}

///|
test "大屏: what is due on the timeline done as of its own moment, the host's clock on past it or not: the fold back from the same place, the same at a moment" {
  let stepped = pane_dues(true)
  let jumped = pane_dues(false)
  assert_eq(jumped, stepped)
}

///|
test "大屏: its shell, row, column and page made once: the same nodes as the sidebar folds, is shown a while and opens" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let ids = @sfdesk.pane_seen().unwrap().0
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.pane_seen().unwrap().0, ids)
  @sfdesk.wide.peeking.set(true)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.pane_seen().unwrap().0, ids)
  @sfdesk.wide.peeking.set(false)
  @sfdesk.wide.folded.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.pane_seen().unwrap().0, ids)
}

///|
/// On the tape, the page brought over at `t0 + 10` and 用量 gone to at `t0 + 100` while the tape goes (the frame off the
/// tape made then): where the tape had its block then (how far across, its column) and where the block's close sets out
/// from.
fn tape_left_for_usage(t : @ui.Tester) -> ((Double, Double), (Double, Double)) {
  let t0 = t.time()
  t.advance(between_frames_ms)
  @sfdesk.bring_page()
  t.frame_at(t0 + 40.0)
  t.advance(t0 + 100.0 - t.time())
  bring(t0 + 100.0)
  let (x, _) = @sfdesk.tape_along_at(t0 + 100.0)
  let col = match @sfdesk.tape_seen() {
    Some((_, _, _)) => @sfdesk.tape_col_now(t0 + 100.0)
    None => -1.0
  }
  @sfbase.go_place("usage") |> ignore
  bring(t0 + 100.0)
  ((x, col), fold_at(t0 + 100.0))
}

///|
test "中屏 to 用量 while the tape goes: the block closes from where the tape had it then; and again after the tape again" {
  let t = tape_chat(0, 720.0, 840.0)
  let (tape, from) = tape_left_for_usage(t)
  assert_false(@sfdesk.wide.tape)
  assert_eq(from, tape)
  // back to the chats (the tape again), the page brought over again, and 用量 once more mid-way: the same from there
  t.run_for(@ui.move_most_ms)
  @sfbase.go_place("chats") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.tape)
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Side))
  t.run_for(@ui.move_most_ms)
  let (tape, from) = tape_left_for_usage(t)
  assert_false(@sfdesk.wide.tape)
  assert_eq(from, tape)
}
