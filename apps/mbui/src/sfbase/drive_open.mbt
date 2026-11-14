// Where the drive hands a file to be looked at (still.fail apps/android drive/DriveScreen.kt open: pictures, PDFs, code,
// tables, pages in the chat's viewer, FilePreview.kt): the file preview (viewer.mbt), its bytes read by `drive.read`.
// Video and audio go to the player (drive.mbt drive_open pushes DrivePlay: play.mbt); a file handed here
// otherwise plays in the preview's player, reading the same way.

///|
/// `file` of a drive opened to be looked at; `near`: the others of its folder to step to (pictures: the folder's
/// pictures, `file` among them, stepped through and swiped between as a chat's are). `beside`: asked beside the page (a
/// row's menu's 在侧边打开; a list's ⌘ press is a pick of more than one, never this), as open_preview's.
pub fn open_drive_file(file : DriveFile, near : Array[DriveFile], beside? : Bool = false) -> Unit {
  open_preview(file.station, "", drive_attachment(file), drive=Some(file), steps=if near.length() > 1 {
    InFolder(near)
  } else {
    NoSteps
  }, beside~)
}

