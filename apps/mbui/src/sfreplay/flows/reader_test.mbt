// 98-reader (e2e/traces/reader.trace: Mini1 against the local still.fail, 47 messages): the reader's rest. A novel in
// GB18030 read as the Android app reads it (its words, not replacement marks); 下载 in its top bar (the bars shown by a
// tap): the whole file kept on the device; 排版 → 宋体: the serif face kept in the core's prefs (prefs.set reader.face).

///|
test "98-reader" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("reader"), seed~)
    // (put in the lent folder before the app starts: a live run's step, the trace has what came of it)
    f.before("drive-gb 105609")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.tap("旧小说-gb.txt")
    // (the reader in, its push over: a live run taps its text only then)
    f.run_for(@ui.nav_push_ms)
    // its words as written (GB18030 read as such)
    f.see("读出来的字应当和写进去的一样")
    // a tap on the text: the bars
    f.tap_at(195.0, 420.0)
    f.run_for(@sf.reader_bars_ms)
    f.tap("icon:download")
    f.see("已保存到「下载」")
    // the whole file kept, as the station has it (4454 bytes)
    let kept = f.t.kept()
    assert_eq(kept.length(), 1)
    assert_eq(kept[0].0, "旧小说-gb.txt")
    assert_eq(kept[0].2.length(), 4454)
    // the toast's time shown, then its way out
    f.run_for(@sfapp.toast_ms)
    f.t.draw()
    f.run_to(@kit.toast_rest("toast"))
    f.tap("排版")
    f.run_to(@kit.sheet_rest("dv-reader-sheet"))
    f.tap("宋体")
    // the face's segmented choice: its thumb (a cover, @ui's cover.mbt) on its spring to 宋体
    f.run_to(f.t.rest_of("cover.mbt"))
    f.end()
  })
}
