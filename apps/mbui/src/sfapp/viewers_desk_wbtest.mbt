// The file viewers on a desktop (the library's viewer_bar.mbt, reader.mbt; preview_desk.mbt): over the wide frame's whole
// window, as the desktop app's (FilePreview.tsx docked, viewer/Reader.tsx with a mouse).

///|
/// The fixture's `mode` in a desktop's window: a chat's file open in its preview (chat-preview-…), a drive's text read
/// (reader…), seen once it is in.
fn desk_tester(mode : String) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  if mode.has_prefix("chat-preview") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  t.draw()
  if mode.has_prefix("reader") || mode.has_prefix("player") {
    // (what the mode opens: 文档 and the file in it)
    app.nav.replace(Home)
    open_drive_fixture(mode)
    t.run_for(@ui.move_most_ms)
  } else {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// Where a tool of the bar is, by how many from its end (download 0): the last at the window's corner as a page's bar's
/// last is (window_end_in), 32 each, 2 apart.
fn desk_tool_x(from_end : Int) -> Double {
  1280.0 - @sf.window_end_in(12.0) - 16.0 - from_end.to_double() * 34.0
}

///|
test "desk: an image on the canvas under the bar, back to its chat by name, which of two, its size and kind, no zoom's tools in it (zoomed by the hand and the keys); → steps, Esc closes" {
  let t = desk_tester("chat-preview-step")
  assert_true(@sfdesk.is_wide(t.ctx()))
  assert_true(t.find("界面草图.png") is Some(_))
  // (its size in pixels as its message says it)
  assert_true(t.find("1 / 2 · 18 KB · 图片 · 600×400") is Some(_))
  // no zoom's tools in the bar (−, its per cent, +, 1:1: the user, 2026-11-01), its close the way back (named by the chat)
  for k in ["web-main.preview.zoomOutKey", "web-main.preview.fitKey", "web-main.preview.zoomInKey", "web-main.preview.actualKey"] {
    assert_eq(t.all(Button, label=@sf.t(k)).length(), 0, msg="no zoom's tool in the bar: \{k}")
  }
  assert_true(t.find("100%") is None && t.find("1:1") is None, msg="no zoom's tool in the bar: its per cent, 1:1")
  assert_true(t.find_last("整理发布清单") is Some(_))
  // → the one after
  t.key(@ui.key_code_right)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  assert_true(t.find("2 / 2 · 21 KB · 图片 · 400×560") is Some(_))
  // Esc: gone at once, only drawn fading out
  t.key(@ui.key_escape)
  assert_true(viewer.get() is None)
  t.run_for(pv_fade_ms)
  assert_true(t.find("第二版.png") is None)
}

///|
test "desk: a chat's film says its size, length and rate in the bar as its message does, none of it read yet" {
  let t = desk_tester("chat-preview-video")
  assert_true(t.find("1280×720 · 0:13 · 30 fps") is Some(_))
}

///|
test "desk: a chat's film fitted clear of the bar and the controls, never under them; ⌘ and the wheel zoom it" {
  let t = desk_tester("chat-preview-video")
  let key = viewer.get().unwrap().media.unwrap().key()
  let (top, foot) = @sf.player_room(1280.0)
  let (_, y, w, h) = @sf.player_picture_at(key).unwrap()
  // 1280 × 720 in 1280 × (800 less the bar and the controls): as tall as that leaves, under the bar, over the controls
  assert_true((y - top).abs() < 0.5, msg="\{y} \{top}")
  assert_true((y + h - (800.0 - foot)).abs() < 0.5, msg="\{y + h} \{800.0 - foot}")
  assert_true(w < 1280.0, msg="\{w}")
  t.wheel_with(640.0, 400.0, 0.0, -200.0, @ui.wheel_mod_cmd)
  t.run_for(@ui.move_most_ms)
  let (_, _, w2, _) = @sf.player_picture_at(key).unwrap()
  assert_true(w2 > w * 1.3, msg="\{w} \{w2}")
}

///|
test "desk: Esc closes a chat's film as it flies in, before its player is up" {
  new_run()
  let src = fixture("chat-preview-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms / 4.0)
  assert_true(viewer.get() is Some(_))
  t.key(@ui.key_escape)
  assert_true(viewer.get() is None)
}

///|
test "desk: a click on the image hides the bar, another brings it back; one round it closes the preview" {
  let t = desk_tester("chat-preview-image")
  let v = viewer.get().unwrap()
  // left alone, the bar stays
  t.run_for(left_alone_ms)
  assert_true(v.bars_shown())
  // 600 × 400 in 1280 × 800, fitted 32 in: in the middle as it is
  t.tap(640.0, 400.0)
  t.run_for(double_tap_ms)
  assert_true(viewer.get() is Some(_))
  assert_true(!v.bars_shown())
  t.tap(640.0, 400.0)
  t.run_for(double_tap_ms)
  assert_true(v.bars_shown())
  t.tap(150.0, 700.0)
  assert_true(viewer.get() is None)
}

///|
test "desk: the bar hidden by a click shows while the pointer is along the top, where it is, and hides again past it" {
  let t = desk_tester("chat-preview-image")
  let v = viewer.get().unwrap()
  t.tap(640.0, 400.0)
  t.run_for(double_tap_ms)
  assert_true(!v.bars_shown())
  t.move(640.0, 20.0)
  t.draw()
  assert_true(v.bars_shown())
  t.move(640.0, 400.0)
  t.draw()
  assert_true(!v.bars_shown())
}

///|
test "desk: ⌘ and the wheel (or a pinch) zoom round the pointer, the wheel alone pans; + − 0 1 as the web's keys" {
  let t = desk_tester("chat-preview-image")
  let z = viewer.get().unwrap().zoom
  // 600 × 400 fitted in 1280 × 800: as it is
  assert_true((z.scale - 1.0).abs() < 0.001)
  // fitted, the wheel alone moves nothing
  t.wheel_with(640.0, 400.0, 0.0, 120.0, 0)
  assert_true((z.scale - 1.0).abs() < 0.001)
  // ⌘ and the wheel up: e^(200 × 0.002)
  t.wheel_with(640.0, 400.0, 0.0, -200.0, @ui.wheel_mod_cmd)
  assert_true((z.scale - @dmath.exp(0.4)).abs() < 0.01, msg="\{z.scale}")
  // a pinch (a wheel with ⌃, marked so): its small steps finer
  t.wheel_with(640.0, 400.0, 0.0, -10.0, @ui.wheel_mod_ctrl | @ui.wheel_mod_pinch)
  assert_true((z.scale - @dmath.exp(0.4) * @dmath.exp(0.1)).abs() < 0.01, msg="\{z.scale}")
  // 0 fitted again, + a quarter more (its glide run), 1 as it is
  t.key(@ui.key_of_char('0'))
  t.run_for(@ui.move_most_ms)
  assert_true((z.scale - 1.0).abs() < 0.001, msg="\{z.scale}")
  t.key(@ui.key_of_char('='))
  t.run_for(@ui.move_most_ms)
  assert_true((z.scale - 1.25).abs() < 0.01, msg="\{z.scale}")
  t.key(@ui.key_of_char('1'))
  t.run_for(@ui.move_most_ms)
  assert_true((z.scale - 1.0).abs() < 0.01, msg="\{z.scale}")
}

///|
test "desk: a file told of says so, 下载 the page's button; the bar's own download too" {
  let t = desk_tester("chat-preview-none")
  assert_true(t.find("此文件类型不支持预览") is Some(_))
  assert_true(t.find("4 KB · BIN") is Some(_))
  t.tap_text("下载")
  t.frame()
  // downloaded by the core: how far, in the button's place
  assert_true(t.find("正在下载 0% · 4 KB") is Some(_))
}

///|
test "desk: a chat's Markdown reads in the reader on its paper, the preview's own bar not drawn; Esc closes it" {
  let t = desk_tester("chat-preview-md")
  t.run_for(@sf.reader_place_ms)
  // its words as a document's, its bar the reader's (no 预览 / 源码)
  assert_true(t.find("发布前要做的") is Some(_))
  assert_true(t.find("说明.md") is Some(_))
  assert_true(t.find("源码") is None)
  t.key(@ui.key_escape)
  assert_true(viewer.get() is None)
}

///|
test "desk: a drive's text over the whole window, back to its folder; 目录 docks at the right, Esc shuts it, then goes back" {
  let t = desk_tester("reader")
  t.run_for(@sf.reader_place_ms)
  assert_true(app.nav.top() is DriveRead(_))
  assert_true(t.find("长篇小说.txt") is Some(_))
  // over the sidebar: a press where its rows are is the reader's
  t.tap(140.0, 200.0)
  assert_true(app.nav.top() is DriveRead(_))
  // 目录, the first of its four tools
  t.tap(desk_tool_x(3), 22.0)
  let r = @sf.reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "长篇小说.txt" }))
  assert_true(r.panel == @sf.ReaderPanel::Contents)
  assert_true(t.find("在全文中搜索") is Some(_))
  t.key(@ui.key_escape)
  assert_true(r.panel == @sf.ReaderPanel::NoPanel)
  t.key(@ui.key_escape)
  assert_false(app.nav.top() is DriveRead(_))
}
