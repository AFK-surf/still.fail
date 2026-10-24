// A Slack app's look (settings/app_look.mbt; SlackApp.kt AppLook): its icon picked from still.fail's buddies or the
// model makers' marks or a picture of the person's own, drawn on its colour as a 1024 JPEG, and sent with the rest.

///|
/// The Slack app page of the settings' fixture, its calls kept in `calls` and answered.
fn slack_app_tester(calls : Array[Made]) -> @ui.Tester {
  reset()
  let base = fixture("settings")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  open_setting("slack-app:ws1/st1#c1")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
/// The colour in the look's field.
fn colour_typed(t : @ui.Tester) -> String {
  match t.query(TextField, label="#RRGGBB") {
    Some(s) => s.value
    None => ""
  }
}

///|
/// What the last connect.putSlackApp sent.
fn put_input(calls : Array[Made]) -> Json? {
  let made = calls.filter(fn(m) { m.name == "connect.putSlackApp" })
  if made.is_empty() {
    None
  } else {
    field(Some(made[made.length() - 1].params), "input")
  }
}

///|
test "a Slack app's look: its icon, the buddies and the makers to pick from, its colour" {
  let calls : Array[Made] = []
  let t = slack_app_tester(calls)
  assert_true(t.find("头像") is Some(_))
  assert_true(t.find("从下方选择一个，或上传图片。") is Some(_))
  // an app that has one: kept until another is picked
  assert_true(t.find("保持当前") is Some(_))
  assert_true(t.find("上传图片") is Some(_))
  // the core's buddies asked for once, then the makers after them
  assert_eq(calls.filter(fn(m) { m.name == "buddies" }).length(), 1)
  for a in ["后端接口", "移动应用", "写文档", "Anthropic", "OpenAI", "智谱", "xAI"] {
    assert_true(t.query(Button, label=a) is Some(_), msg=a)
  }
  assert_true(t.find("底色") is Some(_))
}

///|
test "a buddy picked: its picture read and drawn on its colour, the icon sent with the colour" {
  let calls : Array[Made] = []
  let t = slack_app_tester(calls)
  // its picture: 4 by 4, a red square in the middle 2 by 2, clear round it
  let px = FixedArray::make(64, b'\x00')
  for y in 1..<3 {
    for x in 1..<3 {
      px[(y * 4 + x) * 4] = b'\xFF'
      px[(y * 4 + x) * 4 + 3] = b'\xFF'
    }
  }
  t.add_pixels("https://app.still.fail/avatars/mobile.webp", 4, 4, px)
  t.click(Button, label="移动应用")
  // its picture decoded, read back
  for _ in 0..<3 {
    t.draw()
  }
  // its colour taken
  assert_eq(colour_typed(t), "#B9D84A")
  assert_true(t.query(Button, label="移动应用").unwrap().selected == Some(true))
  t.tap_text("应用到 Slack")
  t.draw()
  let input = put_input(calls)
  assert_eq(text(input, "backgroundColor"), "#B9D84A")
  assert_true(text(input, "icon").has_prefix("data:image/jpeg;base64,/9j/"))
}

///|
test "a maker's mark picked: drawn at once, on its own colour" {
  let calls : Array[Made] = []
  let t = slack_app_tester(calls)
  t.click(Button, label="Anthropic")
  t.draw()
  assert_eq(colour_typed(t), "#D97757")
  t.tap_text("应用到 Slack")
  t.draw()
  assert_true(text(put_input(calls), "icon").has_prefix("data:image/jpeg;base64,"))
}

///|
test "a picture of their own: its middle square on white, the colour its edge's" {
  let calls : Array[Made] = []
  let t = slack_app_tester(calls)
  t.picks([("me.png", b"\x89PNG")])
  // the icon tapped: the system's picker (as 上传图片 does)
  t.click(Button, label="头像")
  // the picker's answer (the frame after it asked), the picture decoded (the made-up host's by the next), read back
  // and drawn
  assert_eq(t.pick_asks().length(), 1)
  for _ in 0..<4 {
    t.draw()
  }
  // (the made-up host's picture: grey through) its edge's colour taken
  assert_eq(colour_typed(t), "#808080")
  t.tap_text("应用到 Slack")
  t.draw()
  let input = put_input(calls)
  assert_eq(text(input, "backgroundColor"), "#808080")
  assert_true(text(input, "icon").has_prefix("data:image/jpeg;base64,"))
}

///|
test "a picture that cannot be read: said, nothing sent" {
  let calls : Array[Made] = []
  let t = slack_app_tester(calls)
  // a buddy whose picture the host does not have: it did not decode
  t.click(Button, label="后端接口")
  t.draw()
  t.draw()
  assert_true(t.find("无法生成头像") is Some(_))
}

///|
test "a new Slack app's look: it starts as the first buddy, its icon and colour put in the flow" {
  let calls : Array[Made] = []
  reset()
  @settings.fixture_page("settings-new-connect-app") |> ignore
  let base = fixture("settings")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  open_setting("new-connect:ws1/st1")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  for _ in 0..<3 {
    t.draw()
  }
  // a new one: 上传 on its empty icon until one is made, then the first buddy's, on its colour
  assert_true(t.query(Button, label="后端接口").unwrap().selected == Some(true))
  let edits = calls.filter(fn(m) { m.name == "connect.flow.edit" }).map(fn(m) { field(Some(m.params), "input") })
  assert_true(edits.iter().any(fn(i) { text(field(i, "settings"), "backgroundColor") == "#B582EB" }))
  assert_true(edits.iter().any(fn(i) { text(i, "icon").has_prefix("data:image/jpeg;base64,") }))
}
