// 19-drive-rename (e2e/traces/drive-rename.trace: Studio against the local still.fail): in the lent folder the photo
// the run's 18 put up held (a long press): chosen; ⋯ → 重命名, the name changed in its field and saved (drive.rename
// from the old name to the new: Flow::end has it asked as the run asked it).

///|
test "19-drive-rename" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-rename"), seed~)
    // (the photo 18's upload left, put there before the app starts: the run apart from 18's)
    f.before("drive-photo 082940")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.hold("e2e-photo.jpg", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.tap("重命名")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("=保存")
    f.tap("e2e-photo.jpg")
    f.clear()
    f.type_text("照片-082940.jpg")
    f.tap("=保存")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("照片-082940.jpg")
    f.gone("e2e-photo.jpg")
    f.end()
  })
}
