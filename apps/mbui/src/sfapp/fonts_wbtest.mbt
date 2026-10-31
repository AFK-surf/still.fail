// 外观 › 字体 (settings/fonts.mbt; Fonts.kt) and the faces the app is then set in (faces.mbt), over the settings'
// fixture and its made-up faces (fonts_fixture.mbt).

///|
test "外观's 字体 row: the faces at a glance, opening the page: the places, a chat as they set it, the faces with their sizes" {
  let t = settings_tester("appearance")
  assert_true(t.find("字体") is Some(_))
  // none chosen: the app's own, its setting's row (after 主题)
  assert_true(t.find("默认") is Some(_))
  // (its words whole: 拖入 chat 的文件's note says 默认 too)
  let said = t.words().filter(fn(w) { w.0 == "默认" && w.5 > 0.5 })
  assert_eq(said.length(), 1)
  t.tap(said[0].1 + said[0].3 / 2.0, said[0].2 + said[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
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
  tap_place(t, "代码")
  t.draw()
  assert_true(t.find("Fira Code") is Some(_))
  assert_true(t.find("91 kB") is Some(_))
  assert_true(t.find("思源黑体") is None)
  assert_true(@ui.face_given(own_code_face))
}

///|
test "a face picked: kept as the device's, fetched, unzipped and checked, and what people write set in it; 跟随界面 puts it back" {
  let t = settings_tester("fonts")
  tap_place(t, "正文")
  t.draw()
  assert_true(t.find("跟随界面") is Some(_))
  assert_false(@ui.face_given(@hostapi.face_text))
  t.tap_text("霞鹜文楷")
  t.draw()
  // fetched (the core had none of it), its two files unzipped, checked, and given for what people write
  assert_true(face_here("lxgw-wenkai"))
  assert_true(@ui.face_given(@hostapi.face_text))
  // here: no size said any more
  assert_true(t.find("26 MB") is None)
  // the interface's stays the app's own
  assert_false(@ui.face_given(@hostapi.face_ui))
  t.tap_text("跟随界面")
  t.draw()
  assert_false(face_here("lxgw-wenkai"))
  assert_false(@ui.face_given(@hostapi.face_text))
}

///|
test "a face being fetched: how far said on its row, the app's own standing in until it is here" {
  let t = settings_tester("fonts", mode="settings-fonts-coming", shows="settings-fonts-coming")
  assert_true(t.find("正在下载 42%") is Some(_))
  assert_false(face_here("noto-sans-sc"))
  assert_false(@ui.face_given(@hostapi.face_ui))
}

///|
/// The made-up prefs with each place's face's files said kept here (`path`, as the core says it of those this device
/// keeps: client/core-ts/src/fonts.ts setKeptAt), at `/data/` and the file's weight.
fn kept_here(base : Source) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      if name == "prefs" {
        match field(t.value, "faces") {
          Some(Object(faces)) =>
            for place in ["ui", "text", "code"] {
              for f in items(faces.get(place), "files") {
                match f {
                  Object(m) => m["path"] = ("/data/" + number(Some(f), "weight").to_int().to_string()).to_json()
                  _ => ()
                }
              }
            }
          _ => ()
        }
      }
      t
    },
  }
}

///|
test "a face kept here: given by where its files are the frame the prefs come, the first page set in it, nothing asked of the core" {
  new_run()
  let base = fixture("home")
  (base.call)("prefs.set", { "fonts": { "ui": "noto-sans-sc" } }, fn(_) {  })
  let asked = Ref(0)
  let src : Source = {
    ..kept_here(base),
    read_bytes: fn(name, params, done) {
      if name == "fonts.file" {
        asked.val += 1
      }
      (base.read_bytes)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(face_here("noto-sans-sc"))
  assert_true(@ui.face_given(@hostapi.face_ui))
  assert_eq(asked.val, 0)
}

///|
test "a face's file the host cannot read where it is: had through the core instead, unzipped and checked" {
  new_run()
  let base = fixture("home")
  // fetched, kept as fetched (gzipped): what the host cannot read as a face
  (base.call)("fonts.fetch", { "id": "lxgw-wenkai" }, fn(_) {  })
  (base.call)("prefs.set", { "fonts": { "text": "lxgw-wenkai" } }, fn(_) {  })
  let asked = Ref(0)
  let src : Source = {
    ..kept_here(base),
    read_bytes: fn(name, params, done) {
      if name == "fonts.file" {
        asked.val += 1
      }
      (base.read_bytes)(name, params, done)
    },
  }
  // (the app from the frame its host is set so)
  let on = Ref(false)
  let t = @ui.Tester::new(fn(c) { if on.val { view(c, src) } }, w=390.0, h=844.0, platform=2)
  t.set_unreadable_font("/data/500")
  on.val = true
  t.draw()
  t.draw()
  assert_eq(asked.val, 2)
  assert_true(face_here("lxgw-wenkai"))
  assert_true(@ui.face_given(@hostapi.face_text))
}

///|
/// The places' choice's `place` tapped (its words drawn after what the page is for, which names them too).
fn tap_place(t : @ui.Tester, place : String) -> Unit {
  let (x, y) = t.find_last(place).unwrap()
  t.tap(x, y)
}

///|
test "a face pointed at tried in the chat above them: the chat held at its tallest while the pointer is on the faces, nothing under it shaking" {
  let t = settings_tester("fonts")
  // 思源黑体 set wide enough that their message wraps once more in it, 思源宋体 a little
  t.face_wider(preview_faces_from + 1, 0.6)
  t.face_wider(preview_faces_from + 2, 0.3)
  t.draw()
  let before = t.find("Inter").unwrap()
  let (x, y) = t.find("思源黑体").unwrap()
  t.move(x + 4.0, y + 4.0)
  t.draw()
  // tried: the chat taller, the faces moved down once, and held there as the row now under the pointer is tried
  let moved = t.find("Inter").unwrap()
  assert_true(moved.1 > before.1)
  // the hand still on the same spot, moving a little (the row under it now another, narrower one): nothing moves
  for i in 0..<4 {
    t.move(x + 5.0 + i.to_double(), y + 4.0)
    t.draw()
    assert_eq(t.find("Inter"), Some(moved))
  }
  // along the faces (a narrower one tried, the gaps between rows): still held
  let (x2, y2) = t.find("霞鹜文楷").unwrap()
  t.move(x2 + 4.0, y2 + 4.0)
  t.draw()
  t.draw()
  assert_eq(t.find("Inter"), Some(moved))
  // the pointer gone off the faces: as before
  t.move(x, 4.0)
  t.draw()
  t.draw()
  assert_eq(t.find("Inter"), Some(before))
}
