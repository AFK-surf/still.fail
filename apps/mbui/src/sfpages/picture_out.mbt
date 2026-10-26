// A picture made here handed out (the poster of the agents at work, a chat drawn as one long picture): copied whole to
// paste where others see it (a chat, a post), or on a phone (iOS, Android) saved to its photo album, where a post or a
// chat picks it from (2026-10-26 用户：「手机上能复制图片吗？」「是不是应该是下载」「保存」).

///|
/// Whether a picture goes to the photo album here (a phone's), else to the clipboard.
fn picture_to_album() -> Bool {
  @ui.platform() == 1 || @ui.platform() == 2
}

///|
/// What the button that hands a picture out says, and its icon: 复制图片, or on a phone 保存到相册.
pub fn picture_out_way() -> (String, String) {
  if picture_to_album() {
    (@sf.t("web-main.stations.saveToPhotos"), "download")
  } else {
    (@sf.t("desktop.contextMenu.copyImage"), "copy")
  }
}

///|
/// The picture `png` handed out as its button says (picture_out_way), what came of it said; None: it could not be
/// made.
pub fn picture_out(c : @ui.Ctx, png : Bytes?) -> Unit {
  let album = picture_to_album()
  match png {
    None => say(c, @sf.t(if album { "web-main.stations.saveToPhotosFailed" } else { "web-main.stations.shareFailed" }))
    Some(png) if album =>
      @sfbase.keep_bytes(
        c,
        "still.fail.png",
        "image/png",
        png,
        way=Photos,
        saved=@sf.t("web-main.stations.savedToPhotos"),
        failed=@sf.t("web-main.stations.saveToPhotosFailed"),
      )
    Some(png) => {
      @ui.clipboard_set_png(png, label="still.fail")
      if !@ui.copy_shown() {
        say(c, @sf.t("common.copied"))
      }
    }
  }
}
