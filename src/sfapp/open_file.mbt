// Where the drive hands a file to be looked at (ember apps/android drive/DriveScreen.kt open: pictures, PDFs, code,
// tables, pages, subtitles in the chat's viewer, FilePreview.kt; video and audio in the player, Player.kt; anything
// else to another app). The file preview (slice 11, branch `preview`) fills this in; until it does, it says there is
// no preview yet.

///|
/// `file` of a drive opened to be looked at; `near`: the others of its folder to step to (pictures: the folder's
/// pictures, `file` among them; otherwise none).
pub fn open_file(c : @ui.Ctx, src : Source, file : DriveFile, near : Array[DriveFile]) -> Unit {
  ignore(src)
  ignore(near)
  ignore(file)
  say(c, tr("android-chat.file.noPreview"))
}
