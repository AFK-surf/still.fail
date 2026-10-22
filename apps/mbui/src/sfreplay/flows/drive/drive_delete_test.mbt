// 20-drive-delete (e2e/traces/drive-delete.trace: Studio against the local still.fail): the file 19 renamed held,
// ⋯ → the bin: the test station has no trash for the drive, so it asks first (删除「…」？) and deletes it for good
// (drive.remove with permanent: Flow::end has it asked as the run asked it).

///|
test "20-drive-delete" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-delete"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.hold("照片-082940.jpg", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("复制路径")
    f.tap("icon:trash")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("删除「照片-082940.jpg」？")
    f.tap("=删除")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.gone("照片-082940.jpg")
    f.end()
  })
}
