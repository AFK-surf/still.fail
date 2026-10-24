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
/// The ids of the `n` photos latest at `now` (seconds), newest first (Attach.kt latest): each by the latest of its times
/// that can be believed, a time in milliseconds taken as the seconds it means and one still ahead of now (by more than a
/// day) left out; the gallery's own order (its id) between photos of the same time.
fn latest_photos(photos : Array[@hostapi.GalleryPhoto], now : Int64, n : Int) -> Array[@hostapi.GalleryPhoto] {
  let believed = fn(t : Int64) -> Int64 {
    let s = if t > 100_000_000_000L { t / 1000L } else { t }
    if s >= 1L && s <= now + 86_400L {
      s
    } else {
      0L
    }
  }
  let ranked = photos.map(fn(p) {
    let mut at = believed(p.added)
    let m = believed(p.modified)
    if m > at {
      at = m
    }
    let k = believed(p.taken)
    if k > at {
      at = k
    }
    (p, at)
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
fn recent_frame(src : Source, open : Bool) -> Unit {
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
fn recent_strip(c : @ui.Ctx, tapped : (Int) -> Unit) -> Unit {
  let t = @sf.theme()
  let photos = recent.photos
  let ask = match recent.access {
    Whole => None
    Chosen => Some(tr("android-chat.attach.recent.more"))
    _ => Some(tr("android-chat.attach.recent.allow"))
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
      c.box(dir=Row, gap=6.0, tx=off, fn() {
        recent_tile(c, fn() { @sf.icon(c, "camera", size=24.0, color=t.p.text) |> ignore })
        for p in photos {
          recent_tile(c, fn() {
            c.image(p.src, w=Px(92.0), h=Px(122.0), radius=14.0, fit=FitCover, bg=0L) |> ignore
            // a video's still, its play mark in its corner (Attach.kt Thumbnail: 22 round, black at 45%, 6 in)
            if p.video {
              c.layer(fn() {
                c.box(style=recent_video_room, fn() {
                  c.box(w=Px(22.0), h=Px(22.0), radius=11.0, bg=0x00000073L, align=ACenter, justify=JCenter, fn() {
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
              c.box(padx=8.0, gap=8.0, align=ACenter, fn() {
                @sf.icon(c, "photo", size=22.0, color=t.p.muted) |> ignore
                c.text(words, size=12.0, color=t.p.muted, line=16.0, center=true) |> ignore
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
  let t = @sf.theme()
  c.box(w=Px(92.0), h=Px(122.0), radius=14.0, bg=t.p.chip, clip=true, align=ACenter, justify=JCenter, body)
  |> ignore
}
