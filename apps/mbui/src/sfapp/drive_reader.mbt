// A text of a drive, read (Screen.DriveRead): the library's reader (@sf.reader, the web's Reader) over a drive's file
// (sfbase drive_viewer.mbt) on the phone's page, its bars a tap brings, its panels the drive's sheets (viewer_host.mbt).

///|
/// The text `at.path` of `at.root` on `at.station`, read.
pub fn reader_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  drive_reader(c, src, at, fn() { @sfbase.close_page(DriveRead(at)) |> ignore })
}

///|
/// The paper's darkness while a reader is on top (the system bars' icons readable on it), None otherwise.
fn reader_paper_dark(src : Source) -> Bool? {
  match app.nav.top() {
    DriveRead(_) => Some(@sf.reader_paper(reader_prefs(src).paper).dark)
    _ => None
  }
}
