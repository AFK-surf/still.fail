// A new Slack app's look in the new connect's dialog as its fixture puts it up over the whole app (src/sfpages
// slack_app.mbt; a connect's page's fold: src/sfpages connects_wbtest.mbt): the app's step, its icon and colour sent
// with the rest. On a phone's width with a finger.

///|
/// A page of the settings' fixture (`mode` as MBUI_FIXTURE has it) at a phone's width with a finger, its calls kept in
/// `calls` and answered.
fn look_tester(route : @settings.Route, calls : Array[Made], mode? : String = "settings") -> @ui.Tester {
  reset()
  if mode != "settings" {
    @settings.fixture_page(mode) |> ignore
  }
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(route))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a new Slack app's look in the new connect's dialog, at a phone's width: it starts as the first buddy, its icon and colour put in the flow" {
  let calls : Array[Made] = []
  let t = look_tester(@settings.Route::Connects(""), calls, mode="settings-new-connect-app")
  for _ in 0..<3 {
    t.draw()
  }
  assert_true(@sf.presenting())
  assert_true(t.query(Button, label="后端接口").unwrap().selected == Some(true))
  let edits = calls.filter(fn(m) { m.name == "connect.flow.edit" }).map(fn(m) { field(Some(m.params), "input") })
  assert_true(edits.iter().any(fn(i) { text(field(i, "settings"), "backgroundColor") == "#B582EB" }), msg=edits.map(fn(e) { e.to_string() }).join(" | "))
}
