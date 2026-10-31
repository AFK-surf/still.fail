// A sidebar's list at its end (sfdesk's side.mbt side_scroll, sfpages' sidebar.mbt, @sf.list_foot_in): its last row
// as far from the column's foot as its rows are from its sides, in the panel's foot corners as in its sides; and a row
// of the settings' list whose words at its end leave it before its title is cut.

///|
/// The sidebar's row `label` (its link: the row's ground) left of `edge`.
fn side_row_at(t : @ui.Tester, label : String, edge : Double) -> (Double, Double, Double, Double)? {
  for s in t.semantics() {
    if s.label == label && s.role == @ui.Role::Link && !s.hidden && s.rect.0 < edge {
      return Some(s.rect)
    }
  }
  None
}

///|
/// The sidebar's panel on the tape (the block's: the rail and the sidebar in it).
fn side_panel(t : @ui.Tester) -> @ui.Laid? {
  t.boxes().iter().find_first(fn(b) { b.moves == "dock" })
}

///|
/// The tape's settings on a touch screen's medium window `h` high, the device's language `locale` (its host's
/// MBUI_LOCALE; "": Chinese): 关于's page opened from the sidebar's list scrolled to its end, beside the sidebar still
/// in use, 关于 its last row, lit; then a newer build known where `newer`.
fn settings_at_end(h : Double, locale? : String = "", newer? : String = "") -> @ui.Tester raise {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=690.0, h~, platform=2, env=[("MBUI_LOCALE", locale)])
  say_room(t, "medium", "medium")
  t.run_for(@ui.move_most_ms)
  tap_said(t, @sf.t("web-pages.settings.title"))
  t.run_for(@ui.move_most_ms)
  t.wheel(200.0, h / 2.0, 3000.0)
  t.run_for(@ui.move_most_ms)
  let about = @sf.t("web-pages.settings.nav.about")
  guard side_row_at(t, about, 400.0) is Some((x, y, w, rh)) else { fail("no \{about} in the sidebar") }
  t.tap(x + w / 2.0, y + rh / 2.0)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(app.nav.top() == Setting(@settings.Route::About))
  // (its page beside the sidebar, the sidebar still in use)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // (said once 关于 has asked still.fail cloud: what it answered, none newer, said over)
  if newer != "" {
    // (ready for the person's word: the settings' row says the version it goes to)
    @sffixture.fixture_update(newer)
    @sffixture.fixture_update_goes(newer, "ready")
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
test "on the tape a sidebar's list ends as far under its last row as its rows stand in from its sides: the settings' 关于 lit at its end, in the panel's foot corner" {
  let t = settings_at_end(520.0)
  guard side_row_at(t, "关于", 400.0) is Some((x, y, w, h)) else { fail("no 关于 in the sidebar") }
  guard side_panel(t) is Some(p) else { fail("no sidebar's panel") }
  let side = p.x + p.w - (x + w)
  let foot = p.y + p.h - (y + h)
  assert_eq(foot, @sf.list_foot_in(Side))
  assert_true((foot - side).abs() < 0.01, msg="its foot \{foot}, its side \{side}")
  assert_eq(t.corner_faults(), [])
}

///|
test "a settings row's words at its end leave it before its title is cut: About whole, Update to … gone where it has not the room" {
  // (what is at its end shorter than the row, longer than the row leaves it beside its title)
  let newer = "0.1.5425-beta"
  let t = settings_at_end(520.0, locale="en-US", newer~)
  update.available.set(None)
  assert_true(side_row_at(t, "About", 400.0) is Some(_), msg="no About in the sidebar")
  // (the row too short for both: what is at its end gone from it, its title whole)
  let said = "Update to " + newer
  let shown = t.boxes().iter().any(fn(b) { b.text == said && b.x < 400.0 && b.w > 0.0 && b.opacity > 0.0 })
  assert_false(shown, msg="its end still in the row")
  assert_eq(t.squeeze_faults(), [])
}
