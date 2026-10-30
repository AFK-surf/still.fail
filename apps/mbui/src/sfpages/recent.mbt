// ＋'s recent photos and videos (still.fail's Android app, chat/screens/Attach.kt RecentPhotos, latest): the gallery's
// latest across the top of the sheet after the camera, a video's tile marked with a play badge in its corner, a tap
// putting one in the message (most of what goes to an agent is a screenshot just taken); read again as the sheet opens
// and on each answer of the gallery's (@hostapi.gallery_*). Several go together as the system's photo picker and
// chat apps' strips choose them: each tile's ring in its top corner chooses it (numbered in the order chosen), and
// while some are chosen a tap anywhere on a tile chooses it or not; the tiles under the strip give way to 添加 n 个
// (recent_adding), which puts them in the message in that order.
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
  /// the gallery's answers when last read
  answers : @signals.Signal[Int]
  access : @signals.Signal[@hostapi.GalleryAccess]
  reading : @signals.Signal[@ui.GalleryRead?]
  /// read again once the read under way is taken (asked for while it read)
  again : @signals.Signal[Bool]
  photos : @sf.LiveArray[@hostapi.GalleryPhoto]
  /// the photos chosen to go together (their `src`), in the order chosen; none as the sheet opens
  chosen : @sf.LiveArray[String]
}

///|
let recent : Recent = { answers: @signals.signal(-1, same=fn(a, b) { a == b }), access: @signals.signal(NoGallery), reading: @signals.signal(None), again: @signals.signal(false, same=fn(a, b) { a == b }), photos: @sf.LiveArray::new(), chosen: @sf.LiveArray::new() }

///|
fn recent_reset() -> Unit {
  recent.answers.set(-1)
  recent.access.set(NoGallery)
  recent.reading.set(None)
  recent.again.set(false)
  recent.photos.clear()
  recent.chosen.clear()
}

///|
/// The strip's photo `i` (its first after the camera: 0).
pub fn recent_photo(i : Int) -> @hostapi.GalleryPhoto? {
  recent.photos.get(i)
}

///|
/// Whether and how the gallery may be read, as last asked.
pub fn recent_access() -> @hostapi.GalleryAccess {
  recent.access.get()
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
/// ＋'s sheet opened (by what opens it, as it does): none chosen, the gallery read again, what it took in since it was
/// last read with it (a screenshot just taken). Not seen by the sheet's frames: they are drawn only while it is up, so
/// they never see it down between two openings.
pub fn recent_opened() -> Unit {
  recent.chosen.clear()
  recent_read()
}

///|
/// The gallery read as it is now; asked while a read is under way, read again once that one is taken (one at a time,
/// none let go of unread).
fn recent_read() -> Unit {
  recent.answers.set(@hostapi.gallery_answers())
  if recent.reading.get() is Some(_) {
    recent.again.set(true)
    return
  }
  recent.access.set(@hostapi.gallery_access())
  recent.reading.set(match recent.access.get() {
    Whole | Chosen => @ui.gallery_read()
    _ => {
      recent.photos.replace([])
      None
    }
  })
}

///|
/// Each frame ＋'s sheet is drawn: the gallery read again on each of the system's answers (an ask for it answered), a
/// read done taken.
pub fn recent_frame(src : Source) -> Unit {
  if @hostapi.gallery_answers() != recent.answers.get() {
    recent_read()
  }
  match recent.reading.get() {
    Some(r) =>
      match r.photos() {
        Some(all) => {
          recent.reading.set(None)
          recent.photos.replace(latest_photos(all, ((src.now)() / 1000.0).to_int64(), recent_most))
          // (one chosen and gone from the gallery since: not chosen)
          recent.chosen.retain(fn(s) { recent.photos.iter().any(fn(p) { p.src == s }) })
          @hostapi.log("recent photos: \{recent.photos.length()} of \{all.length()}")
          if recent.again.get() {
            recent.again.set(false)
            recent_read()
          }
        }
        // (read on the host's side: its word that it is done brings the frame that takes it)
        None => ()
      }
    None => ()
  }
}

///|
/// While photos are chosen in the strip, in the room of the tiles under it (as high, so the sheet stays as it is):
/// 添加 n 个; pressed, the photos chosen read whole as one pick of them, in the order chosen, given to `add`. Whether
/// some are chosen (the tiles are not drawn then).
pub fn recent_adding(c : @ui.Ctx, add : (@ui.Pick) -> Unit) -> Bool {
  let n = recent.chosen.length()
  if n == 0 {
    return false
  }
  let id = c.id("attach/add")
  if c.clicked(id) {
    match @ui.pick_photos(recent.chosen.copy()) {
      Some(pick) => add(pick)
      None => ()
    }
    recent.chosen.clear()
  }
  let words = @sf.t("web-mobile.files.addCount", args=[("n", n.to_string())])
  let corner = attach_block_corner()
  c.box(style=recent_add_row.then(@ui.style(pb=@sf.room_of(attach_foot()))), fn() {
    let b = c.box(style=recent_add.then(@ui.style(radius=attach_block_radius())), id~, fn() {
      c.text(words, style=recent_add_words) |> ignore
      @motion.ripple(c, id, corner)
    })
    c.semantics(b, Button, id~, label=words)
  })
  |> ignore
  true
}

///|
/// Photo `src` chosen to go with the others, or not any more.
fn recent_choose(src : String) -> Unit {
  if recent.chosen.contains(src) {
    recent.chosen.retain(fn(s) { s != src })
  } else {
    recent.chosen.push(src)
  }
}

///|
/// The strip (Attach.kt RecentPhotos): the camera, the recent photos, the tile that asks; `tapped(i)` with the tile
/// tapped: 0 the camera, 1… a photo (none chosen: it alone), -1 the asking tile. A photo's ring (a finger's reach round
/// it), or any of a photo while some are chosen, chooses it or not.
pub fn recent_strip(c : @ui.Ctx, tapped : (Int) -> Unit) -> Unit {
  // (across the panel it is in, to its sides: scrolled, the tiles go under them)
  c.box(style=@sf.panel_bleed(), fn() { recent_strip_across(c, tapped) }) |> ignore
}

///|
/// The strip in the room it has.
fn recent_strip_across(c : @ui.Ctx, tapped : (Int) -> Unit) -> Unit {
  let t = @sf.theme()
  let photos = recent.photos
  let ask = match recent.access.get() {
    Whole => None
    Chosen => Some(@sf.t("android-chat.attach.recent.more"))
    _ => Some(@sf.t("android-chat.attach.recent.allow"))
  }
  let tiles = 1 + photos.length() + (if ask is Some(_) { 1 } else { 0 })
  let (side, top) = recent_in()
  let corner = attach_block_corner()
  let width = c.width
  let content = side * 2.0 + tiles.to_double() * recent_step - 6.0
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
        a.animate(to, @motion.sheet_spring, velocity=d.vx * 1000.0)
      }
      if d.take_tap() {
        let (x0, y0) = match c.rect_of(id) {
          Some((x0, y0, _, _)) => (x0, y0)
          None => (0.0, 0.0)
        }
        // (from the first tile's start and top: as far in as the row has them)
        let x = d.x - x0 - side - a.get()
        let y = d.y - y0 - top
        let i = (x / recent_step).to_int()
        let across = x - i.to_double() * recent_step
        if x >= 0.0 && across <= recent_tile_w && i < tiles {
          if i >= 1 && i <= photos.length() {
            if recent_on_ring(across, y, corner) || recent.chosen.length() > 0 {
              recent_choose(photos[i - 1].src)
            } else {
              tapped(i)
            }
          } else {
            tapped(if i == 0 { 0 } else { -1 })
          }
        }
      }
    }
    None => ()
  }
  let off = a.get()
  c.drag_area(id, axis=Horizontal, w=Fill(1.0), fn() {
    c.box(style=recent_strip_row.then(@ui.style(pl=@sf.room_of(side), pr=@sf.room_of(side), pt=@sf.room_of(top))), fn() {
      c.box(style=recent_tiles, tx=off, fn() {
        recent_tile(c, fn() { @sf.icon(c, "camera", size=24.0, color=t.p.text) |> ignore })
        for p in photos {
          let n = match recent.chosen.search(p.src) {
            Some(k) => k + 1
            None => 0
          }
          recent_tile(c, fn() {
            c.image(p.src, w=Px(recent_tile_w), h=Px(recent_tile_h), radius=corner, fit=FitCover, bg=0L) |> ignore
            c.layer(fn() {
              c.box(style=recent_marks.then(@ui.style(p=@sf.room_of(recent_mark_in(corner)))), fn() {
                // its ring in its top corner, chosen its number on the primary
                c.box(style=recent_ring_room, fn() {
                  c.box(style=if n > 0 { recent_ring_on } else { recent_ring }, fn() {
                    if n > 0 {
                      c.text(n.to_string(), style=recent_ring_words) |> ignore
                    }
                  })
                  |> ignore
                })
                |> ignore
                // a video's still, its play mark in its foot corner (Attach.kt Thumbnail: 22 round, black at 45%)
                if p.video {
                  @sf.play_mark(c, recent_mark_side, A(Theater, O45)) |> ignore
                }
              })
              |> ignore
            })
            |> ignore
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
/// The strip's row: as far in as recent_in has it, 12 over its foot, its tiles 6 apart (Attach.kt RecentPhotos'
/// contentPadding and spacing).
// kept across runs: a value (no field of it changes)
let recent_strip_row : @ui.Style = @ui.css("row w=Full pb=S3 gap=S1_5 clip")

///|
/// The room under ＋'s tiles (照片 文件 Station 文件, 添加 n 个): in a sheet 18 (Attach.kt); in a small panel none past
/// its padding, so they stand as far from its foot as the strip from its sides and top.
pub fn attach_foot() -> Double {
  if @sf.in_small_panel() {
    0.0
  } else {
    18.0
  }
}

///|
/// How far in the strip's tiles stand from the panel's sides and under its top: in a sheet 12 and 4 (Attach.kt
/// RecentPhotos' contentPadding); in a small panel beside ＋, at its padding, as a menu's rows (the first tile in its
/// corner, concentric with it: attach_block_corner).
fn recent_in() -> (Double, Double) {
  if @sf.in_small_panel() {
    (@sf.panel_pad, 0.0)
  } else {
    (12.0, 4.0)
  }
}

///|
/// How round ＋'s tiles are (the strip's, 照片 文件 Station 文件, 添加 n 个): a block's (the ladder's row_corner) in a
/// sheet; in a small panel, concentric with its corner at its padding, as its rows are.
pub fn attach_block_corner() -> Double {
  if @sf.in_small_panel() {
    @sf.small_panel_inner(@sf.r_menu)
  } else {
    @sf.row_corner
  }
}

///|
/// attach_block_corner as a style's: a small panel's panel_in, else a block's row_radius.
pub fn attach_block_radius() -> @ui.Radius {
  if @sf.in_small_panel() {
    @sf.panel_in
  } else {
    @sf.row_radius
  }
}

///|
/// What is marked on a photo's tile: its ring at its top end, a video's play mark at its foot's start, each concentric
/// with the tile's corner (recent_mark_in).
// kept across runs: a value (no field of it changes)
let recent_marks : @ui.Style = @ui.css("w=Full h=Full justify=JBetween align=AStart")

///|
/// The marks' side (Attach.kt Thumbnail's play mark: 22).
let recent_mark_side : Double = 22.0

///|
/// How far in a mark stands from the sides of a tile `corner` round: concentric with its corner (18 round: 7).
fn recent_mark_in(corner : Double) -> Double {
  @sf.capsule_in(corner, recent_mark_side)
}

///|
/// Whether a tap at (`across`, `down`) on a photo's tile, from its start and top, is on its ring: reached from round
/// it, as a finger reaches what is smaller than its tip (mbui's press_reach: the ring grown to @ui.finger_target round
/// its middle).
fn recent_on_ring(across : Double, down : Double, corner : Double) -> Bool {
  let tip = @ui.finger_target()
  let reach = (if tip > recent_mark_side { tip } else { recent_mark_side }) / 2.0
  let x = recent_tile_w - recent_mark_in(corner) - recent_mark_side / 2.0
  let y = recent_mark_in(corner) + recent_mark_side / 2.0
  (across - x).abs() <= reach && (down - y).abs() <= reach
}

///|
/// The ring's place: across the top of the tile, at its end.
// kept across runs: a value (no field of it changes)
let recent_ring_room : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
/// A photo's ring, not chosen: white, over a shade of black so that it shows on a white picture too.
// kept across runs: a value (no field of it changes)
let recent_ring : @ui.Style = @ui.style(
  w=Fixed(recent_mark_side),
  h=Fixed(recent_mark_side),
  radius=Full,
  bg=A(Theater, O20),
  border=B1_5,
  border_color=OnVeil,
)

///|
/// Chosen: filled with the primary (as a checkbox ticked), its number on it.
// kept across runs: a value (no field of it changes)
let recent_ring_on : @ui.Style = recent_ring.then(@ui.css("bg=Primary align=ACenter justify=JCenter"))

///|
// kept across runs: a value (no field of it changes)
let recent_ring_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnPrimary, wrap=false)

///|
/// 添加 n 个's row, where the tiles under the strip were (as far over the foot: attach_foot).
// kept across runs: a value (no field of it changes)
let recent_add_row : @ui.Style = @ui.css("row w=Full")

///|
/// 添加 n 个: as high and round as the tiles it stands for (attach_tile, attach_block_corner), on the primary.
// kept across runs: a value (no field of it changes)
let recent_add : @ui.Style = @ui.style(
  w=Full,
  h=Fixed(recent_add_h),
  bg=Primary,
  align=ACenter,
  justify=JCenter,
)

///|
let recent_add_h : Double = 70.0

///|
// kept across runs: a value (no field of it changes)
let recent_add_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=OnPrimary, wrap=false)

///|
/// A tile of the strip (92 × 122, the chip's grey under it), as round as attach_block_radius.
fn recent_tile(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=recent_tile_box.then(@ui.style(radius=attach_block_radius())), body) |> ignore
}

///|
/// A tile: 92 × 122 (as round as attach_block_corner: what is marked in its corners concentric with it), a quiet ground
/// under it.
// kept across runs: a value (no field of it changes)
let recent_tile_box : @ui.Style = @ui.style(
  w=Fixed(recent_tile_w),
  h=Fixed(recent_tile_h),
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
/// The tile that asks for the gallery: its picture over what it asks, 8 in.
// kept across runs: a value (no field of it changes)
let recent_ask : @ui.Style = @ui.css("px=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let recent_ask_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4, center=true)
