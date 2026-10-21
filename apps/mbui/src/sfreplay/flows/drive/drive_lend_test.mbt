// 15-drive-lend (e2e/traces/drive-lend.trace: Studio against the local still.fail): 文件 over Home, the station's
// home; ＋ lends another folder through the folder picker (the station's home, its folders), the run's own
// e2e-082940: drive.setRoots with it (Flow::end has it asked as the run asked it), said in a toast, then listed.

///|
test "15-drive-lend" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_drive_lend, seed~)
    f.open_page(@sfapp.Page::Files)
    f.see("主目录")
    f.tap("icon:plus")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("选择文件夹")
    f.tap("e2e-082940")
    f.see("子文件夹")
    f.tap("=选择此文件夹")
    // lent, said at once, the sheet still going down (its toast's time its own: looked at as it shows)
    f.see("已开放「e2e-082940」")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.see("=e2e-082940")
    // the toast gone by itself
    f.run_for(@sfapp.toast_ms)
    f.end()
  })
}
