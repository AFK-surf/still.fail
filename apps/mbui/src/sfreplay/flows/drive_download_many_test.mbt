// 91-drive-download-many (e2e/traces/drive-download-many.trace: against the local still.fail): several files downloaded
// at once (FolderView manyItems: 下载 2 个文件) from a folder of their own (drive-big), in a desktop's window (the files'
// page wide: what is chosen several at a time, ⌘A): one of them 48 MB, read a part at a time (drive.read, 4 MB each);
// each kept (@ui.keep_begin), each said. (The run's trace keeps none of the big file's bytes: that a file is kept byte
// for byte is the end-to-end smoke's, 90-drive-download.)

///|
test "91-drive-download-many" {
  replay_drive_download_many()
}

///|
fn replay_drive_download_many() -> Unit raise {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-download-many"), seed~, w=1280.0, h=800.0)
    // (put in the lent folder before the app starts: a live run's step, the trace has what came of it)
    f.before("drive-big 105609")
    f.open_page(@sfapp.Page::Files)
    // The favorite and the folder in the station's home can both be visible. Open the favorite.
    f.see_n(2, "=e2e-105609")
    f.tap("=e2e-105609", top=true)
    f.run_for(@ui.move_most_ms)
    // A folder in the wide list opens on a double click.
    f.see("=大文件")
    f.tap("=大文件")
    f.tap("=大文件")
    f.run_for(@ui.move_most_ms)
    f.see("大文件.bin")
    f.tap("大文件.bin")
    f.key("cmd+a")
    f.right_click("大文件.bin")
    f.run_for(@kit.presence_in_ms)
    f.see("下载 2 个文件")
    f.tap("下载 2 个文件")
    // its toast, up as the download begins (looked for then: how long the parts take is the run's own, the toast's
    // time its own, and one may outlast the other)
    f.see("已保存到「下载」")
    // both kept, each whole as the run read it: the small one's 40 bytes, the big one's parts all taken in
    // (both saved once the core says it is done with each: a run's script waits for that)
    f.answered("download.done", 2)
    f.until(fn() {
      let names = f.t.kept().map(fn(k) { k.0 })
      names.contains("大文件.bin") && names.contains("附件.txt")
    })
    let kept = f.t.kept().map(fn(k) { k.0 })
    assert_true(kept.contains("大文件.bin"))
    assert_true(kept.contains("附件.txt"))
    assert_eq(f.t.kept().filter(fn(k) { k.0 == "附件.txt" })[0].2.length(), 40)
    // its toast, up since the download began, its time shown
    f.run_for(@sfapp.toast_ms)
    f.end()
  })
}
