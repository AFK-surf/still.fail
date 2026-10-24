// A video or a song of a station's drive, played (Screen.DrivePlay, pushed from a folder's row): the library's player
// (@sf.player: opened where it was left on this device, the subtitle beside it, where it is kept as it plays) on the
// phone's page over a drive's file (sfbase drive_viewer.mbt: its bytes read through the core a part at a time, never
// the whole file first), the folder (the `drive` topic, as last read) its others. The next or the one before replace
// this page in place.

///|
/// The file `at.path` of `at.root` on `at.station`, played; the next or the one before in its place.
pub fn play_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  drive_player(c, src, at, fn() { @sfbase.close_page(DrivePlay(at)) |> ignore }, fn(other) { app.nav.replace(DrivePlay(other)) })
}

///|
/// Back while the player on top is sideways turns it upright first (Player.kt BackHandler).
fn play_back(c : @ui.Ctx) -> Unit {
  match app.nav.top() {
    DrivePlay(at) =>
      {
        let m = @sf.playing_for(reader_key(at)).media
        if m.is_sideways() {
          c.on_back(fn() { m.upright() })
        }
      }
    _ => ()
  }
}

///|
/// Whether what is on top is dark or light whatever the theme (the system bars' icons follow it): the player and the
/// viewer over a picture or a video dark; a reader as its paper. None: as the theme.
fn page_dark(src : Source) -> Bool? {
  match viewer.val {
    Some(v) if !v.closing && v.dark() => return Some(true)
    _ => ()
  }
  if app.nav.top() is DrivePlay(_) {
    return Some(true)
  }
  reader_paper_dark(src)
}
