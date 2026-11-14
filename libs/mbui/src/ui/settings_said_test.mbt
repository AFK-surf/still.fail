///|
/// What the host gives the frames, kept as it changes (@ui.trace_settings), and a Tester made and drawn by it
/// (settings_of, Tester::settings_said): a replay's, never by defaults of its own.
test "what the host gives the frames is kept as it changes, and a Tester is drawn by it again" {
  let said : Array[String] = []
  let t = @ui.Tester::new(env_view, w=400.0, h=700.0, scale=1.0)
  @ui.trace_settings(fn(m) { said.push(Json::object(m).stringify()) })
  t.frame()
  t.frame()
  t.set_dark(true)
  t.set_utc_offset(540)
  t.frame()
  @ui.trace_settings(fn(_) { () })
  // the first frame's, then the change's: two (the frame between them gave the same)
  assert_eq(said.length(), 2)
  let first = @json.parse(said[0]) catch { _ => panic() }
  guard @ui.settings_of(first) is Ok((w, h, scale, _, _, dark)) else { fail("not one") }
  assert_eq((w, h, scale, dark), (400.0, 700.0, 1.0, false))
  assert_true(said[1].contains("\"dark\":1") && said[1].contains("\"utc\":540"))
  // a Tester made by the first and told the second draws as the run did then
  let again = @ui.Tester::new(env_view, w~, h~, scale~, dark~)
  assert_true(again.settings_said(said[0]))
  again.frame()
  assert_true(again.words().iter().any(fn(w) { w.0 == "light" }))
  assert_true(again.settings_said(said[1]))
  again.frame()
  assert_true(again.words().iter().any(fn(w) { w.0 == "dark" }))
  assert_eq(@hostapi.utc_offset_min(0.0), 540)
  // a line that is not one is left to what else reads the host's lines
  assert_false(again.settings_said("{\"view\":{\"view\":1}}"))
}

///|
test "a run's settings without a field are refused by name, never filled in" {
  let line : Json = { "settings": { "w": 390.0, "h": 844.0, "scale": 2.0, "platform": 2.0, "pointing": 1.0, "dark": 0.0 } }
  guard @ui.settings_of(line) is Err(why) else { fail("taken without its font") }
  assert_true(why.contains("font"))
  assert_true(@ui.settings_of({ "view": 1.0 }) is Err(_))
}
