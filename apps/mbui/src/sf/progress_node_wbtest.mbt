///|
/// A progress bar as an old view draws it (progress) at (0, 0) and as nodes (progress_node) 300 in, each 200 wide, at
/// how far `part` says.
fn progress_pair(part : @signals.Signal[Double?]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=600.0, h=100.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(200.0))).height(Is(Some(3.0))) |> ignore
      @ui.old(h, fn(c) { progress(c, "old", part.get()) }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(100.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(200.0))) |> ignore
      progress_node(b, fn() { part.get() }, fn() { @ui.tree_theme().line }, fn() { theme().p.accent }).width_share(
        Is(1.0),
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The pieces of the bar drawn on either side (the old view's, the nodes'), each as (x from its bar's start, width), the
/// track's first: what is drawn of each 3 high.
fn progress_drawn(t : @ui.Tester) -> (Array[(Int, Int)], Array[(Int, Int)]) {
  let old = []
  let new = []
  for r in t.drawn_rects() {
    let (x, _, w, h, _) = r
    if h != 3.0 || w < 0.5 {
      continue
    }
    if x < 250.0 {
      old.push(((x * 10.0).round().to_int(), (w * 10.0).round().to_int()))
    } else {
      new.push((((x - 300.0) * 10.0).round().to_int(), (w * 10.0).round().to_int()))
    }
  }
  (old, new)
}

///|
/// What each bar (the old view's, the nodes') says, as read out (its value, its range) and as the host is told it (its
/// range's least, where it is, its most: a11y_lines' fields 12 to 14): checked to be `value` and `range` both.
fn progress_said(t : @ui.Tester, value : String, range : (Double, Double, Double)?) -> Unit raise {
  let bars = t.all(ProgressBar)
  assert_eq(bars.length(), 2, msg="both bars read out")
  for b in bars {
    assert_eq((b.value, b.range), (value, range), msg="read out: \{b.value} \{b.range}")
  }
  let told = t.ctx().a11y_lines().split("\n").filter(fn(l) { l.contains("ProgressBar") }).to_array()
  assert_eq(told.length(), 2, msg="both told the host")
  let want = match range {
    Some((lo, at, hi)) => [lo.to_string(), at.to_string(), hi.to_string()]
    None => ["", "", ""]
  }
  for l in told {
    let f = l.split("\u{1F}").map(fn(v) { v.to_string() }).to_array()
    assert_eq([f[12], f[13], f[14]], want, msg="told the host: \{f[12]} \{f[13]} \{f[14]}")
  }
}

///|
/// What the nodes' bar says as read out now (its value, its range), no frame drawn for it: the one 300 in.
fn node_said(t : @ui.Tester) -> (String, (Double, Double, Double)?) {
  let bars = t.all(ProgressBar).filter(fn(b) { b.rect.0 >= 250.0 })
  if bars.length() != 1 {
    return ("\{bars.length()} bars", None)
  }
  (bars[0].value, bars[0].range)
}

///|
test "a progress bar as nodes drawn and read out as the old view's is (its range its least, where it is, its most, told so to the host): at a part, gone on to another over progress_ms from where it was at that moment, then not known (a 40% piece sweeping across as a wait, not a motion), then known again" {
  let part : @signals.Signal[Double?] = @signals.signal(Some(0.25), same=fn(a, b) { a == b })
  let t = progress_pair(part)
  let same = fn(what : String) raise {
    let (old, new) = progress_drawn(t)
    assert_true(old.length() >= 2, msg="\{what}: the old one drawn: \{old}")
    assert_eq(new, old, msg=what)
  }
  same("at a quarter")
  progress_said(t, "25%", Some((0.0, 25.0, 100.0)))
  part.set(Some(0.75))
  assert_eq(node_said(t), ("75%", Some((0.0, 75.0, 100.0))), msg="told: said at once, no frame drawn")
  t.draw()
  t.run_for(@kit.progress_ms / 2.0)
  same("half way to three quarters")
  progress_said(t, "75%", Some((0.0, 75.0, 100.0)))
  t.run_for(@kit.progress_ms)
  same("at three quarters")
  part.set(None)
  assert_eq(node_said(t), ("", None), msg="not known: said at once, no frame drawn")
  t.draw()
  t.run_for(@kit.progress_known_ms / 3.0)
  same("going to not known")
  t.run_for(@kit.progress_known_ms)
  same("not known: swept")
  progress_said(t, "", None)
  let tree = @ui.view_tree().unwrap()
  assert_true(tree.cycle_read(), msg="not known: a wait read by the clock")
  assert_true(!tree.clock_read(), msg="no motion")
  t.run_for(@kit.progress_sweep_ms / 3.0)
  same("not known, a third of a sweep later")
  part.set(Some(0.5))
  assert_eq(node_said(t), ("50%", Some((0.0, 50.0, 100.0))), msg="known again: said at once, no frame drawn")
  t.draw()
  t.run_for(@kit.progress_known_ms)
  same("known again, at half")
  progress_said(t, "50%", Some((0.0, 50.0, 100.0)))
  assert_true(!tree.cycle_read() && !tree.clock_read(), msg="known and there: nothing reads the clock")
}

///|
test "a progress bar as nodes, motion reduced, drawn as the old view's is: a part told anew there in the first frame, not known and known again there at once, nothing read of the clock after any of them" {
  @ui.set_motion_chosen(Some(true))
  let part : @signals.Signal[Double?] = @signals.signal(Some(0.25), same=fn(a, b) { a == b })
  let t = progress_pair(part)
  let tree = @ui.view_tree().unwrap()
  let seen : Array[(String, (Array[(Int, Int)], Array[(Int, Int)]), Bool)] = []
  for step in [("three quarters", Some(0.75)), ("not known", None), ("known again", Some(0.5))] {
    part.set(step.1)
    t.draw()
    seen.push((step.0, progress_drawn(t), tree.clock_read() || tree.cycle_read()))
  }
  @ui.set_motion_chosen(None)
  for s in seen {
    let (what, (old, new), ticking) = s
    assert_true(old.length() >= 2, msg="\{what}: the old one drawn: \{old}")
    assert_eq(new, old, msg="\{what}: in the first frame, as the old one")
    assert_true(!ticking, msg="\{what}: nothing read of the clock after")
  }
}
