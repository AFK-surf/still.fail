///|
/// The made-up chat with one of its made-up files open in the preview (preview_fixture.mbt).
fn preview_tester(what : String) -> @ui.Tester {
  reset()
  let src = fixture("chat-preview-" + what)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.settle() |> ignore
  t
}

///|
test "kinds by name, as the Android app's kindOf" {
  assert_true(preview_kind("a.PNG").0 == Some(KImage))
  assert_true(preview_kind("录屏.mov").0 == Some(KVideo))
  assert_true(preview_kind("x.pdf").0 == Some(KPdf))
  assert_true(preview_kind("Makefile").0 == Some(KCode))
  assert_eq(preview_kind("app.mts").2, "ts")
  assert_true(preview_kind("build.log").0 == Some(KText))
  assert_true(preview_kind("备份.bin").0 is None)
  assert_true(looks_like_text(utf8_bytes("纯文本 plain")))
  assert_true(!looks_like_text(b"\x00\x01\x02"))
}

///|
#skip("等 #747：预览关闭的淡出登记成动画（迁移 chat）")
test "an image opens fitted, its bar over it; a double tap zooms in, another back" {
  let t = preview_tester("image")
  assert_true(t.find("界面草图.png") is Some(_))
  assert_true(t.find("100%") is None)
  let v = viewer.val.unwrap()
  // 600 × 400 in 390 × 844 with 12 round it: (390 - 24) / 600
  assert_true((v.zoom.scale - 366.0 / 600.0).abs() < 0.001)
  t.tap(195.0, 422.0)
  t.advance(100.0)
  t.tap(195.0, 422.0)
  t.settle() |> ignore
  assert_true((v.zoom.scale - 1.525).abs() < 0.01)
  t.advance(400.0)
  t.tap(195.0, 422.0)
  t.advance(100.0)
  t.tap(195.0, 422.0)
  t.settle() |> ignore
  assert_true((v.zoom.scale - 366.0 / 600.0).abs() < 0.001)
  // back closes it (fading out), the chat under it again
  t.back()
  t.settle() |> ignore
  assert_true(viewer.val is None)
  assert_true(t.find("界面草图.png") is None)
}

///|
#skip("等 #747：预览关闭的淡出登记成动画（迁移 chat）")
test "a video plays in a native view, its bytes read through the core; its controls over it" {
  let t = preview_tester("video")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("open 1 1 ") }))
  assert_true(t.views().contains("control 1 1 0"))
  // 1280 × 720 fitted: (390 - 24) wide, in the middle
  let holes = t.holes()
  assert_eq(holes.length(), 1)
  let (x, _, w, h) = holes[0]
  assert_eq(x, 12.0)
  assert_true((w - 366.0).abs() < 0.5 && (h - 366.0 * 720.0 / 1280.0).abs() < 0.5)
  // its frames' times asked of the host and counted (the fake host's file: three frames a 30th of a second apart)
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("control 1 20 ") }))
  assert_true(t.find(" / 3 帧") is Some(_))
  t.back()
  t.settle() |> ignore
  assert_true(t.views().contains("close 1"))
}

///|
test "a PDF's pages, drawn by the host" {
  let t = preview_tester("pdf")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("pdf ") }))
  let v = viewer.val.unwrap()
  assert_eq(v.pdf.unwrap().pages, 3)
}

///|
test "HTML in a page of its own; its source in the code face" {
  let t = preview_tester("html")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("open 1 2 ") }))
  assert_eq(t.holes().length(), 1)
  let (_, y, _, _) = t.holes()[0]
  assert_eq(y, 60.0)
  t.tap_text("源码")
  t.settle() |> ignore
  assert_true(t.views().contains("close 1"))
  assert_true(t.find("周报草稿") is Some(_))
}

///|
test "a file of no kind it can show: told of, with the download" {
  let t = preview_tester("none")
  assert_true(t.find("此文件类型不支持预览") is Some(_))
  assert_true(t.find("4 KB · BIN") is Some(_))
  assert_true(t.find("下载") is Some(_))
}

///|
test "Markdown rendered; code as it is; a table" {
  let t = preview_tester("md")
  assert_true(t.find("发布前要做的") is Some(_))
  let t = preview_tester("code")
  assert_true(t.find("export const estimate = 66;") is Some(_))
  let t = preview_tester("csv")
  assert_true(t.find("帧时间（毫秒）") is Some(_))
  assert_true(t.find("设置, 外观") is Some(_))
}

///|
test "two fingers pinch an image round the point between them; no tap comes of it" {
  let t = preview_tester("image")
  let v = viewer.val.unwrap()
  let fit = v.zoom.scale
  let awake = v.awake
  t.touch(0, 150.0, 422.0)
  t.frame()
  t.touch(4, 240.0, 422.0)
  t.frame()
  t.touch(5, 330.0, 422.0)
  t.frame()
  // 90 apart, then 180: twice as big
  assert_true((v.zoom.scale - fit * 2.0).abs() < 0.001)
  t.touch(6, 330.0, 422.0)
  t.frame()
  t.touch(2, 150.0, 422.0)
  t.settle() |> ignore
  assert_eq(v.awake, awake)
}

///|
test "stepping through the chat's images: the way to the next (imageNear), a tap goes there" {
  let t = preview_tester("step")
  assert_true(t.find("界面草图.png") is Some(_))
  // fitted 600 × 400 in 366 wide: the way to the one after on the right
  let v = viewer.val.unwrap()
  let (_, after) = v.near(fixture("chat-preview-step"))
  assert_true(after is Some(_))
  t.tap(390.0 - 8.0 - 18.0, 422.0)
  t.settle() |> ignore
  assert_true(t.find("第二版.png") is Some(_))
  assert_eq(viewer.val.unwrap().file.name, "第二版.png")
}

///|
test "a swipe past a fifth of the stage goes to the next; a short one comes back" {
  let t = preview_tester("step")
  t.drag(300.0, 422.0, 260.0, 422.0)
  t.settle() |> ignore
  assert_eq(viewer.val.unwrap().file.name, "界面草图.png")
  t.drag(300.0, 422.0, 100.0, 422.0)
  t.settle() |> ignore
  assert_eq(viewer.val.unwrap().file.name, "第二版.png")
}

///|
test "marking: a box drawn on the picture is numbered, its note kept, its quote says where it is" {
  let t = preview_tester("image")
  marks_start()
  t.settle() |> ignore
  let v = viewer.val.unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  // from (100, 100) to (300, 200) in the picture's pixels
  t.drag(x + 100.0 * k, y + 100.0 * k, x + 300.0 * k, y + 200.0 * k)
  t.settle() |> ignore
  assert_eq(marking.shapes.length(), 1)
  assert_eq(marking.shapes[0].kind, "box")
  assert_eq(mark_numbers(marking.shapes).get(marking.shapes[0].id), Some(1))
  // what is said of it, then its quote
  marking.comments[marking.shapes[0].id] = "这里对齐"
  let q = marks_quotes("界面草图-标注.png", "界面草图.png", v.zoom.nw, v.zoom.nh)
  assert_eq(q.length(), 1)
  assert_eq(q[0].0, "图片 界面草图.png 标注 1")
  assert_true(q[0].1.has_prefix("框 · 左上角 ("))
  assert_eq(q[0].2, "这里对齐")
  // undone, none; redone, back
  marks_undo()
  assert_eq(marking.shapes.length(), 0)
  marks_redo()
  assert_eq(marking.shapes.length(), 1)
  marks_leave()
}
