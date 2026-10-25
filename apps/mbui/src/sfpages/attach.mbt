// ＋ pressed on a touch system (still.fail's Android app, chat/screens/Attach.kt): the library's panel, a sheet from the foot,
// of the gallery's recent photos across its top (the camera first: recent.mbt), then 照片, 文件 and Station 文件 (添加 n 个
// in their place while photos are chosen in the strip). A tile
// picked asks the system (held by the host where it is big: writing_add_held), what it answers coming into the draft as
// the composer is next drawn (take_in); Station 文件 puts up the shell's sheet of station files for the draft. On a
// computer ＋ is the system's picker at once (composer.mbt attach).

///|
/// ＋'s panel for draft `key`, opened by ＋ (`plus`): the gallery's recent photos read again as it opens.
fn attach_open(plus : Int, src : Source, key : String) -> Unit {
  @sf.panel("", fn(c, close) { attach_body(c, src, key, close) }, from=Of(plus))
  recent_opened()
}

///|
/// What the panel shows, each frame it is drawn: the strip, then the three tiles.
fn attach_body(c : @ui.Ctx, src : Source, key : String, close : () -> Unit) -> Unit {
  let p = @sf.theme().p
  let ask = fn(kind : @hostapi.PickKind) {
    close()
    match @ui.pick(kind, hold=true) {
      Some(pick) => composing.picking = Some((key, pick))
      None =>
        say(c, @sf.t(if kind == Camera { "android-chat.composer.noCamera" } else { "android-chat.composer.noFiles" }))
    }
  }
  // the gallery's recent photos, read as the panel opened (attach_open), taken once read
  recent_frame(src)
  let tapped = fn(i : Int) {
    if i == 0 {
      ask(Camera)
    } else if i > 0 {
      close()
      match recent_photo(i - 1).map(fn(photo) { @ui.pick_photos([photo.src]) }) {
        Some(Some(pick)) => composing.picking = Some((key, pick))
        _ => ()
      }
    } else {
      match recent_access() {
        // no gallery on this host: said so
        NoGallery => {
          close()
          say(c, @sf.t("android-chat.composer.noRecent"))
        }
        _ => @hostapi.gallery_ask()
      }
    }
  }
  let photos = c.id("attach/photos")
  let files = c.id("attach/files")
  let station = c.id("attach/station")
  if c.clicked(photos) {
    ask(Photos)
  }
  if c.clicked(files) {
    ask(Files)
  }
  if c.clicked(station) {
    close()
    (@sfbase.station_files_asked.val)(src, key)
  }
  recent_strip(c, tapped)
  // photos chosen in the strip: 添加 n 个 where the tiles were
  let adding = recent_adding(c, fn(pick) {
    close()
    composing.picking = Some((key, pick))
  })
  if adding {
    return
  }
  c.box(style=attach_tiles, fn() {
    for item in [
      (photos, @sf.t("android-chat.attach.photos"), "photo"),
      (files, @sf.t("android-chat.attach.files"), "file"),
      (station, @sf.t("web-pages.chat.files"), "server"),
    ] {
      let (id, label, icon) = item
      c.box(style=attach_tile, id~, fn() {
        @sf.icon(c, icon, size=attach_icon, color=p.text) |> ignore
        c.text(label, style=attach_words) |> ignore
        // (Attach.kt: clip(Smooth(14)).clickable; the ladder's block corner here)
        @motion.ripple(c, id, attach_corner)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The tiles' row (Attach.kt: 12 from the sides, the panel's room there; 18 under them, 8 between).
// kept across runs: a value (no field of it changes)
let attach_tiles : @ui.Style = @ui.css("row w=Full pb=S4_5 gap=S2")

///|
/// A tile: 70 high, its icon over its name, on a quiet ground, a block's corner (the ladder's, as the strip's tiles).
// kept across runs: a value (no field of it changes)
let attach_tile : @ui.Style = @ui.style(
  w=@sf.grow,
  h=Fixed(attach_tile_h),
  px=S1,
  gap=S1_5,
  radius=@sf.row_radius,
  bg=Neutral,
  align=ACenter,
  justify=JCenter,
)

///|
let attach_tile_h : Double = 70.0

///|
// kept across runs: a value (no field of it changes)
let attach_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
let attach_icon : Double = 22.0

///|
let attach_corner : Double = @sf.row_corner
