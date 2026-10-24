// 20-drive-delete (e2e/traces/drive-delete.trace: Studio against the local still.fail): the file 19 renamed right
// clicked: what can be done to it beside the pointer; the bin: the test station has no trash for the drive, so it asks
// first (删除「…」？) and deletes it for good (drive.remove with permanent: Flow::end has it asked as the run asked it).

///|
test "20-drive-delete" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-delete"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.right_click("照片-082940.jpg")
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
