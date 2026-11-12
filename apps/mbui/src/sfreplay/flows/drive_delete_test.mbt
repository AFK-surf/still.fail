// 20-drive-delete (e2e/traces/drive-delete.trace: Mac against the local still.fail): the file 19 renamed held
// (a phone's): what can be done to it; the bin: the test station has no trash for the drive, so it asks
// first (删除「…」？) and deletes it for good (drive.remove with permanent: Flow::end has it asked as the run asked it).
// before it: 15-drive-lend

///|
test "20-drive-delete" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-delete"), seed~)
    // The renamed photo is the starting state when this flow runs on its own.
    f.before("drive-photo 082940 renamed")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest)
    f.hold("照片-082940.jpg", @ui.long_press_ms)
    f.run_for(@kit.presence_in_ms)
    f.see("复制路径")
    f.tap("icon:trash")
    f.run_for(@kit.presence_in_ms)
    f.see("删除「照片-082940.jpg」？")
    f.tap("=删除")
    f.run_for(@kit.presence_out_ms)
    f.gone("照片-082940.jpg")
    f.end()
  })
}
