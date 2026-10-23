// A video or a song of a station's drive, played (Screen.DrivePlay, pushed from a folder's row): the library's player
// (@sf.player: opened where it was left on this device, the subtitle beside it, where it is kept as it plays; a
// desktop's over the whole window, a phone's on its page) over a drive's file (drive_viewer.mbt: its bytes read through
// the core a part at a time, never the whole file first), the folder (the `drive` topic, as last read) its others. The
// next or the one before replace this page in place.

///|
/// The file `at.path` of `at.root` on `at.station`, played.
pub fn play_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let key = reader_key(at)
  let root = at.root.unwrap_or("")
  let dir = dv_parent(at.path)
  let file = drive_viewer_file(c, src, at)
  let entries = items((src.topic)("drive", drive_params(at.station, root, dir)).value, "entries").map(dv_entry)
  let siblings : Array[@sf.ViewerEntry] = entries.map(fn(e) {
    { name: e.name, size: e.size, mtime: e.mtime, mime: e.mime, kind: e.kind, dir: e.dir }
  })
  let open = fn(other : String) {
    app.nav.replace(DrivePlay({ station: at.station, root: at.root, path: dv_join(dir, other) }))
  }
  @sf.player(
    c,
    key,
    file,
    siblings,
    back_label=viewer_folder_label(src, at.station, root, dir),
    on_back=fn() { app.nav.pop() |> ignore },
    on_go=open,
  )
}

///|
/// Its page gone: where it was kept, the player stopped.
fn play_left(at : DriveAt) -> Unit {
  @sf.player_let_go(reader_key(at))
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
