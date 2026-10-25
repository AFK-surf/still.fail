// 18-drive-upload (e2e/traces/drive-upload.trace: against the local still.fail): 上传文件 in the folder the run's 15
// lent (e2e-115455), the system's picker giving a photo and a 9 MB file (MBUI_PICK_FILES; here Tester::picks, the same
// bytes: what each upload's id is made from): each a row going up a part at a time (drive.upload.part, the run's
// parts), then the folder's entries.
// before it: 15-drive-lend

///|
test "18-drive-upload" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-upload"), seed~)
    f.t.picks([("e2e-photo.jpg", @sfreplay.e2e_photo()), ("e2e-data.bin", @sfreplay.e2e_data())])
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-115455")
    f.run_to(@ui.nav_rest())
    f.see("小说-e2e.txt")
    // (the folder's bar: what can be done to it, putting files up the last to leave it)
    f.tap("icon:upload")
    f.see("e2e-data.bin")
    f.see("9.0 MB ·")
    f.see("e2e-photo.jpg")
    f.see("1 个文件夹 · 4 个文件")
    f.end()
  })
}
