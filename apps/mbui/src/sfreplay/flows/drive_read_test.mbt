// 17-drive-read (e2e/traces/drive-read.trace: Studio against the local still.fail): a text of the lent folder read
// (drive.read): its chapters found, the bars a tap away, the contents going to a chapter; where it was left told to
// the core once the reader held still (drive.place, past the first two chapters: Flow::end has it asked as the run
// asked it), and its row says how far.

///|
test "17-drive-read" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-read"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.tap("小说-e2e.txt")
    // (the reader in, its push over: a live run taps its text only then)
    f.run_for(@ui.move_most_ms)
    // a tap on the text: the bars
    f.tap_at(195.0, 420.0)
    f.run_for(@sf.reader_bars_ms)
    f.see("目录")
    f.see("下一章")
    f.see("第一章 雨后的车站")
    f.tap("目录")
    f.run_to(@kit.sheet_rest("dv-reader-sheet"))
    f.see("第三章 灯塔的钥匙")
    f.tap("第三章 灯塔的钥匙")
    f.run_to(@kit.sheet_rest("dv-reader-sheet"))
    f.gone("第四章 回程")
    // held still there: where it is told to the core
    f.run_for(@sf.reader_still_ms)
    f.back()
    f.run_to(@ui.nav_rest())
    f.see("小说-e2e.txt")
    f.see("%")
    f.end()
  })
}
