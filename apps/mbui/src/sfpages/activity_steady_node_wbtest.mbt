// What an agent at work says it does, steadied (activity_steady_node.mbt): each change of what shows and the moment it
// began, held to what steady_words worked out, from the moments the core said each step; the same at every rate.

///|
/// A step as the core says it.
fn steady_said(key : String, words : String, important? : Bool = false) -> ActivitySaid {
  { key, words, mono: false, important }
}

///|
/// A node steadying row "r" of `steadies` as `said` and `came` say, every change of what shows kept in `log`.
fn steady_tester(
  steadies : ActivitySteadies,
  said : @signals.Signal[ActivitySaid],
  came : @signals.Signal[Double?],
  log : Array[ActivityShown],
  on? : @signals.Signal[Bool] = @signals.signal(true),
) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      root.show(fn() { on.get() }, fn(v) {
        let shown = activity_steady_node(v, steadies, "r", fn() { said.get() }, fn() { came.get() })
        v.reacts(shown, fn(s) { log.push(s) })
        v.box(fn(w) { w.words(By(fn() { shown().said.words })) |> ignore }) |> ignore
      })
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  t
}

///|
test "steadied: a routine step shows once what shows has had steady_dwell_ms and it has been said steady_candidate_ms; one gone before its turn never shows; an important one at once once what shows has had its change; the same step's new words at once" {
  let steadies = ActivitySteadies::new()
  let a = steady_said("read", "读 chat_rows.mbt")
  let said = @signals.signal(a)
  let came : @signals.Signal[Double?] = @signals.signal(None)
  let log : Array[ActivityShown] = []
  let t = steady_tester(steadies, said, came, log)
  assert_eq(log.length(), 1)
  let t0 = log[0].at
  assert_eq(log[0], { said: a, was: "", was_mono: false, at: t0 })
  // a routine step said soon after: its turn once what shows has had its dwell
  t.run_for(steady_candidate_ms / 2.0)
  let t1 = t.time()
  let b = steady_said("edit", "改 chat_rows.mbt")
  said.set(b)
  t.run_for(steady_dwell_ms * 2.0)
  let b_at = dmax(t0 + steady_dwell_ms, t1 + steady_candidate_ms)
  assert_eq(log, [{ said: a, was: "", was_mono: false, at: t0 }, { said: b, was: a.words, was_mono: false, at: b_at }])
  // one said and another after it before its turn: the first never shows, the second from when it was said
  let c = steady_said("test", "跑测试")
  said.set(c)
  t.run_for(steady_candidate_ms / 2.0)
  let t3 = t.time()
  let d = steady_said("build", "编译")
  said.set(d)
  t.run_for(steady_dwell_ms * 2.0)
  let d_at = dmax(b_at + steady_dwell_ms, t3 + steady_candidate_ms)
  assert_eq(log.length(), 3)
  assert_eq(log[2], { said: d, was: b.words, was_mono: false, at: d_at })
  // an important step: at once, what shows having had its own change's time
  let t4 = t.time()
  let e = steady_said("ask", "等你确认", important=true)
  said.set(e)
  t.draw()
  let e_at = dmax(d_at + @sfbase.glyph_change_in_ms, t4)
  assert_eq(log[3], { said: e, was: d.words, was_mono: false, at: e_at })
  // a routine one after an important one: once that has had its dwell
  t.run_for(steady_candidate_ms / 2.0)
  let t5 = t.time()
  let f = steady_said("read2", "读 decision.mbt")
  said.set(f)
  t.run_for(steady_dwell_ms * 2.0)
  let f_at = dmax(e_at + steady_dwell_ms, t5 + steady_candidate_ms)
  assert_eq(log[4], { said: f, was: e.words, was_mono: false, at: f_at })
  // the same step's new words: at once, from when it began
  let f2 = steady_said("read2", "读 decision.mbt 第 2 段")
  said.set(f2)
  t.draw()
  assert_eq(log.length(), 6)
  assert_eq(log[5], { said: f2, was: e.words, was_mono: false, at: f_at })
  assert_eq(t.audit(), [])
}

///|
test "steadied: kept by its row's key, a row made again goes on from where it was; a row come into its list anew starts from that moment with what is said then" {
  let steadies = ActivitySteadies::new()
  let a = steady_said("read", "读 chat_rows.mbt")
  let said = @signals.signal(a)
  let came : @signals.Signal[Double?] = @signals.signal(None)
  let on = @signals.signal(true)
  let log : Array[ActivityShown] = []
  let t = steady_tester(steadies, said, came, log, on~)
  let t0 = log[0].at
  t.run_for(steady_candidate_ms / 2.0)
  let t1 = t.time()
  let b = steady_said("edit", "改 chat_rows.mbt")
  said.set(b)
  t.run_for(steady_dwell_ms * 2.0)
  // let go and made again: what showed, as it was
  on.set(false)
  t.run_for(@ui.move_most_ms)
  on.set(true)
  t.draw()
  let b_at = dmax(t0 + steady_dwell_ms, t1 + steady_candidate_ms)
  assert_eq(log[log.length() - 1], { said: b, was: a.words, was_mono: false, at: b_at })
  // come into its list anew: what is said now, from then
  let t2 = t.time()
  came.set(Some(t2))
  t.draw()
  assert_eq(log[log.length() - 1], { said: b, was: "", was_mono: false, at: t2 })
  assert_eq(t.audit(), [])
}
