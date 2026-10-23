// The file viewers on a desktop (viewer_bar.mbt, preview_desk.mbt, reader_desk.mbt): over the wide frame's whole
// window, as the desktop app's (FilePreview.tsx docked, viewer/Reader.tsx with a mouse).

///|
/// The fixture's `mode` in a desktop's window: a chat's file open in its preview (chat-preview-…), a drive's text read
/// (reader…), seen once it is in.
fn desk_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  if mode.has_prefix("chat-preview") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  t.draw()
  if mode.has_prefix("reader") || mode.has_prefix("player") {
    // (what the mode opens: 文档 and the file in it)
    app.nav.replace(Home)
    open_drive_fixture(mode)
    t.run_for(@ui.nav_push_ms)
  } else {
    t.run_for(fly_open_ms)
  }
  t
}

///|
/// Where a tool of the bar is, by how many from its end (download 0): 12 in from the window's side, 32 each, 2 apart.
fn desk_tool_x(from_end : Int) -> Double {
  1280.0 - 12.0 - 16.0 - from_end.to_double() * 34.0
}

///|
test "desk: an image on the canvas under the bar, back to its chat by name, which of two, its size and kind; → steps, Esc closes" {
  let t = desk_tester("chat-preview-step")
  assert_true(wide_on.val)
  assert_true(t.find("界面草图.png") is Some(_))
  assert_true(t.find("1 / 2 · 18 KB · 图片") is Some(_))
  // the zoom's tools in the bar, its close the way back (named by the chat)
  assert_true(t.find("100%") is Some(_))
  assert_true(t.find("1:1") is Some(_))
  assert_true(t.find_last("整理发布清单") is Some(_))
  // → the one after
  t.key(@ui.key_code_right)
  assert_eq(viewer.val.unwrap().file.name, "第二版.png")
  assert_true(t.find("2 / 2 · 21 KB · 图片") is Some(_))
  // Esc: gone at once, only drawn fading out
  t.key(@ui.key_escape)
  assert_true(viewer.val is None)
  t.run_for(pv_fade_ms)
  assert_true(t.find("第二版.png") is None)
}

///|
test "desk: a click on the image does nothing, one round it closes the preview" {
  let t = desk_tester("chat-preview-image")
  // 600 × 400 in 1280 × 800, fitted 32 in: in the middle as it is
  t.tap(640.0, 400.0)
  t.run_for(double_tap_ms)
  assert_true(viewer.val is Some(_))
  t.tap(150.0, 700.0)
  assert_true(viewer.val is None)
}

///|
test "desk: a file told of says so, 下载 the page's button; the bar's own download too" {
  let t = desk_tester("chat-preview-none")
  assert_true(t.find("此文件类型不支持预览") is Some(_))
  assert_true(t.find("4 KB · BIN") is Some(_))
  t.tap_text("下载")
  assert_true(viewer.val.unwrap().asked)
}

///|
test "desk: a chat's Markdown reads in the reader on its paper, the preview's own bar not drawn; Esc closes it" {
  let t = desk_tester("chat-preview-md")
  t.run_for(reader_place_ms)
  // its words as a document's, its bar the reader's (no 预览 / 源码)
  assert_true(t.find("发布前要做的") is Some(_))
  assert_true(t.find("说明.md") is Some(_))
  assert_true(t.find("源码") is None)
  t.key(@ui.key_escape)
  assert_true(viewer.val is None)
}

///|
test "desk: a drive's text over the whole window, back to its folder; 目录 docks at the right, Esc shuts it, then goes back" {
  let t = desk_tester("reader")
  t.run_for(reader_place_ms)
  assert_true(app.nav.top() is DriveRead(_))
  assert_true(t.find("长篇小说.txt") is Some(_))
  // over the sidebar: a press where its rows are is the reader's
  t.tap(140.0, 200.0)
  assert_true(app.nav.top() is DriveRead(_))
  // 目录, the first of its four tools
  t.tap(desk_tool_x(3), 22.0)
  let r = reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "长篇小说.txt" }))
  assert_true(r.panel == Contents)
  assert_true(t.find("在全文中搜索") is Some(_))
  t.key(@ui.key_escape)
  assert_true(r.panel == NoPanel)
  t.key(@ui.key_escape)
  assert_false(app.nav.top() is DriveRead(_))
}
