// Where a picture made here goes (the poster of the agents at work, a chat drawn as one long picture, a table):
// copied whole to paste where others see it (a chat, a post), or on a phone (iOS, Android) saved to its photo album,
// where a post or a chat picks it from (2026-10-26 用户：「手机上能复制图片吗？」「是不是应该是下载」「保存」). Handed
// out by the pages (sfpages picture_out), which keep it as the album has it.

///|
/// Whether a picture goes to the photo album here (a phone's), else to the clipboard.
pub fn picture_to_album() -> Bool {
  @ui.platform() == 1 || @ui.platform() == 2
}

///|
/// What the button that hands a picture out says, and its icon: 复制图片, or on a phone 保存到相册.
pub fn picture_out_way() -> (String, String) {
  if picture_to_album() {
    (t("web-main.stations.saveToPhotos"), "download")
  } else {
    (t("desktop.contextMenu.copyImage"), "copy")
  }
}

///|
/// A picture made here (`png`; None: it could not be made) handed out as picture_out_way says, what came of it said
/// (that it was copied, not where what handed it out says so itself: the third), true once it is out: sfpages'
/// picture_out, given as the app starts; till then (a page drawn alone) copied, nothing said.
// kept across runs: what the app says once as it starts
pub let picture_out_by : Ref[(@ui.Ctx, Bytes?, Bool) -> Bool] = Ref(fn(_, png, _) {
  match png {
    Some(png) => {
      @ui.clipboard_set_png(png, label="still.fail")
      true
    }
    None => false
  }
})
