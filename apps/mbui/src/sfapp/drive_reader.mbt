// A reader on top as the shell has it (its page sfpages' drive_play.mbt): its paper's darkness for the system bars'
// icons.

///|
/// The paper's darkness while a reader is on top (the system bars' icons readable on it), None otherwise.
fn reader_paper_dark(src : Source) -> Bool? {
  match app.nav.top() {
    DriveRead(_) => Some(@sf.reader_paper(reader_prefs(src).paper).dark)
    _ => None
  }
}
