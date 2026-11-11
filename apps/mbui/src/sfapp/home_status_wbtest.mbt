// A phone's chats' list under the system's status bar (window_inset: the bar over the window's top): its top bar's
// glass goes up under the status bar, one with it, as before Home was made once (d540841ab1^: TopGlassBar under
// windowInsetsPadding(statusBars)). 2026-11-05: a page's ground painted over the status bar's room cut it from the
// glass under it (narrow_made_top's paper, for a page with no top of its own, over Home's own).

///|
test "a phone's chats' list's top bar is one glass with the status bar's room over it, no ground painted across it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home", w=390.0, h=844.0, platform=2, window_inset=true)
  t.run_for(@ui.move_most_ms)
  let glass = t.drawn_glass().filter(fn(g) { g.1 == 0.0 && g.2 == 390.0 })
  // (a band of ground across the window's top, less tall than the glass: over the status bar's room)
  let bands = t.drawn_rects().filter(fn(r) {
    r.0 == 0.0 && r.1 == 0.0 && r.2 == 390.0 && glass.iter().any(fn(g) { r.3 < g.3 })
  })
  assert_eq((glass.length(), bands), (1, []), msg="the glass \{Repr(glass)}")
}

///|
test "the system status bar remains part of Home's glass" {
  let t = wide_tester([], mode="home", w=390.0, h=844.0, platform=2)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":24,\"bottom\":48,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let glass = t.drawn_glass().filter(fn(g) { g.1 == 0.0 && g.2 == 390.0 })
  let bands = t.drawn_rects().filter(fn(r) {
    r.0 == 0.0 && r.1 == 0.0 && r.2 == 390.0 && r.3 == 24.0
  })
  assert_eq((glass.length(), bands), (1, []), msg="the glass \{Repr(glass)}")
}

///|
test "a made place's own top bar needs no ground over the status bar" {
  new_run()
  let src = fixture("home")
  app.nav.replace(Place("usage"))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":24,\"bottom\":48,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let glass = t.drawn_glass().filter(fn(g) { g.1 == 0.0 && g.2 == 390.0 })
  let bands = t.drawn_rects().filter(fn(r) {
    r.0 == 0.0 && r.1 == 0.0 && r.2 == 390.0 && r.3 == 24.0
  })
  assert_eq((glass.length(), bands), (1, []), msg="the glass \{Repr(glass)}")
}

///|
test "a made page without its own top still covers the status bar with its ground" {
  new_run()
  let src = fixture("home")
  app.nav.replace(Settings)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":24,\"bottom\":48,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let bands = t.drawn_rects().filter(fn(r) {
    r.0 == 0.0 && r.1 == 0.0 && r.2 == 390.0 && r.3 == 24.0
  })
  assert_true(!bands.is_empty(), msg="the page's status-bar ground: \{Repr(bands)}")
}
