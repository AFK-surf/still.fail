// Where the drive hands a file to be looked at (ember apps/android drive/DriveScreen.kt open: pictures, PDFs, code,
// tables, pages in the chat's viewer, FilePreview.kt): the file preview (preview.mbt), its bytes read by `drive.read`.
// Video and audio go to the player (drive.mbt drive_open pushes DrivePlay: play.mbt, Player.kt); a file handed here
// otherwise plays in the preview's player, reading the same way.

///|
/// `file` of a drive opened to be looked at; `near`: the others of its folder to step to (pictures: the folder's
/// pictures, `file` among them; otherwise none: stepping is not done here yet).
pub fn open_file(c : @ui.Ctx, src : Source, file : DriveFile, near : Array[DriveFile]) -> Unit {
  ignore(src)
  ignore(near)
  open_preview(
    file.station,
    "",
    {
      name: file.name,
      path: file.path,
      size: file.size,
      width: 0.0,
      height: 0.0,
      thumbhash: "",
      owner: "",
    },
    drive=Some(file),
  )
  c.request_frame()
}
