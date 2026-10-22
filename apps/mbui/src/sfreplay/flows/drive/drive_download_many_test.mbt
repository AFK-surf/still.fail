// 91-drive-download-many (e2e/traces/drive-download-many.trace: Mini1 against the local still.fail, 76 messages):
// several files downloaded at once (DriveScreen.kt openChosenSheet: 下载 2 个文件) from a folder of their own
// (drive-big): one of them 48 MB, read a part at a time (drive.read, 4 MB each), how far it has come on its row
// meanwhile; each kept (@ui.keep_begin), each said. (The run's trace keeps none of the big file's bytes: that a file is
// kept byte for byte is the end-to-end smoke's, 90-drive-download.)

///|
test "91-drive-download-many" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-download-many"), seed~)
    // (put in the lent folder before the app starts: a live run's step, the trace has what came of it)
    f.before("drive-big 105609")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.tap("=大文件")
    f.run_to(@ui.nav_rest())
    f.hold("大文件.bin", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("附件.txt")
    f.see("已选 2 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.tap("下载 2 个文件")
    // its toast, up as the download begins (looked for then: how long the parts take is the run's own, the toast's
    // time its own, and one may outlast the other)
    f.see("已保存到「下载」")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.gone("%")
    // both kept, each whole as the run read it: the small one's 40 bytes, the big one's parts all taken in
    let kept = f.t.kept().map(fn(k) { k.0 })
    assert_true(kept.contains("大文件.bin"))
    assert_true(kept.contains("附件.txt"))
    assert_eq(f.t.kept().filter(fn(k) { k.0 == "附件.txt" })[0].2.length(), 40)
    // its toast, up since the download began (the sheet still going down), its time shown and gone
    f.run_for(@sfapp.toast_ms)
    // (its time counted from the frame after it showed, @kit.toaster's `after(later=true)`: out a frame on, then gone)
    f.run_for(@sfreplay.frame_ms)
    f.run_to_rest("toast")
    f.end()
  })
}
