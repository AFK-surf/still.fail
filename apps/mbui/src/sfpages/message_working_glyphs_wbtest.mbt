// An agent at work's line as nodes (message_working_node.mbt's working_words_node) set beside the old view's
// (chat_rows.mbt steady_words, activity_change_glyphs, activity_glyphs) on the same fixture and the same steps said by
// the core: its first words coming in; a step giving way to a longer one, a shorter one, one of as many glyphs, one in
// the monospaced face; several said one after another quicker than the line shows them; narrow, and at 1.3. At each
// moment declared from the one the step began showing (its start, on its way, its end, after it), each glyph drawn
// (where, how big, how opaque), the words and the clock where they are. The old view's step began at the frame that
// saw it said; the nodes' at the moment it was said: each is read from its own start, and how far apart the two are
// is held (none but a frame of the rate). Harness: message_working_node_wbtest's.

///|
/// What the row at `t` draws now: each glyph (where, how big, how opaque, to a hundredth; none of those not seen), then
/// each of its words (the clock with them).
fn glyphs_drawn(t : @ui.Tester) -> String {
  let r = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let glyphs = t
    .drawn_instances_keyed()
    .filter(fn(a) { a[5] == 1.0 && a[11] >= 0.005 })
    .map(fn(a) { "\{r(a[0])},\{r(a[1])} \{r(a[2])}x\{r(a[3])} a\{r(a[11])}" })
  let words = t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{r(w.5)}" })
  glyphs.join("\n") + "\n--\n" + words.join("\n")
}

///|
/// A line glyphs_drawn says, cut in three: what it is (a glyph: none; words: theirs and `@`), how far across, and how
/// far down and the rest.
fn glyphs_line_parts(l : String) -> (String, String, String) {
  let at = match l.rev_find("@") {
    Some(i) => i + 1
    None => 0
  }
  let head = l.exact_view(end=at).to_owned()
  let rest = l.exact_view(start=at).to_owned()
  match rest.find(",") {
    Some(c) => (head, rest.exact_view(end=c).to_owned(), rest.exact_view(start=c + 1).to_owned())
    None => (head, rest, "")
  }
}

///|
/// What glyphs_drawn says, but where down each is: across, how big, how opaque.
fn glyphs_across(drawn : String) -> String {
  let lines : Array[String] = []
  for l in drawn.split("\n") {
    let (head, x, rest) = glyphs_line_parts(l.to_owned())
    let size = match rest.find(" ") {
      Some(sp) => rest.exact_view(start=sp).to_owned()
      None => ""
    }
    lines.push(head + x + size)
  }
  lines.join("\n")
}

///|
/// Whether each of the line's words in what glyphs_drawn says is as far down as its clock (`1m 5s`).
fn glyphs_level(drawn : String) -> Bool {
  let down = fn(l : String) {
    let (_, _, rest) = glyphs_line_parts(l)
    match rest.find(" ") {
      Some(sp) => rest.exact_view(end=sp).to_owned()
      None => rest
    }
  }
  let words : Array[String] = []
  let mut past = false
  for l in drawn.split("\n") {
    if l == "--" {
      past = true
    } else if past {
      words.push(l.to_owned())
    }
  }
  let clock = words.filter(fn(l) { l.has_prefix("1m 5s@") })
  clock.length() == 1 && words.iter().all(fn(l) { down(l) == down(clock[0]) })
}

///|
/// The fixture's agent's row as the old view draws it (activity_row out of a list, steadied as row `rk`: three letters,
/// so that its glyphs' noise is the nodes' row's, `act:s-c1`), come into its list as `came` says as it changes.
fn glyphs_old(w : Double, src : Source, rk : String, came : @signals.Signal[Double?]) -> @ui.Tester {
  let view = work_view([work_agent_json()])
  dec_old(w, view, fn(c, here) {
    row_box(c, row_side(w), 0.0, fn() {
      activity_row(c, src, here, view.agents[0], @sfbase.emits_of("glyphs-test"), rk, false, came.get())
    })
    |> ignore
  })
}

///|
/// The same as the nodes draw it (working_said_node), steadied in `steadies`.
fn glyphs_new(w : Double, src : Source, steadies : ActivitySteadies, came : @signals.Signal[Double?]) -> @ui.Tester {
  let view = work_view([work_agent_json()])
  dec_new(w, fn() { view }, fn(f, here) {
    working_said_node(f, src, here, "act:s-c1", fn() { row_side(w) }, fn() { 0.0 }, fn() { (here.view)().agents[0] }, fn() {
      came.get()
    }, steadies)
    |> ignore
  })
}

///|
/// How far apart the moments a change is looked at are, from its start: what its glyphs (glyph_change_in_ms) and its
/// line's width (a Move, move_most_ms at the most) take, in ten.
let glyphs_step_ms : Double = @ui.move_most_ms / 10.0

///|
/// How long a frame is at the slowest rate the tests run at (7 a second, scripts/fps_check.sh): the most the old view
/// sees a step after it was said.
// kept across runs: a value, never written
let glyphs_frame_most_ms : Double = 1000.0 / 7.0

///|
/// When the step said last begins showing, as the old view's steadying of row `rk` has it (steady_words): once what
/// shows has had steady_dwell_ms, and the step has been said steady_candidate_ms from the frame that saw it.
fn glyphs_old_due(rk : String) -> Double {
  let st = steadies.get(rk + "\u{1}s-c1").unwrap()
  dmax(st.at + steady_dwell_ms, st.pending_at + steady_candidate_ms)
}

///|
/// The same as the nodes' steadying has it (steady_step): from the moment it was said.
fn glyphs_new_due(steadies : ActivitySteadies) -> Double {
  let st = steadies.rows.get("act:s-c1").unwrap()
  dmax(st.shown.untracked().at + steady_dwell_ms, st.pending_at + steady_candidate_ms)
}

///|
/// A row's walk: what the core says first, shown a while, then each of `then` said `apart` after the one before; from
/// the moment the last begins showing (`due` reads it of the row's steadying once it is said), what is drawn at each
/// moment glyphs_step_ms apart to move_most_ms, and row_size_ms after that. What is drawn at each, and when the step
/// began showing.
fn glyphs_walk(
  t : @ui.Tester,
  live : @signals.Signal[Json?],
  then : Array[Json],
  apart : Double,
  due : () -> Double,
) -> (Array[String], Double) {
  t.run_for(steady_dwell_ms * 2.0)
  for i, j in then {
    if i > 0 {
      t.run_for(apart)
    }
    live.set(Some(j))
  }
  // (said: its turn worked out, not come)
  t.run_for(glyphs_step_ms)
  let at = due()
  t.run_for(at - t.time())
  let seen = [glyphs_drawn(t)]
  for _ in 0..<10 {
    t.run_for(glyphs_step_ms)
    seen.push(glyphs_drawn(t))
  }
  t.run_for(@ui.row_size_ms)
  seen.push(glyphs_drawn(t))
  (seen, at)
}

///|
/// The fixture's changes by name: what the core says first, what after it (each `apart` after the one before), how
/// wide the row is, the system's size of words.
fn glyphs_cases() -> Array[(String, Json, Array[Json], Double, Double, Double)] {
  let short = work_live("读 a.mbt")
  let long = work_live("改 chat_rows_node.mbt 和 decision.mbt", key="edit")
  [
    ("to a longer step", short, [long], 0.0, 760.0, 1.0),
    ("to a shorter step", long, [work_live("读 a.mbt", key="read2")], 0.0, 760.0, 1.0),
    ("to one of as many glyphs", short, [work_live("跑 b.sh", key="run")], 0.0, 760.0, 1.0),
    ("to one in the monospaced face", short, [work_live("npm test --filter rows", key="run", mono=true)], 0.0, 760.0, 1.0),
    (
      "several said quicker than the line shows them",
      short,
      [work_live("跑 b.sh", key="run"), work_live("编译", key="build"), long],
      steady_candidate_ms / 4.0,
      760.0,
      1.0,
    ),
    ("narrow, cut short", short, [work_live("改 chat_rows_node.mbt 和 decision.mbt 和 message_working_node.mbt", key="edit")], 0.0, 390.0, 1.0),
    ("at 1.3", short, [long], 0.0, 390.0, 1.3),
  ]
}

///|
test "a step giving way to the next glyph by glyph, made once as nodes, is drawn as the old view drew it at each moment from its start: longer, shorter, as many glyphs, monospaced, several said at once, narrow, at 1.3" {
  for i, c in glyphs_cases() {
    let (name, first, then, apart, w, scale) = c
    let rk = "g" + (10 + i).to_string()
    let live_old = @signals.signal(Some(first))
    let old = glyphs_old(w, work_src(live_old, []), rk, @signals.signal(None))
    old.set_font_scale(scale)
    let (was, old_at) = glyphs_walk(old, live_old, then, apart, fn() { glyphs_old_due(rk) })
    let steadies = ActivitySteadies::new()
    let live = @signals.signal(Some(first))
    let t = glyphs_new(w, work_src(live, []), steadies, @signals.signal(None))
    t.set_font_scale(scale)
    let said_at = Ref(0.0)
    let (seen, at) = glyphs_walk(t, live, then, apart, fn() {
      said_at.val = t.time() - glyphs_step_ms
      glyphs_new_due(steadies)
    })
    // (the nodes' step from the moment the last was said; the old view's from the frame that saw it, as late as a
    // frame of the rate at the most)
    assert_eq(at, said_at.val + steady_candidate_ms, msg=name)
    assert_true(old_at >= at && old_at - at <= glyphs_frame_most_ms, msg="\{name}: old \{old_at}, nodes \{at}")
    // (the default run draws a frame as a step is said: none apart there)
    if !@ui.test_at_a_rate() {
      assert_eq(old_at, at, msg=name)
    }
    for k, s in seen {
      if scale == 1.0 || k == seen.length() - 1 {
        assert_eq(s, was[k], msg="\{name}: at \{k}")
      } else {
        // (at the system's size of words, the old view's line as it changes was as high as the theme's line at 1,
        // its words set lower than the clock beside them and cut at their foot: the nodes' as high as its words, in
        // line with the clock. Across, how opaque, and at rest, the same)
        assert_eq(glyphs_across(s), glyphs_across(was[k]), msg="\{name}: at \{k}")
        assert_true(glyphs_level(s), msg="\{name}: at \{k}: \{s}")
      }
    }
    // (on its way half way through: glyphs seen part way in or out)
    assert_true(seen[3].contains(" a0."), msg="\{name}: \{seen[3]}")
    assert_eq(t.audit(), [], msg=name)
  }
}

///|
test "an agent's first words, made once as nodes, come in glyph by glyph as the old view's did, from when its row came into its list" {
  let live_old = @signals.signal(Some(work_live("改 chat_rows_node.mbt 和 decision.mbt")))
  let came_old : @signals.Signal[Double?] = @signals.signal(None)
  let old = glyphs_old(760.0, work_src(live_old, []), "g01", came_old)
  old.run_for(@ui.move_most_ms)
  came_old.set(Some(old.time()))
  // (the frame of the moment it came: what is read is that frame, not the one drawn before it came)
  old.draw()
  let was = [glyphs_drawn(old)]
  for _ in 0..<10 {
    old.run_for(activity_glyph_in_ms / 8.0)
    was.push(glyphs_drawn(old))
  }
  let steadies = ActivitySteadies::new()
  let live = @signals.signal(Some(work_live("改 chat_rows_node.mbt 和 decision.mbt")))
  let came : @signals.Signal[Double?] = @signals.signal(None)
  let t = glyphs_new(760.0, work_src(live, []), steadies, came)
  t.run_for(@ui.move_most_ms)
  came.set(Some(t.time()))
  t.draw()
  let seen = [glyphs_drawn(t)]
  for _ in 0..<10 {
    t.run_for(activity_glyph_in_ms / 8.0)
    seen.push(glyphs_drawn(t))
  }
  for k, s in seen {
    assert_eq(s, was[k], msg="at \{k}")
  }
  assert_eq(t.audit(), [])
}

///|
/// From the moment row `t`'s change begins (`at`), what is drawn at each moment glyphs_step_ms apart to move_most_ms,
/// `then` said as it is `when` steps in (`live`), and row_size_ms after that.
fn glyphs_from(t : @ui.Tester, at : Double, live : @signals.Signal[Json?], when : Int, then : Json) -> Array[String] {
  t.run_for(at - t.time())
  let seen = [glyphs_drawn(t)]
  for k in 1..=10 {
    if k == when + 1 {
      live.set(Some(then))
    }
    t.run_for(glyphs_step_ms)
    seen.push(glyphs_drawn(t))
  }
  t.run_for(@ui.row_size_ms)
  seen.push(glyphs_drawn(t))
  seen
}

///|
test "the same step's new words said as its change is under way: the nodes' change goes on to its end with the words it began with, then the new ones show at once, as the old view's at rest" {
  let short = work_live("读 a.mbt")
  let long = work_live("改 chat_rows_node.mbt 和 decision.mbt", key="edit")
  let longer = work_live("改 chat_rows_node.mbt 和 decision.mbt 第 2 段", key="edit")
  // (the old view's, the new words said three steps in: at rest, as the nodes' are)
  let live_old = @signals.signal(Some(short))
  let old = glyphs_old(760.0, work_src(live_old, []), "g02", @signals.signal(None))
  old.run_for(steady_dwell_ms * 2.0)
  live_old.set(Some(long))
  old.run_for(glyphs_step_ms)
  let was = glyphs_from(old, glyphs_old_due("g02"), live_old, 3, longer)
  // (the nodes' as the change went with nothing more said)
  let steadies = ActivitySteadies::new()
  let live = @signals.signal(Some(short))
  let t = glyphs_new(760.0, work_src(live, []), steadies, @signals.signal(None))
  t.run_for(steady_dwell_ms * 2.0)
  live.set(Some(long))
  t.run_for(glyphs_step_ms)
  let plain = glyphs_from(t, glyphs_new_due(steadies), live, 99, long)
  let steadies2 = ActivitySteadies::new()
  let live2 = @signals.signal(Some(short))
  let t2 = glyphs_new(760.0, work_src(live2, []), steadies2, @signals.signal(None))
  t2.run_for(steady_dwell_ms * 2.0)
  live2.set(Some(long))
  t2.run_for(glyphs_step_ms)
  let seen = glyphs_from(t2, glyphs_new_due(steadies2), live2, 3, longer)
  // (as the old view's up to the moment the new words were said; then on as with none said till its end)
  for k in 0..=3 {
    assert_eq(seen[k], was[k], msg="at \{k}")
  }
  // (the old view's words of the line coming in changed for the new ones as they were said, half way: other glyphs
  // at the places coming in, the line's way aimed elsewhere at once; the nodes' on as they were, till their glyphs'
  // change is over, glyph_change_in_ms from its start, its width's way ended before it)
  for k in 4..=7 {
    assert_eq(seen[k], plain[k], msg="at \{k}")
  }
  assert_true(seen[4] != was[4])
  // (then the new words whole, at once, as the old view's are then)
  for k in 8..=11 {
    assert_eq(seen[k], was[k], msg="at \{k}")
  }
  assert_true(t2.find("改 chat_rows_node.mbt 和 decision.mbt 第 2 段") is Some(_))
  assert_eq(t2.audit(), [])
}

///|
test "an important step said as a long change of width is under way: the nodes' next change sets out from where the line and its glyphs are then, as the old view's at its start and at rest" {
  let short = work_live("读 a.mbt")
  let long = work_live("改 chat_rows_node.mbt 和 decision.mbt 和 message_working_node.mbt 和 activity_steady_node.mbt 和 chat_list.mbt 和 chat_rows.mbt", key="edit")
  let ask : Json = { "activity": { "now": { "text": "等你确认", "key": "ask", "mono": false, "important": true } } }
  let live_old = @signals.signal(Some(short))
  let old = glyphs_old(1200.0, work_src(live_old, []), "g03", @signals.signal(None))
  old.run_for(steady_dwell_ms * 2.0)
  live_old.set(Some(long))
  old.run_for(glyphs_step_ms)
  let was = glyphs_from(old, glyphs_old_due("g03"), live_old, 1, ask)
  let steadies = ActivitySteadies::new()
  let live = @signals.signal(Some(short))
  let t = glyphs_new(1200.0, work_src(live, []), steadies, @signals.signal(None))
  t.run_for(steady_dwell_ms * 2.0)
  live.set(Some(long))
  t.run_for(glyphs_step_ms)
  let at = glyphs_new_due(steadies)
  let seen = glyphs_from(t, at, live, 1, ask)
  // (the important step began showing as the first change's glyphs were over, its line's width still on its way)
  let next = steadies.rows.get("act:s-c1").unwrap().shown.untracked()
  assert_eq(next.said.key, "ask")
  assert_eq(next.at, at + @sfbase.glyph_change_in_ms)
  for k in 0..=7 {
    assert_eq(seen[k], was[k], msg="at \{k}")
  }
  // (the old view's next change set out from the words it was whole where they are at rest, the line as wide as they
  // are, its width's way cut short; the nodes' from where its glyphs and its width had come to: the two apart since)
  assert_true(seen[8] != was[8])
  assert_eq(seen[11], was[11])
  assert_eq(t.audit(), [])
}

///|
test "with motion reduced, the nodes' line shows each step whole as it begins, as the old view's" {
  let short = work_live("读 a.mbt")
  let long = work_live("改 chat_rows_node.mbt 和 decision.mbt", key="edit")
  let live_old = @signals.signal(Some(short))
  let old = glyphs_old(760.0, work_src(live_old, []), "g04", @signals.signal(None))
  old.set_reduce_motion(true)
  let (was, _) = glyphs_walk(old, live_old, [long], 0.0, fn() { glyphs_old_due("g04") })
  let steadies = ActivitySteadies::new()
  let live = @signals.signal(Some(short))
  let t = glyphs_new(760.0, work_src(live, []), steadies, @signals.signal(None))
  t.set_reduce_motion(true)
  let (seen, _) = glyphs_walk(t, live, [long], 0.0, fn() { glyphs_new_due(steadies) })
  for k, s in seen {
    assert_eq(s, was[k], msg="at \{k}")
  }
  // (whole from its start)
  assert_eq(seen[0], seen[11])
  assert_eq(t.audit(), [])
}

///|
/// How far apart the two moments either side of a cause the line is looked at are: a ms.
// kept across runs: a value, never written
let glyphs_moment_ms : Double = 1.0

///|
/// Each glyph `t` draws now: where it is and how opaque.
fn glyphs_seen(t : @ui.Tester) -> Array[(Double, Double, Double)] {
  t.drawn_instances_keyed().filter(fn(a) { a[5] == 1.0 }).map(fn(a) { (a[0], a[1], a[11]) })
}

///|
/// Where each glyph seen in `now` (glyphs_ms_most's twentieth opaque at least: what is less is as good as gone, and
/// one at none is not drawn) was a ms before, in `was`, as near and as opaque as glyphs_ms_most says, and each seen
/// in `was` is so in `now`. What is otherwise.
fn glyphs_near(was : Array[(Double, Double, Double)], now : Array[(Double, Double, Double)]) -> String? {
  let near = fn(a : (Double, Double, Double), b : (Double, Double, Double)) {
    (a.0 - b.0).abs() <= glyphs_ms_most.0 && (a.1 - b.1).abs() <= glyphs_ms_most.0 && (a.2 - b.2).abs() <= glyphs_ms_most.1
  }
  for g in now {
    if g.2 >= glyphs_ms_most.1 && !was.iter().any(fn(w) { near(w, g) }) {
      return Some("\{Repr(g)} from nowhere near it: \{Repr(was)}")
    }
  }
  for w in was {
    if w.2 >= glyphs_ms_most.1 && !now.iter().any(fn(g) { near(w, g) }) {
      return Some("\{Repr(w)} gone at once: \{Repr(now)}")
    }
  }
  None
}

///|
/// How far a glyph may go in a ms, and how much more or less opaque it may come: a Move's fastest over the widest of
/// these lines, a glyph's quickest fade.
// kept across runs: values, never written
let glyphs_ms_most : (Double, Double) = (5.0, 0.05)

///|
/// What `t` draws a ms before moment `m` and a ms after it, `cause` done between: where each glyph seen after was
/// before, and each seen before is after, as glyphs_near has it. What is otherwise, none.
fn glyphs_step_at(t : @ui.Tester, m : Double, cause? : () -> Unit = fn() {  }) -> String? {
  t.run_for(m - glyphs_moment_ms - t.time())
  let was = glyphs_seen(t)
  cause()
  t.run_for(glyphs_moment_ms * 2.0)
  glyphs_near(was, glyphs_seen(t))
}

///|
/// A row at `w` walked to a change from short words to long ones, an important step said as it begins (its turn as the
/// glyphs' change is over: a ms either side of it looked at), then, where `again`, that step's own new words said half
/// way through its change (a ms either side of that). What glyphs_step_at says at each, as the change begins, as the
/// next takes over, as it is said again. `old`: the old view's row (steadied as row `rk`).
fn glyphs_steps(old : Bool, rk : String) -> Array[String?] raise {
  let short = work_live("读 a.mbt")
  let long = work_live("改 chat_rows_node.mbt 和 decision.mbt 和 message_working_node.mbt 和 activity_steady_node.mbt 和 chat_list.mbt 和 chat_rows.mbt", key="edit")
  let ask : Json = { "activity": { "now": { "text": "等你确认", "key": "ask", "mono": false, "important": true } } }
  let again : Json = { "activity": { "now": { "text": "等你确认：发布吗", "key": "ask", "mono": false, "important": true } } }
  let steadies = ActivitySteadies::new()
  let live = @signals.signal(Some(short))
  let t = if old {
    glyphs_old(1200.0, work_src(live, []), rk, @signals.signal(None))
  } else {
    glyphs_new(1200.0, work_src(live, []), steadies, @signals.signal(None))
  }
  t.run_for(steady_dwell_ms * 2.0)
  live.set(Some(long))
  t.run_for(glyphs_step_ms)
  let at = if old { glyphs_old_due(rk) } else { glyphs_new_due(steadies) }
  let begins = glyphs_step_at(t, at)
  t.run_for(glyphs_step_ms)
  live.set(Some(ask))
  let next = at + @sfbase.glyph_change_in_ms
  let taken = glyphs_step_at(t, next)
  let said = glyphs_step_at(t, next + glyphs_step_ms * 3.0, cause=fn() { live.set(Some(again)) })
  if !old {
    let shown = steadies.rows.get("act:s-c1").unwrap().shown.untracked()
    assert_eq(shown.said.key, "ask")
    assert_eq(shown.at, next)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("等你确认：发布吗") is Some(_))
    assert_eq(t.audit(), [])
  }
  [begins, taken, said]
}

///|
test "the nodes' line goes on without a step as a change begins, as another takes over one under way, as the same step's new words are said in one; the old view's at the last a step" {
  let was = glyphs_steps(true, "g05")
  // (the old view's next change set out from the words it was whole, the line as wide as they are: its width's way
  // so nearly over there that no glyph is a step from where it was; the same step's new words, at once)
  assert_eq(was[0], None)
  assert_eq(was[1], None)
  assert_true(was[2] is Some(_), msg="\{Repr(was)}")
  assert_eq(glyphs_steps(false, ""), [None, None, None])
}
