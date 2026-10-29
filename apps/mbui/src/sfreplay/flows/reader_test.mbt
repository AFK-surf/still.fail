// 98-reader (e2e/traces/reader.trace: Mini1 against the local still.fail, 47 messages): the reader's rest. A novel in
// GB18030 read as the Android app reads it (its words, not replacement marks); 下载 in its top bar (the bars shown by a
// tap): the whole file kept on the device.

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
    f.run_for(@ui.move_most_ms)
    // its words as written (GB18030 read as such)
    f.see("读出来的字应当和写进去的一样")
    // a tap on the text: the bars
    f.tap_at(195.0, 420.0)
    f.run_for(@sf.reader_bars_ms)
    f.tap("icon:download")
    f.see("已保存到「下载」")
    // the whole file kept, as the station has it (4454 bytes)
    // (saved once the core says it is done with it: a run's script waits for that, the toast says it of any)
    f.answered("download.done", 1)
    // (among what the device keeps, once it has it: the run's downloads before it are on its list too)
    f.until(fn() { f.t.kept().iter().any(fn(k) { k.0 == "旧小说-gb.txt" }) })
    let kept = f.t.kept().filter(fn(k) { k.0 == "旧小说-gb.txt" })
    assert_eq(kept.length(), 1)
    assert_eq(kept[0].2.length(), 4454)
    // the toast's time shown, then its way out
    f.run_for(@sfapp.toast_ms)
    f.t.draw()
    f.run_to(@kit.toast_rest("toast"))
    f.end()
  })
}
