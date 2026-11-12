// A page in a panel of its own on the tape (laid out Medium), narrow in its panel (an iPhone Duo upright: a station's
// page beside the stations' list): its head of its own in the page's room as its cards and its parts' choice are, not
// against the panel's edge (2026-11-07).

///|
/// A station's page opened over the settings on an iPhone Duo upright (669 × 951, the system's bars), brought over
/// as a press on it does.
fn duo_station_page() -> @ui.Tester raise {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=669.0, h=951.0, platform=1, nav_able=true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":59,\"bottom\":90,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  app.nav.push(Settings)
  app.nav.push_over(Setting(@settings.Route::Station("ws1/st1")))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.tape.get())
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a station's page in a panel of the tape, narrow: its head (its mark, its name, its ⋯) within the room its parts' choice stands in" {
  let t = duo_station_page()
  // the parts' choice (概览 进程 …): the first thing under the head, in the page's room (the group its options are said
  // in, 概览 its first)
  let shown = t.semantics().filter(fn(s) { !s.hidden })
  guard shown.iter().find_first(fn(s) { s.role == @ui.Role::Radio && s.label == "概览" }) is Some(first) else {
    fail("no parts' choice: \{Repr(shown.map(fn(s) { (s.role, s.label) }))}")
  }
  guard shown
    .iter()
    .find_first(fn(s) {
      s.role == @ui.Role::RadioGroup &&
      s.rect.0 <= first.rect.0 &&
      s.rect.1 <= first.rect.1 &&
      first.rect.0 + first.rect.2 <= s.rect.0 + s.rect.2 &&
      first.rect.1 + first.rect.3 <= s.rect.1 + s.rect.3
    }) is Some(choice) else {
    fail("no parts' choice around 概览 at \{Repr(first.rect)}")
  }
  let (cx, cy, cw, _) = choice.rect
  // its mark: the square button over the choice (pressed to pick the station's mark)
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Button && s.rect.1 < cy && s.rect.2 == s.rect.3 && s.rect.2 < cw }) is Some(mark) else {
    fail("no mark")
  }
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.label == @sf.t("common.more") && s.rect.1 < cy }) is Some(more) else {
    fail("no ⋯")
  }
  assert_true(mark.rect.0 >= cx, msg="the mark at \{mark.rect.0}, the choice at \{cx}")
  assert_true(more.rect.0 + more.rect.2 <= cx + cw, msg="⋯ ends at \{more.rect.0 + more.rect.2}, the choice at \{cx + cw}")
  // (the page's own 4 inside the room, each side)
  assert_eq(mark.rect.0 - cx, cx + cw - (more.rect.0 + more.rect.2))
}
