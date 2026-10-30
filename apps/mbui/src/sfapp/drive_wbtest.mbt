// The drive's pages over the fixture's made-up drive (drive_fixture.mbt; the text as the reader lays it out is the
// library's, src/sf reader_text_wbtest.mbt): 文件, a folder, going in and back, a row held and renamed, deleted, a folder made, a file to the preview, a text read with
// its bars and its contents, a Markdown file read as Markdown and searched.

///|
/// The app over the fixture's drive.
fn drive_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_drive_fixture(mode)
  // (a phone's: a finger)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // the fixture's pages in
  nav_rested(t)
  t
}

///|
/// Frames on to where the pages' slides said they end (@ui.nav_rest: a page pushed, popped or risen).
fn nav_rested(t : @ui.Tester) -> Unit {
  t.draw()
  let e = @ui.nav_rest()
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
}

///|
/// Frames on to where the bottom bar said all of it rests (BarModel::rest: its springs and glides).
fn bar_rested(t : @ui.Tester) -> Unit {
  t.draw()
  let e = bar.rest()
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
}

///|
/// Frames on to where sheet `key` said it is at rest (its springs and its scrim's fade: @kit.sheet_rest).
fn sheet_rested(t : @ui.Tester, key : String) -> Unit {
  t.draw()
  let e = @kit.sheet_rest(key)
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
}

///|
/// Held on `s` (a long press), then let go; what it opened (a presenter's sheet) risen.
fn hold(t : @ui.Tester, s : String) -> Unit {
  let (x, y) = t.find(s).unwrap()
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms)
  t.release(x, y)
  sheet_rested(t, "sf-present")
}

///|
test "文件: the files' places (the wide frame's sidebar's list): 个人收藏, each station with a drive, one away said so; 团队共享 the folders pinned" {
  let t = drive_tester("files")
  for words in ["文件", "个人收藏", "Station", "Studio", "离线", "团队共享", "文档", "照片"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // back says the page under it
  assert_true(t.find("对话") is Some(_))
  t.assert_idle()
}

///|
test "a folder: what it holds in a line, folders first, hidden files left out; in and back by the crumbs" {
  let t = drive_tester("files")
  t.tap_text("文档")
  nav_rested(t)
  assert_true(t.find("2 个文件夹 · 7 个文件") is Some(_))
  assert_true(t.find(".草稿缓存") is None)
  let (_, y1) = t.find("设计稿").unwrap()
  let (_, y2) = t.find("长篇小说.txt").unwrap()
  assert_true(y1 < y2)
  assert_true(t.find("14:05") is Some(_))
  t.tap_text("设计稿")
  assert_eq(app.nav.depth(), 4)
  nav_rested(t)
  assert_true(t.find("配色说明.md") is Some(_))
  // the crumbs: 文档 › 设计稿, the root a way back
  t.tap_text("文档")
  assert_eq(app.nav.depth(), 3)
  nav_rested(t)
  assert_true(t.find("长篇小说.txt") is Some(_))
  // (the bottom bar comes back over the place's pages on its springs: run to where they said they rest)
  bar_rested(t)
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "held: what can be done to it in a sheet (EntrySheet); 重命名 changes its name in place, the folder shows it" {
  let t = drive_tester("drive")
  hold(t, "季度数据.csv")
  let log = t.drive("until 复制路径\nuntil 移到废纸篓\ntap 重命名\nclear\ntype 年度数据.csv\nenter\nuntil 年度数据.csv\n")
  assert_true(log.contains("EXIT 0"))
  assert_true(!@sf.presenting())
  // (its sheet sunk away)
  sheet_rested(t, "sf-present")
  t.draw()
  assert_true(t.find("年度数据.csv") is Some(_))
  assert_true(t.find("季度数据.csv") is None)
  // (重命名's ripple, under the sheet that sank sooner than it fades)
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "held: deleted to the station's trash, said so; 新建文件夹 makes one, named in place" {
  let t = drive_tester("drive")
  hold(t, "合同草稿.pdf")
  let log = t.drive("tap 移到废纸篓\ngone 合同草稿.pdf\nuntil 移到 station 的废纸篓\n")
  assert_true(log.contains("EXIT 0"))
  sheet_rested(t, "sf-present")
  t.click(Button, label="新建文件夹")
  // (made as 未命名文件夹, its name's field in its row at once)
  t.frame()
  let log = t.drive("clear\ntype 新的文件夹\nenter\nuntil 新的文件夹\n")
  assert_true(log.contains("EXIT 0"))
  assert_true(t.find("新的文件夹") is Some(_))
  sheet_rested(t, "sf-present")
  // (a ripple pressed under the sheet that sank sooner than it fades)
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "a picture goes to the preview, read by drive.read" {
  let t = drive_tester("drive")
  let log = t.drive("tap 首页截图.png\n")
  assert_true(log.contains("EXIT 0"))
  // (the run ends at its tap: the preview grows in from its row, and reads it as it does)
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_eq(v.file.name, "首页截图.png")
  assert_true(v.drive is Some(_))
  assert_true(v.bytes.get() is Some(_))
  // kept on the device as read from its start, as its folder lists it (DriveCache.kt; the core's drive-kept.ts)
  let asked = fix_reads.filter(fn(p) { text(Some(p), "path").has_suffix("首页截图.png") })
  assert_true(asked.length() > 0)
  for p in asked {
    assert_eq(text(Some(p), "keep"), "file")
    assert_eq(number(Some(p), "size"), 812345.0)
    assert_eq(number(Some(p), "mtime"), 1792300000000.0 - 812345.0)
  }
  // left alone a while, its bars there still (only a tap hides them)
  t.run_for(left_alone_ms)
  assert_true(v.bars_shown())
  t.assert_idle()
}

///|
test "a text read: where it was left, a tap brings its bars, the contents go to a chapter, the place kept" {
  let t = drive_tester("drive")
  t.tap_text("长篇小说.txt")
  // in, and where it was left waited on (none here)
  nav_rested(t)
  t.run_for(@sf.reader_place_ms)
  assert_true(t.find("上一章") is None)
  t.tap(195.0, 420.0)
  t.run_for(@sf.reader_bars_ms)
  assert_true(t.find("上一章") is Some(_))
  assert_true(t.find("目录") is Some(_))
  t.tap_text("目录")
  sheet_rested(t, "dv-reader-sheet")
  assert_true(t.find("第四章 回程") is Some(_))
  t.tap_text("第四章 回程")
  // the panel sunk away, the jump made, where it is kept once it is still
  sheet_rested(t, "dv-reader-sheet")
  t.run_for(@sf.reader_still_ms)
  assert_true(t.find("第四章 回程") is Some(_))
  // left: where it was, kept on this device
  t.back()
  assert_eq(app.nav.depth(), 3)
  nav_rested(t)
  t.draw()
  match fix_places.get("长篇小说.txt") {
    // at the fourth chapter (a little before it shows too)
    Some(p) => {
      let ch4 = novel_text().find("第四章").unwrap().to_double()
      assert_true(number(Some(p), "at") >= ch4 - 300.0)
      assert_true(number(Some(p), "at") <= ch4 + 50.0)
    }
    None => fail("no place kept: \{fix_places.keys().collect()}")
  }
  t.assert_idle()
}

///|
test "＋'s Station 文件: a file ticked in a folder lent goes into the chat's draft, named by its path" {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  let log = t.drive(
    "tap icon:plus\ntap Station 文件\nuntil 所有位置\nuntil 主目录\ntap =文档\nuntil 整个文件夹\ntap 发布清单.md\ntap 添加 1 个\ngone 所有位置\n",
  )
  assert_true(log.contains("EXIT 0"), msg="\{log}")
  // in the draft as the core keeps it, where it is on the station (sent, the core names it in the message)
  t.draw()
  let files = @sfbase.writing(src, "ws1/st1:s-c1").files
  assert_eq(files.length(), 1)
  assert_eq(text(field(Some(files[0]), "ref"), "path"), "/Users/lin/文档/发布清单.md")
  assert_true(t.find("发布清单") is Some(_))
  // its sheet sunk away
  sheet_rested(t, "sf-present")
}

///|
test "a text read where it was left goes there, then asks for no frame more" {
  // (the fixture's 长篇小说.txt was left at 2400 in every reader mode but `reader`: in its third block)
  let t = drive_tester("reader-bars")
  // the reader's page in, then where it went kept once it holds still
  nav_rested(t)
  t.run_for(@sf.reader_still_ms)
  let r = @sf.reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "长篇小说.txt" }))
  assert_eq(r.jump_step, 0)
  assert_eq(r.chunk, 2)
  t.assert_idle()
}

///|
test "a Markdown file read as a chat's Markdown is drawn, its words searched where they are drawn" {
  let t = drive_tester("reader-md")
  nav_rested(t)
  t.run_for(@sf.reader_place_ms)
  // its marks gone: a heading, a list, inline code, a quote, as Markdown draws them
  assert_true(t.find("发布清单") is Some(_))
  assert_true(t.find("# 发布清单") is None)
  assert_true(t.find("**每一项**") is None)
  assert_true(t.find("release.log") is Some(_))
  // searched: 每一项 is in bold in the text, found as drawn
  let r = @sf.reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "发布清单.md" }))
  r.query = "每一项"
  r.typed_n += 1
  t.draw()
  t.run_for(@sf.reader_search_ms)
  t.draw()
  assert_eq(r.matches.length(), 1)
  assert_eq(r.matches[0].chunk, 0)
  assert_eq(fixture_markdown().view(start_offset=r.matches[0].start).has_prefix("每一项"), true)
}

///|
test "a folder's buttons said to a screen reader: 上传文件, 新建文件夹, 更多操作" {
  let t = drive_tester("drive")
  assert_true(t.query(Button, label="上传文件") is Some(_))
  assert_true(t.query(Button, label="新建文件夹") is Some(_))
  assert_true(t.query(Button, label="更多操作") is Some(_))
}
