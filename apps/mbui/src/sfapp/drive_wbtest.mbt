// The drive's text model (drive_text.mbt, as TextModel.kt's tests check it) and its pages over the fixture's made-up
// drive (drive_fixture.mbt): 文件, a folder, going in and back, a row held and renamed, deleted, a folder made, a
// file to the preview, a text read with its bars and its contents.

///|
fn utf8_of(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
test "decoding: UTF-8, its byte order mark, UTF-16, a character cut at the end" {
  assert_eq(@hostapi.decode_text(utf8_of("第一章 开始")).0, "第一章 开始")
  let bom = Bytes::from_array([b'\xEF', b'\xBB', b'\xBF', b'a', b'b'][:])
  assert_eq(@hostapi.decode_text(bom), ("ab", "UTF-8 BOM"))
  let le = Bytes::from_array([b'\xFF', b'\xFE', b'\x2C', b'\x7B', b'a', b'\x00'][:])
  assert_eq(@hostapi.decode_text(le), ("第a", "UTF-16LE"))
  // 第 is E7 AC AC: its last byte cut off the front of a bigger file
  let cut = Bytes::from_array([b'a', b'\xE7', b'\xAC'][:])
  assert_eq(@hostapi.decode_text(cut, truncated=true), ("a", "UTF-8"))
  // a half-copied file is still UTF-8
  assert_eq(@hostapi.decode_text(cut), ("a", "UTF-8"))
}

///|
test "decoding: a file that is not UTF-8 read as GB18030 (第一章 开始)" {
  // (as a Tester's host decodes it: the system's tables are a host's own)
  @ui.Tester::new(fn(_) {  }) |> ignore
  // 第 B5DA, 一 D2BB, 章 D5C2, a space, 开 BFAA, 始 CABC
  let gb = Bytes::from_array(
    [b'\xB5', b'\xDA', b'\xD2', b'\xBB', b'\xD5', b'\xC2', b' ', b'\xBF', b'\xAA', b'\xCA', b'\xBC'][:],
  )
  assert_eq(@hostapi.decode_text(gb), ("第一章 开始", "GB18030"))
  // the front of a bigger file, its last character cut in half: dropped
  let cut = Bytes::from_array([b'\xB5', b'\xDA', b'\xD2'][:])
  assert_eq(@hostapi.decode_text(cut, truncated=true), ("第", "GB18030"))
}

///|
test "chapters: 第…章, front matter, Chapter N; a stray title-like line only far enough from the last" {
  let text = "序章\n很久以前的事。\n第一章 车站\n他到了。\n第 12 节\n又一节。\nChapter 3 The Key\nwords.\n正文 第三卷 回程\n"
  let marks = find_chapters(text, weak=false)
  assert_eq(marks.map(fn(m) { m.title }), ["序章", "第一章 车站", "第 12 节", "Chapter 3 The Key", "正文 第三卷 回程"])
  assert_eq(marks[1].offset, text.find("第一章").unwrap())
  // not a heading: a sentence that starts with 第
  assert_eq(find_chapters("第一次见到他的时候，天已经黑了，路上一个人也没有。\n", weak=false).length(), 0)
}

///|
test "a hard-wrapped text is reflowed into its paragraphs; a heading stays its own" {
  let line = "这一行正好二十五个字这一行正好二十五个字这一行正好二"
  let lines = []
  for i in 0..<14 {
    lines.push(if i % 4 == 3 { "结束了。" } else { line })
  }
  let text = "第一章 开头\n" + lines.join("\n")
  let wrap = detect_wrap_width(text)
  assert_eq(wrap, line.length())
  let keep : Map[Int, Bool] = Map([])
  for m in find_chapters(text, weak=false) {
    keep[m.offset] = true
  }
  let flowed = reflow(text, wrap, keep)
  let paras = flowed.split("\n").map(fn(p) { p.to_owned() }).to_array()
  assert_eq(paras[0], "第一章 开头")
  assert_eq(paras[1], line + line + line + "结束了。")
  // paragraph-per-line text is left alone
  assert_eq(detect_wrap_width("短的一行。\n另一行，长一点点的。\n"), 0)
}

///|
test "blocks: cut at paragraph ends within the budget, found again by offset" {
  let p = "一二三四五六七八九十。\n"
  let text = p.repeat(30)
  let (chunks, starts) = chunk_text(text, budget=100)
  assert_true(chunks.length() > 1)
  assert_eq(chunks.iter().fold(init="", fn(a, s) { a + s }), text)
  for c in chunks {
    assert_true(c.length() <= 100)
    assert_true(c.has_suffix("\n"))
  }
  assert_eq(chunk_index_for(starts, starts[2] + 3), 2)
}

///|
test "indents: a paragraph's own spacing replaced by two ideographic spaces, a heading left; offsets follow" {
  let chunk = "第一章 车站\n  他到了。\n\u{3000}\u{3000}她也到了。\n"
  let drawn = render_chunk(chunk, true)
  assert_eq(drawn, "第一章 车站\n\u{3000}\u{3000}他到了。\n\u{3000}\u{3000}她也到了。\n")
  let raw = chunk.find("他").unwrap()
  assert_eq(drawn.view(start_offset=render_offset(chunk, raw, true)).has_prefix("他"), true)
  let raw2 = chunk.find("她").unwrap()
  assert_eq(drawn.view(start_offset=render_offset(chunk, raw2, true)).has_prefix("她"), true)
}

///|
test "search: every place, by block; letters ignoring case when nothing else was found" {
  let hits = search_chunks(["钥匙在这里，钥匙也在那里", "没有", "Key and key"], "钥匙")
  assert_eq(hits.map(fn(m) { (m.chunk, m.start) }), [(0, 0), (0, 6)])
  assert_eq(search_chunks(["Key and KEY"], "key").length(), 2)
}

///|
test "Markdown: drawn as runs, its marks gone, the way back to the raw offsets" {
  let md = render_markdown("# 标题\n\n- 一项 **重要**\n> 引用\n", 0x888888FFL, 0xE5704AFFL, 0x444444FFL)
  let drawn = md.runs.iter().fold(init="", fn(a, r) { a + r.text })
  assert_eq(drawn, "标题\n\n• 一项 重要\n▎ 引用\n")
  assert_eq(md.raw_of.length(), drawn.length())
  assert_true(md.runs.iter().any(fn(r) { r.text == "重要" && r.weight == 600 }))
  assert_eq(md.leading, 16.0)
  let raw = "# 标题\n\n- 一项 **重要**\n> 引用\n".find("重要").unwrap()
  assert_eq(drawn.view(start_offset=md.rendered_index(raw)).has_prefix("重要"), true)
  assert_eq(markdown_chapters("# 一\n```\n# 不是\n```\n## 二\n#### 太深\n").map(fn(m) { m.title }), ["一", "二"])
}

///|
test "a novel built: blocks, chapters by block, an offset found again" {
  let novel = build_novel("小说.txt", utf8_of(novel_text()), false)
  assert_eq(novel.chapters.length(), 5)
  assert_eq(novel.chapters[1].0, "第二章 旧仓库")
  let (k, o) = novel.at(3000)
  assert_eq(novel.starts[k] + o, 3000)
  assert_eq(novel.offset_of(k, 0.0), novel.starts[k])
}

///|
/// The app over the fixture's drive.
fn drive_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
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
/// Held on `s` (a long press), then let go.
fn hold(t : @ui.Tester, s : String) -> Unit {
  let (x, y) = t.find(s).unwrap()
  t.press_at(x, y)
  t.run_for(dv_hold_ms)
  t.release(x, y)
}

///|
test "文件: each station's home and folders lent under its name; one away faint, said so" {
  let t = drive_tester("files")
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.find("主目录") is Some(_))
  assert_true(t.find("文档") is Some(_))
  assert_true(t.find("备份盘") is Some(_))
  assert_true(t.find("MBA · 离线") is Some(_))
  assert_true(t.find("照片") is Some(_))
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
test "held: chosen; its sheet renames it, the folder shows the new name" {
  let t = drive_tester("drive")
  hold(t, "季度数据.csv")
  assert_true(t.find("已选 1 项") is Some(_))
  let log = t.drive("tap icon:more\nuntil 复制路径\nuntil 移到废纸篓\ntap 重命名\nuntil 保存\ntap 季度数据.csv\nclear\ntype 年度数据.csv\ntap 保存\ngone 保存\n")
  assert_true(log.contains("EXIT 0"))
  assert_true(dv.sheet is NoSheet)
  // (its sheet sunk away)
  sheet_rested(t, "dv-sheet")
  assert_true(t.find("年度数据.csv") is Some(_))
  assert_true(t.find("季度数据.csv") is None)
  assert_true(t.find("已选 1 项") is None)
  t.assert_idle()
}

///|
test "deleted to the station's trash, said so; a new folder made" {
  let t = drive_tester("drive")
  hold(t, "合同草稿.pdf")
  let log = t.drive("tap icon:more\ntap 移到废纸篓\ngone 合同草稿.pdf\nuntil 已移到 station 的废纸篓\n")
  assert_true(log.contains("EXIT 0"))
  let log = t.drive("tap icon:plus\ntap 新建文件夹\ntap 文件夹名\ntype 新的文件夹\ntap =新建\nuntil 新的文件夹\n")
  assert_true(log.contains("EXIT 0"))
  assert_true(t.find("新的文件夹") is Some(_))
  sheet_rested(t, "dv-sheet")
  t.assert_idle()
}

///|
test "a picture goes to the preview, read by drive.read" {
  let t = drive_tester("drive")
  let log = t.drive("tap 首页截图.png\n")
  assert_true(log.contains("EXIT 0"))
  // (the run ends at its tap: the preview grows in from its row, and reads it as it does)
  t.run_for(fly_open_ms)
  let v = viewer.val.unwrap()
  assert_eq(v.file.name, "首页截图.png")
  assert_true(v.drive is Some(_))
  assert_true(v.bytes is Some(_))
  // kept on the device as read from its start, as its folder lists it (DriveCache.kt; the core's drive-kept.ts)
  let asked = fix_reads.filter(fn(p) { text(Some(p), "path").has_suffix("首页截图.png") })
  assert_true(asked.length() > 0)
  for p in asked {
    assert_eq(text(Some(p), "keep"), "file")
    assert_eq(number(Some(p), "size"), 812345.0)
    assert_eq(number(Some(p), "mtime"), 1792300000000.0 - 812345.0)
  }
  // its bars, left alone, go
  t.run_for(rest_ms)
  t.assert_idle()
}

///|
test "a text read: where it was left, a tap brings its bars, the contents go to a chapter, the place kept" {
  let t = drive_tester("drive")
  t.tap_text("长篇小说.txt")
  // in, and where it was left waited on (none here)
  nav_rested(t)
  t.run_for(reader_place_ms)
  assert_true(t.find("上一章") is None)
  t.tap(195.0, 420.0)
  t.run_for(reader_bars_ms)
  assert_true(t.find("上一章") is Some(_))
  assert_true(t.find("目录") is Some(_))
  t.tap_text("目录")
  sheet_rested(t, "dv-reader-sheet")
  assert_true(t.find("第四章 回程") is Some(_))
  t.tap_text("第四章 回程")
  // the panel sunk away, the jump made, where it is kept once it is still
  sheet_rested(t, "dv-reader-sheet")
  t.run_for(reader_still_ms)
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
    None => fail("no place kept: \{fix_places.keys().collect()} \{reader_ui.length()} \{dv_reads.length()}")
  }
  t.assert_idle()
}

///|
test "＋'s Station 文件: a file ticked in a folder lent goes into the draft, and with the message as its path" {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  let log = t.drive(
    "tap icon:plus\ntap Station 文件\nuntil 所有位置\nuntil 主目录\ntap =文档\nuntil 整个文件夹\ntap 发布清单.md\ntap 添加 1 个\ngone 所有位置\nuntil Studio · 路径\ntap icon:arrow-up\nuntil Studio 上的文件：/Users/lin/文档/发布清单.md\n",
  )
  assert_true(log.contains("EXIT 0"))
  assert_eq(refs_of("ws1/st1:s-c1").length(), 0)
  // its sheet sunk away, the words sent flown to their row; the station takes them in, its agent answers, its turn
  // ends (the fixture's times: the run ends as it sends)
  sheet_rested(t, "dv-reader-sheet")
  t.run_for(flight_ms)
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms)
  t.assert_idle()
}

///|
test "a text read where it was left goes there, then asks for no frame more" {
  // (the fixture's 长篇小说.txt was left at 2400 in every reader mode but `reader`: in its third block)
  let t = drive_tester("reader-bars")
  // the reader's page in, then where it went kept once it holds still
  nav_rested(t)
  t.run_for(reader_still_ms)
  let r = reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "长篇小说.txt" }))
  assert_eq(r.jump_step, 0)
  assert_eq(r.chunk, 2)
  t.assert_idle()
}

///|
test "a folder's buttons said to a screen reader as Android's: 刷新, 添加, 显示方式" {
  let t = drive_tester("drive")
  t.tap_text("文档")
  nav_rested(t)
  assert_true(t.query(Button, label="刷新") is Some(_))
  assert_true(t.query(Button, label="添加") is Some(_))
  assert_true(t.query(Button, label="显示方式") is Some(_))
}
