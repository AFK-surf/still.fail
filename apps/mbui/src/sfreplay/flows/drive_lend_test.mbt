// 15-drive-lend (e2e/traces/drive-lend.trace: Studio against the local still.fail): 文件 over Home, the files' places
// (个人收藏, the station); ＋ pins another folder through the folder picker (Pin 文件夹: the station's home, its
// folders), the run's own e2e-082940: drive.setRoots with it (Flow::end has it asked as the run asked it), said in a
// toast, then listed under 团队共享.

///|
test "15-drive-lend" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-lend"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.see("个人收藏")
    f.tap("icon:plus")
    f.run_for(@kit.presence_in_ms)
    f.see("共享此文件夹")
    f.tap("e2e-082940")
    f.see("子文件夹")
    f.tap("=共享此文件夹")
    // pinned, said at once (its toast's time its own: looked at as it shows)
    f.see("已共享「e2e-082940」")
    f.run_for(@kit.presence_out_ms)
    f.see("=e2e-082940")
    // the toast gone by itself
    f.run_for(@sfapp.toast_ms)
    f.end()
  })
}
