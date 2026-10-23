// A text of a drive, read (Screen.DriveRead): the library's reader (@sf.reader, the web's Reader) over a drive's file
// (drive_viewer.mbt): a desktop's over the whole window with the bar every file opened has, back to the folder by
// name; a phone's on its page, its bars a tap brings, its panels the drive's sheets (viewer_host.mbt).

///|
fn reader_key(at : DriveAt) -> String {
  at.station + "\n" + at.root.unwrap_or("") + "\n" + at.path
}

///|
/// The text `at.path` of `at.root` on `at.station`, read.
pub fn reader_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let file = drive_viewer_file(c, src, at)
  @sf.reader(
    c,
    reader_key(at),
    file,
    markdown=@sf.reads_as_markdown(file.name),
    back_label=viewer_folder_label(src, at.station, at.root.unwrap_or(""), dv_parent(at.path)),
    on_back=fn() { app.nav.pop() |> ignore },
  )
}

///|
/// The page left: where it was, kept.
fn reader_left(at : DriveAt) -> Unit {
  @sf.reader_let_go(reader_key(at))
}

///|
/// The paper's darkness while a reader is on top (the system bars' icons readable on it), None otherwise.
fn reader_paper_dark(src : Source) -> Bool? {
  match app.nav.top() {
    DriveRead(_) => Some(@sf.reader_paper(reader_prefs(src).paper).dark)
    _ => None
  }
}
