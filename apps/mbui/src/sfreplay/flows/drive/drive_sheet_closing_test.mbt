// 52-drive-sheet-closing (e2e/traces/drive-sheet-closing.trace, MBUI_OPEN_PAGE=files): a drive sheet let go of: a row
// held, ⋯ → its sheet, the scrim tapped; 重命名 tapped where it is drawn as the sheet goes down is nothing (no rename
// asked: no drive rename in the asks).

///|
test "52-drive-sheet-closing" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_drive_sheet_closing, seed~)
    // 文件 over Home from the start, as the run's MBUI_OPEN_PAGE=files had it
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-084126")
    f.run_for(@ui.nav_push_ms)
    f.see("说明.txt")
    f.hold("说明.txt", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("重命名")
    // the scrim tapped: the sheet sinks, only drawn; 重命名 tapped where it is drawn on its way down asks nothing
    f.tap_at(195.0, 100.0)
    f.tap_at(60.0, -150.0)
    f.tap_at(60.0, -100.0)
    f.tap_at(60.0, -60.0)
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.gone("=保存")
    f.gone("重命名")
    f.end()
  })
}
