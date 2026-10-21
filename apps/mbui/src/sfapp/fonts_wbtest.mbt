// 外观 › 字体 (settings/fonts.mbt; Fonts.kt) and the faces the app is then set in (faces.mbt), over the settings'
// fixture and its made-up faces (fonts_fixture.mbt).

///|
test "外观's 字体 row: the faces at a glance, opening the page: the places, a chat as they set it, the faces with their sizes" {
  let t = settings_tester("appearance")
  assert_true(t.find("字体") is Some(_))
  // none chosen: the app's own
  assert_true(t.find("默认") is Some(_))
  t.tap_text("字体")
  t.run_for(@ui.nav_push_ms)
  // the places as a switch, the interface's in view
  for w in ["界面", "正文", "代码"] {
    assert_true(t.find(w) is Some(_))
  }
  // the chat as the faces set it: their message, the agent's under its name
  assert_true(t.find("登录页在 Safari 上点了没反应") is Some(_))
  assert_true(t.find("Claude") is Some(_))
  // the interface's faces, each with how big it is to fetch (in thousands, as Android says it)
  assert_true(t.find("Inter") is Some(_))
  assert_true(t.find("458 kB") is Some(_))
  assert_true(t.find("思源黑体") is Some(_))
  assert_true(t.find("11 MB") is Some(_))
  assert_true(t.find("JetBrains Mono") is None)
  // each shown in itself: its preview given to a face of its own
  assert_true(@ui.face_given(preview_faces_from))
  // code's: the code faces, 默认 in the app's own (JetBrains Mono)
  t.tap_text("代码")
  t.draw()
  assert_true(t.find("Fira Code") is Some(_))
  assert_true(t.find("91 kB") is Some(_))
  assert_true(t.find("思源黑体") is None)
  assert_true(@ui.face_given(own_code_face))
}

///|
test "a face picked: kept as the device's, fetched, unzipped and checked, and what people write set in it; 跟随界面 puts it back" {
  let t = settings_tester("fonts")
  t.tap_text("正文")
  t.draw()
  assert_true(t.find("跟随界面") is Some(_))
  assert_false(@ui.face_given(@host.face_text))
  t.tap_text("霞鹜文楷")
  t.draw()
  // fetched (the core had none of it), its two files unzipped, checked, and given for what people write
  assert_true(face_here("lxgw-wenkai"))
  assert_true(@ui.face_given(@host.face_text))
  // here: no size said any more
  assert_true(t.find("26 MB") is None)
  // the interface's stays the app's own
  assert_false(@ui.face_given(@host.face_ui))
  t.tap_text("跟随界面")
  t.draw()
  assert_false(face_here("lxgw-wenkai"))
  assert_false(@ui.face_given(@host.face_text))
}

///|
test "a face being fetched: how far said on its row, the app's own standing in until it is here" {
  let t = settings_tester("fonts", mode="settings-fonts-coming", shows="settings-fonts-coming")
  assert_true(t.find("正在下载 42%") is Some(_))
  assert_false(face_here("noto-sans-sc"))
  assert_false(@ui.face_given(@host.face_ui))
}
