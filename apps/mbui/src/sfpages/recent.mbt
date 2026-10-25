// ＋'s recent photos and videos (still.fail's Android app, chat/screens/Attach.kt RecentPhotos, latest): the gallery's
// latest across the top of the sheet after the camera, a video's tile marked with a play badge in its corner, a tap
// putting one in the message (most of what goes to an agent
// is a screenshot just taken); read again as the sheet opens and on each answer of the gallery's (@hostapi.gallery_*).
// Without leave to read the gallery the strip's last tile asks for it (显示最近照片); with only the photos chosen for
// the app (Android 14 on), it chooses more (选择更多照片). A host with no gallery (macOS, iOS, Windows) keeps the
// tile, which says so. The strip scrolls sideways under the finger (it is no list: a drag area, its offset gliding on
// once let go).

///|
/// How many of the gallery's photos the strip shows.
let recent_most : Int = 30

///|
/// A tile of the strip: 92 wide, 6 between.
let recent_step : Double = 98.0

///|
/// The strip's state while the app runs.
priv struct Recent {
  /// the sheet was open last frame (its opening reads the gallery again)
  mut open : Bool
  /// the gallery's answers when last read
  mut answers : Int
  mut access : @hostapi.GalleryAccess
  mut reading : @ui.GalleryRead?
  mut photos : Array[@hostapi.GalleryPhoto]
}

///|
let recent : Recent = { open: false, answers: -1, access: NoGallery, reading: None, photos: [] }

///|
fn recent_reset() -> Unit {
  recent.open = false
  recent.answers = -1
  recent.access = NoGallery
  recent.reading = None
  recent.photos = []
}

///|
/// The strip's photo `i` (its first after the camera: 0).
pub fn recent_photo(i : Int) -> @hostapi.GalleryPhoto? {
  recent.photos.get(i)
}

///|
/// Whether and how the gallery may be read, as last asked.
pub fn recent_access() -> @hostapi.GalleryAccess {
  recent.access
}

///|
/// How far ahead of now a time of the gallery's may be and still be believed (seconds): the phone's clock set back a
/// little since it was written.
let recent_ahead : Int64 = 60L

///|
/// The `n` photos latest into the gallery at `now` (seconds), newest first: each by when it came into it (added: the
/// gallery's own stamp as it took it in), not by when it was taken or its file last written, which the camera, other
/// apps and the gallery itself write as they will (a time zone's hours ahead, a file touched again long after) and
/// which put whatever says it is newer ahead of a picture just saved. A time in milliseconds is taken as the seconds it
/// means, one ahead of now is not believed (then the later believable of the other two ranks it); the gallery's own
/// order (its id) between photos of the same time.
fn latest_photos(photos : Array[@hostapi.GalleryPhoto], now : Int64, n : Int) -> Array[@hostapi.GalleryPhoto] {
  let believed = fn(t : Int64) -> Int64 {
    let s = if t > 100_000_000_000L { t / 1000L } else { t }
    if s >= 1L && s <= now + recent_ahead {
      s
    } else {
      0L
    }
  }
  let ranked = photos.map(fn(p) {
    let added = believed(p.added)
    if added > 0L {
      (p, added)
    } else {
      let m = believed(p.modified)
      let k = believed(p.taken)
      (p, if m > k { m } else { k })
    }
  })
  ranked.sort_by(fn(a, b) {
    if a.1 != b.1 {
      b.1.compare(a.1)
    } else {
      b.0.id.compare(a.0.id)
    }
  })
  let out = []
  for i, r in ranked {
    if i >= n {
      break
    }
    out.push(r.0)
  }
  out
}

///|
/// Each frame ＋'s sheet is drawn: the gallery read again as it opens and on each of the system's answers.
pub fn recent_frame(src : Source, open : Bool) -> Unit {
  let answers = @hostapi.gallery_answers()
  if open && (!recent.open || answers != recent.answers) {
    recent.answers = answers
    recent.access = @hostapi.gallery_access()
    recent.reading = match recent.access {
      Whole | Chosen => @ui.gallery_read()
      _ => {
        recent.photos = []
        None
      }
    }
  }
  recent.open = open
  match recent.reading {
    Some(r) =>
      match r.photos() {
        Some(all) => {
          recent.reading = None
          recent.photos = latest_photos(all, ((src.now)() / 1000.0).to_int64(), recent_most)
          @hostapi.log("recent photos: \{recent.photos.length()} of \{all.length()}")
        }
        // (read on the host's side: its word that it is done brings the frame that takes it)
        None => ()
      }
    None => ()
  }
}

///|
/// The strip (Attach.kt RecentPhotos): the camera, the recent photos, the tile that asks; `tapped(i)` with the tile
/// tapped: 0 the camera, 1… a photo, -1 the asking tile.
pub fn recent_strip(c : @ui.Ctx, tapped : (Int) -> Unit) -> Unit {
  // (across the panel it is in, to its sides: scrolled, the tiles go under them)
  c.box(style=@sf.panel_bleed(), fn() { recent_strip_across(c, tapped) }) |> ignore
}

///|
/// The strip in the room it has.
fn recent_strip_across(c : @ui.Ctx, tapped : (Int) -> Unit) -> Unit {
  let t = @sf.theme()
  let photos = recent.photos
  let ask = match recent.access {
    Whole => None
    Chosen => Some(@sf.t("android-chat.attach.recent.more"))
    _ => Some(@sf.t("android-chat.attach.recent.allow"))
  }
  let tiles = 1 + photos.length() + (if ask is Some(_) { 1 } else { 0 })
  let width = c.width
  let content = 12.0 * 2.0 + tiles.to_double() * recent_step - 6.0
  let least = if content > width { width - content } else { 0.0 }
  let id = c.id("attach/strip")
  let a = @motion.anim(c, "attach/strip", 0.0)
  match c.drag_of(id) {
    Some(d) => {
      let (dx, _) = d.take_move()
      if dx != 0.0 {
        // past either end it goes a third as far (its edges' give)
        let next = a.get() + dx
        a.snap(if next > 0.0 || next < least { a.get() + dx / 3.0 } else { next })
      }
      if d.take_end() {
        let to = a.get() + d.vx * 325.0
        let to = if to > 0.0 { 0.0 } else if to < least { least } else { to }
        a.animate(to, @motion.tween(500.0, ease=Decel))
      }
      if d.take_tap() {
        let x = d.x - (match c.rect_of(id) {
          Some((x0, _, _, _)) => x0
          None => 0.0
        }) - 12.0 - a.get()
        let i = (x / recent_step).to_int()
        if x >= 0.0 && x - i.to_double() * recent_step <= 92.0 && i < tiles {
          tapped(if i < 1 + photos.length() { i } else { -1 })
        }
      }
    }
    None => ()
  }
  let off = a.get()
  c.drag_area(id, axis=Horizontal, w=Fill(1.0), fn() {
    c.box(style=recent_strip_row, fn() {
      c.box(style=recent_tiles, tx=off, fn() {
        recent_tile(c, fn() { @sf.icon(c, "camera", size=24.0, color=t.p.text) |> ignore })
        for p in photos {
          recent_tile(c, fn() {
            c.image(p.src, w=Px(recent_tile_w), h=Px(recent_tile_h), radius=14.0, fit=FitCover, bg=0L) |> ignore
            // a video's still, its play mark in its corner (Attach.kt Thumbnail: 22 round, black at 45%, 6 in)
            if p.video {
              c.layer(fn() {
                c.box(style=recent_video_room, fn() {
                  c.box(style=recent_play, fn() {
                    @sf.icon(c, "play", size=14.0, color=0xFFFFFFFFL) |> ignore
                  })
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          })
        }
        match ask {
          Some(words) =>
            recent_tile(c, fn() {
              c.box(style=recent_ask, fn() {
                @sf.icon(c, "photo", size=22.0, color=t.p.muted) |> ignore
                c.text(words, style=recent_ask_words) |> ignore
              })
              |> ignore
            })
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The strip's row: 12 in from the sheet's sides, 4 under its top, 12 over its foot, its tiles 6 apart (Attach.kt
/// RecentPhotos' contentPadding and spacing).
// kept across runs: a value (no field of it changes)
let recent_strip_row : @ui.Style = @ui.css("row w=Full pl=S3 pr=S3 pt=S1 pb=S3 gap=S1_5 clip")

///|
/// Where a video's play mark sits on its tile: its lower start, 6 in.
// kept across runs: a value (no field of it changes)
let recent_video_room : @ui.Style = @ui.css("w=Full h=Full p=S1_5 justify=JEnd align=AStart")

///|
/// A tile of the strip (92 × 122, the chip's grey under it).
fn recent_tile(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=recent_tile_box, body) |> ignore
}

///|
/// A tile: 92 × 122, 14 round, a quiet ground under it.
// kept across runs: a value (no field of it changes)
let recent_tile_box : @ui.Style = @ui.style(
  w=Fixed(recent_tile_w),
  h=Fixed(recent_tile_h),
  radius=Xl1_5,
  bg=Neutral,
  clip=true,
  align=ACenter,
  justify=JCenter,
)

///|
let recent_tile_w : Double = 92.0

///|
let recent_tile_h : Double = 122.0

///|
/// The tiles, 6 apart, slid across by the finger.
// kept across runs: a value (no field of it changes)
let recent_tiles : @ui.Style = @ui.css("row gap=S1_5")

///|
/// A video's play mark (Attach.kt Thumbnail: 22 round, black at 45%).
// kept across runs: a value (no field of it changes)
let recent_play : @ui.Style = @ui.style(
  w=Fixed(recent_play_side),
  h=Fixed(recent_play_side),
  radius=Full,
  bg=A(Theater, O45),
  align=ACenter,
  justify=JCenter,
)

///|
let recent_play_side : Double = 22.0

///|
/// The tile that asks for the gallery: its picture over what it asks, 8 in.
// kept across runs: a value (no field of it changes)
let recent_ask : @ui.Style = @ui.css("px=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let recent_ask_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L4, center=true)
