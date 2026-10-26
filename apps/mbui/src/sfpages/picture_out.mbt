// A picture made here handed out (the poster of the agents at work, a chat drawn as one long picture, a table): as
// @sf.picture_out_way says, copied or on a phone saved to its photo album (@sf picture_out.mbt), given to the library
// as the app starts (pages.mbt).

///|
/// The picture `png` handed out as its button says (@sf.picture_out_way), what came of it said (that it was copied, not
/// where the button says so itself: `copy_said`); None: it could not be made. True once it is out.
pub fn picture_out(c : @ui.Ctx, png : Bytes?, copy_said? : Bool = false) -> Bool {
  let album = @sf.picture_to_album()
  match png {
    None => {
      say(c, @sf.t(if album { "web-main.stations.saveToPhotosFailed" } else { "web-main.stations.shareFailed" }))
      false
    }
    Some(png) if album => {
      @sfbase.keep_bytes(
        c,
        "still.fail.png",
        "image/png",
        png,
        way=Photos,
        saved=@sf.t("web-main.stations.savedToPhotos"),
        failed=@sf.t("web-main.stations.saveToPhotosFailed"),
      )
      true
    }
    Some(png) => {
      @ui.clipboard_set_png(png, label="still.fail")
      if !@ui.copy_shown() && !copy_said {
        say(c, @sf.t("common.copied"))
      }
      true
    }
  }
}
