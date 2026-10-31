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
test "大屏: folded, shown a while and let go again while it comes: from where it is then, the same whichever frames came between" {
  let peek_then_not = fn() { @sfdesk.wide.peeking.set(false) }
  let shown = fn(frames : Array[Double]) {
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
    t.advance(t0 + 120.0 - t.time())
    bring(t0 + 120.0)
    let was = fold_at(t0 + 120.0)
    peek_then_not()
    bring(t0 + 120.0)
    let from = fold_at(t0 + 120.0)
    t.frame_at(t0 + 400.0)
    (was, from, @sfdesk.pane_seen().map(fn(s) { s.1 }))
  }
  let one = shown([])
  let many = shown([12.0, 30.0, 60.0, 90.0])
  assert_eq(many, one)
  let (was, from, _) = one
  assert_eq(from, was)
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
