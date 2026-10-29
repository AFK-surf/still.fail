// 52-drive-sheet-closing (e2e/traces/drive-sheet-closing.trace, MBUI_OPEN_PAGE=files): what can be done to a row let
// go of: right clicked, its menu beside the pointer; a press beside the menu closes it, and 重命名 where it was drawn
// asks nothing (no drive rename in the asks).

///|
test "52-drive-sheet-closing" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-sheet-closing"), seed~)
    // 文件 over Home from the start, as the run's MBUI_OPEN_PAGE=files had it
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-084126")
    f.run_for(@ui.move_most_ms)
    f.see("说明.txt")
    f.right_click("说明.txt")
    f.run_for(@kit.presence_in_ms)
    f.see("重命名")
    // pressed beside it: the menu goes
    f.tap_at(195.0, 100.0)
    f.run_for(@kit.presence_out_ms)
    f.gone("=保存")
    f.gone("重命名")
    f.end()
  })
}
