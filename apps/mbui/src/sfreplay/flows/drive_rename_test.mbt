// 19-drive-rename (e2e/traces/drive-rename.trace: Studio against the local still.fail): in the lent folder the photo
// the run's 18 put up right clicked: 重命名, its new name typed in its row (⏎) (drive.check, then drive.rename from the
// old name to the new: Flow::end has it asked as the run asked it).

///|
test "19-drive-rename" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-rename"), seed~)
    // (the photo 18's upload left, put there before the app starts: the run apart from 18's)
    f.before("drive-photo 082940")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.right_click("e2e-photo.jpg")
    f.run_for(@kit.presence_in_ms)
    f.tap("重命名")
    // (its name changed in its row: the field there, its name picked but its extension)
    f.run_for(@kit.presence_out_ms)
    f.clear()
    f.type_text("照片-082940.jpg")
    f.enter()
    f.see("照片-082940.jpg")
    f.gone("e2e-photo.jpg")
    f.end()
  })
}
