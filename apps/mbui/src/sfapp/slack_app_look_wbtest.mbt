// A Slack app's look in its pages (src/sfdesk slack_app.mbt; one in every frame): on a connect's page, its app's fold;
// in a new connect's dialog, the app's step. Its icon picked from still.fail's buddies or the model makers' marks or
// a picture of the person's own, drawn on its colour, and sent with the rest. On a phone's width with a finger.

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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(route))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "a connect's Slack app, at a phone's width: its fold opened, the buddies and the makers to pick from, a picture to upload" {
  let calls : Array[Made] = []
  let t = look_tester(@settings.Route::Connect("ws1/st1", "k1"), calls)
  let (x, y, w, h) = t.query(Button, label="Slack app").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  // the core's buddies asked for once, then the makers after them
  assert_eq(calls.filter(fn(m) { m.name == "buddies" }).length(), 1)
  for a in ["后端接口", "移动应用", "写文档", "Anthropic", "OpenAI"] {
    assert_true(t.query(Button, label=a) is Some(_), msg=a)
  }
  // a picture of one's own: its icon's button
  assert_true(t.query(Button, label="上传图片") is Some(_))
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
