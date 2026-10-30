// A station's or a workspace's mark picked in a sheet (Settings.kt openMarkPick; the web's MarkPick.tsx): one of
// still.fail's icons (in a colour, or the words') or an emoji (any, pasted or typed), a picture put up, or none; set at
// once by `save`. What is sent is web/src/stationPick.ts's: a glyph keeps its emoji beside it for older clients, an
// emoji or a picture takes the other away.

///|
/// The emoji offered (any other can be pasted or typed): web/src/stationPick.ts's EMOJI.
// kept across runs: a table of constants, never written
let station_emoji : Array[String] = [
  "🖥️", "💻", "🍎", "🐧", "🪟", "☁️", "🏠", "🏢", "🚀", "⚡", "🔥", "🧪", "🛠️", "🐳", "🦀", "🐙", "🌲", "🌊", "🌙", "☀️",
  "🍊", "🍋", "🍇", "🐱", "🐶", "🦊", "🐼", "🐸", "🦉", "🐝", "🦄", "🐢", "🌵", "🌸", "🍄", "🌈", "❄️", "⭐", "🪐", "🌍",
  "🍉", "🍒", "🥑", "🍕", "☕", "🎧", "🎮", "🤖",
]

///|
/// The colours a glyph can be given, in the picker's order (Parts.kt MARK_COLORS).
// kept across runs: a table of constants, never written
let mark_colors : Array[String] = ["red", "orange", "amber", "green", "teal", "blue", "purple", "pink"]

///|
/// The picker as it is while up.
priv struct MarkPick {
  /// the emoji's side (else the icons')
  emojis : @signals.Signal[Bool]
  /// the icons' colour ("": the words')
  color : @signals.Signal[String]
  /// a count of times opened: its fields are their own
  // (plain: the next ask's number, read only as one is asked)
  mut serial : Int
  /// a picture asked of the system's photo picker
  asking : @signals.Signal[Bool]
  /// a picture picked too large to put up as it is, being read to make it small (its key), "" none
  reading : @signals.Signal[String]
}

///|
let mark_pick : MarkPick = {
  emojis: @signals.signal(false, same=fn(a, b) { a == b }),
  color: @signals.signal("", same=fn(a, b) { a == b }),
  serial: 0,
  asking: @signals.signal(false, same=fn(a, b) { a == b }),
  reading: @signals.signal("", same=fn(a, b) { a == b }),
}

///|
/// A glyph's name and colour of an icon (glyph:<name>[:<colour>]); None for another.
fn glyph_of(icon : String) -> (String, String)? {
  if !icon.has_prefix("glyph:") {
    return None
  }
  let rest = icon.unsafe_substring(start=6, end=icon.length())
  let (name, colour) = match rest.find(":") {
    Some(i) => (rest.unsafe_substring(start=0, end=i), rest.unsafe_substring(start=i + 1, end=rest.length()))
    None => (rest, "")
  }
  if glyph_list.iter().any(fn(g) { g.0 == name }) {
    Some((name, if mark_colors.contains(colour) { colour } else { "" }))
  } else {
    None
  }
}

///|
/// A mark colour for the theme in use; None for none (the words').
fn mark_color(color : String) -> Int64? {
  if color == "" {
    None
  } else {
    @sf.glyph_color(color, @sf.theme().dark)
  }
}

///|
/// An emoji without its presentation selector (as two of the same are compared).
fn bare_emoji(e : String) -> String {
  e.replace_all(old="\u{FE0F}", new="")
}

///|
/// Whether `c` is a pictograph or symbol (U+2190 on, past CJK's own) or a flag's regional indicator: not a letter, a
/// digit or CJK.
fn emoji_char(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 0x1F000 && cp <= 0x1FAFF) ||
  (cp >= 0x2190 && cp <= 0x2BFF) ||
  cp == 0x00A9 ||
  cp == 0x00AE ||
  cp == 0x3030 ||
  cp == 0x303D
}

///|
/// The first emoji of what was typed or pasted, as a person sees one (a flag, a family, a skin tone are one); None
/// for none (firstEmoji).
fn first_emoji(words : String) -> String? {
  let cs = words.trim(chars=" \t\n").to_owned().iter().collect()
  if cs.length() == 0 || !emoji_char(cs[0]) {
    return None
  }
  let b = StringBuilder()
  b.write_char(cs[0])
  let flag_first = cs[0].to_int() >= 0x1F1E6 && cs[0].to_int() <= 0x1F1FF
  let mut i = 1
  while i < cs.length() {
    let cp = cs[i].to_int()
    if cp == 0xFE0F || (cp >= 0x1F3FB && cp <= 0x1F3FF) || cp == 0x20E3 {
      // its presentation, a skin tone, a keycap
      b.write_char(cs[i])
      i += 1
    } else if cp == 0x200D && i + 1 < cs.length() {
      // joined to the next
      b.write_char(cs[i])
      b.write_char(cs[i + 1])
      i += 2
    } else if flag_first && i == 1 && cp >= 0x1F1E6 && cp <= 0x1F1FF {
      b.write_char(cs[i])
      i += 1
    } else {
      break
    }
  }
  Some(b.to_string())
}

///|
/// A picture picked as a mark: put up as it is, as a data URL, where it is a PNG, JPEG or WebP small enough to go with
/// the workspace (46 000 characters), or a GIF (1 390 000: it may move); None otherwise (made small first:
/// picture_mark_small).
fn picture_mark(bytes : Bytes) -> String? {
  let n = bytes.length()
  let kind = if n > 8 && bytes[0] == b'\x89' && bytes[1] == b'P' && bytes[2] == b'N' && bytes[3] == b'G' {
    "png"
  } else if n > 3 && bytes[0] == b'\xFF' && bytes[1] == b'\xD8' && bytes[2] == b'\xFF' {
    "jpeg"
  } else if n > 12 && bytes[8] == b'W' && bytes[9] == b'E' && bytes[10] == b'B' && bytes[11] == b'P' {
    "webp"
  } else if n > 6 && bytes[0] == b'G' && bytes[1] == b'I' && bytes[2] == b'F' && bytes[3] == b'8' {
    "gif"
  } else {
    return None
  }
  let url = "data:image/" + kind + ";base64," + @codec.base64(bytes)
  // a GIF may move, and may be larger: still.fail cloud keeps it in its bucket (cloud/src/icons.ts, 1 MB)
  if url.length() <= (if kind == "gif" { 1390000 } else { 46000 }) {
    Some(url)
  } else {
    None
  }
}

///|
/// A picture too large to put up as it is made small (Settings.kt stationPictureOf): its middle square at 96 px, read
/// at least 192 on its shorter side, as a JPEG (85) on white where it is clear (this app writes no WebP); None when
/// even that is too large.
fn picture_mark_small(w : Int, h : Int, px : FixedArray[Byte]) -> String? {
  let icon = @pixels.Canvas::new(mark_picture_px, mark_picture_px)
  icon.fill(0xFFFFFFFFL)
  let s = if w < h { w } else { h }
  let x = (w - s) / 2
  let y = (h - s) / 2
  icon.draw(w, h, px, (x, y, x + s, y + s), (0.0, 0.0, mark_picture_px.to_double(), mark_picture_px.to_double()))
  let url = "data:image/jpeg;base64," +
    @codec.base64(@pixels.jpeg(mark_picture_px, mark_picture_px, icon.pixels(), quality=85))
  if url.length() <= 46000 {
    Some(url)
  } else {
    None
  }
}

///|
/// A picture's side as a mark, and how large it is read to be made that.
let mark_picture_px : Int = 96

///|
let mark_picture_read : Int = 768

///|
/// Pictures picked as marks too large to put up as they are: each its own key.
let mark_pictures : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// The mark picker (openMarkPick) for `name`, whose mark is `emoji` and `icon` now: `save(emoji, icon)` sets one,
/// `what` naming it should it fail ("" and "" take it away).
pub fn open_mark_pick(
  core : Core,
  name : String,
  emoji : String,
  icon : String,
  what : String,
  save : (String, String, (Result[Json, Json]) -> Unit) -> Unit,
) -> Unit {
  let set = fn(e : String, i : String) {
    if e != emoji || i != icon {
      save(e, i, fn(r) {
        match r {
          Ok(_) => (core.say)(tr("android-settings.station.emojiSet"))
          Err(err) =>
            (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(err))]))
        }
      })
    }
  }
  let glyph = glyph_of(icon)
  let picture = icon.has_prefix("data:image/") ||
    icon.has_prefix("https://") ||
    icon.has_prefix("http://")
  mark_pick.emojis.set(glyph is None && !picture && emoji != "")
  mark_pick.color.set(match glyph {
    Some((_, col)) => col
    None => ""
  })
  mark_pick.serial += 1
  mark_pick.asking.set(false)
  mark_pick.reading.set("")
  let serial = mark_pick.serial
  // (a sheet of its own with touch, a dialog with keyboard and mouse: the presenters'; its grid scrolls in what is left)
  @sf.panel(fill("android-settings.station.emojiTitle", [("name", name)]), from=Unanchored, tall=mark_tall, fn(c, close) {
    // (filling its share, it lays out its own sides: a page's room)
    c.box(style=mark_body, fn() { mark_pick_body(c, core, emoji, icon, glyph, picture, serial, set, close) }) |> ignore
  })
}

///|
/// What the picker holds, given what sets a mark and what closes it.
fn mark_pick_body(
  c : @ui.Ctx,
  core : Core,
  emoji : String,
  icon : String,
  glyph : (String, String)?,
  picture : Bool,
  serial : Int,
  set : (String, String) -> Unit,
  close : () -> Unit,
) -> Unit {
  {
    let t = @sf.theme()
    let pick = fn(e : String, i : String) {
      close()
      set(e, i)
    }
    // a picture too large as it is, read: made small and put up
    if mark_pick.reading.get() != "" {
      match c.image_pixels(mark_pick.reading.get(), mark_picture_read) {
        PixelsComing => ()
        PixelsRead(w, h, px) => {
          mark_pick.reading.set("")
          match picture_mark_small(w, h, px) {
            Some(url) => pick("", url)
            None => (core.say)(tr("android-settings.station.imageFailed"))
          }
        }
        PixelsFailed => {
          mark_pick.reading.set("")
          (core.say)(tr("android-settings.station.imageFailed"))
        }
      }
    }
    let emojis = mark_pick.emojis.get()
    let typed_key = "mark-typed/" + serial.to_string()
    let query_key = "mark-query/" + serial.to_string()
    // the icons' side or the emoji's, and its field: an emoji pasted or typed, or words to find an icon by (the one
    // not shown keeps its own)
    let mut query = ""
    c.box(style=mark_head, fn() {
      let i = @sf.segmented(c, "mark-side/" + serial.to_string(), [tr("android-settings.station.glyphs"), "Emoji"], if emojis {
        1
      } else {
        0
      })
      mark_pick.emojis.set(i == 1)
      if emojis {
        let typed = @sf.input(c, typed_key, placeholder=tr("android-settings.station.emojiPaste"), field=field_of(typed_key)).text
        match first_emoji(typed) {
          Some(e) => {
            field_of(typed_key).set("")
            pick(e, "")
          }
          None => ()
        }
      } else {
        query = @sf.input(c, query_key, placeholder=tr("android-settings.station.glyphSearch"), field=field_of(query_key)).text
      }
    })
    |> ignore
    // the icons' colour: the words' own first, then the marks'; the one picked ringed; it colours the grid, and the
    // icon it has, at once
    if !emojis {
      c.box(style=mark_colours, fn() {
        for col in [""] + mark_colors {
          let of = mark_color(col).unwrap_or(t.p.text)
          let id = c.id("mark-color/" + col)
          if c.clicked(id) {
            mark_pick.color.set(col)
            match glyph {
              Some((g, _)) => set(glyph_emoji(g), "glyph:" + g + (if col == "" { "" } else { ":" + col }))
              None => ()
            }
          }
          let ring = c.box(style=mark_colour, border=if col == mark_pick.color.get() { mark_ring } else { 0.0 }, border_color=of, id~, fn() {
            c.box(style=mark_colour_dot, bg=of, fn() {  }) |> ignore
          })
          c.semantics(ring, Button, id~, label=if col == "" { tr("android-settings.station.glyphs") } else { col }, selected=col == mark_pick.color.get())
        }
      })
      |> ignore
    }
    // the one it has, on the accent's wash
    let kept = if emojis {
      if glyph is None && !picture && emoji != "" { bare_emoji(emoji) } else { "" }
    } else {
      match glyph {
        Some((g, _)) => g
        None => ""
      }
    }
    // the icons found by every word typed (in their names, English or Chinese); all of them for none
    let terms = query.to_lower().split(" ").map(fn(v) { v.to_owned() }).filter(fn(x) { x != "" }).collect()
    let offered : Array[String] = if !emojis {
      glyph_list.filter(fn(g) { terms.iter().all(fn(term) { g.2.contains(term) }) }).map(fn(g) { g.0 })
    } else if kept != "" && !station_emoji.iter().any(fn(e) { bare_emoji(e) == kept }) {
      let l = [emoji]
      for k in 0..<(station_emoji.length() - 1) {
        l.push(station_emoji[k])
      }
      l
    } else {
      station_emoji
    }
    let tint = mark_color(mark_pick.color.get())
    let rows = (offered.length() + mark_across - 1) / mark_across
    let blocks : Array[() -> Unit] = []
    if offered.length() == 0 {
      blocks.push(fn() { @sf.page_note(c, tr("android-settings.station.glyphNone")) })
    }
    for r in 0..<rows {
      blocks.push(fn() {
        // six to a row, each as wide as a sixth of it (a thumb's), square
        c.box(style=mark_row, fn() {
          for k in 0..<mark_across {
            let i = r * mark_across + k
            if i >= offered.length() {
              c.box(style=mark_cell_none, fn() {  }) |> ignore
              continue
            }
            let key = offered[i]
            let on = (if emojis { bare_emoji(key) } else { key }) == kept
            let id = c.id("mark/" + key)
            if c.clicked(id) {
              if emojis {
                pick(key, "")
              } else {
                pick(glyph_emoji(key), "glyph:" + key + (if mark_pick.color.get() == "" { "" } else { ":" + mark_pick.color.get() }))
              }
            }
            // (square: as tall as it is wide)
            let cell = c.box(style=if on { mark_cell_on } else { mark_cell }, aspect=1.0, id~, fn() {
              if emojis {
                c.text(key, style=mark_emoji_words) |> ignore
              } else {
                @sf.station_mark(c, "", "glyph:" + key, mark_glyph, tint.unwrap_or(if on { t.p.accent_text } else { t.p.text }))
              }
              @sf.row_ripple(c, id)
            })
            c.semantics(cell, Button, id~, label=key, selected=on)
          }
        })
        |> ignore
      })
    }
    // a picture put up, or none
    blocks.push(fn() {
      c.box(style=mark_foot, fn() {
        @sf.group(c, fn() {
          if @sf.link_row(
              c,
              "mark-picture",
              tr(if picture { "android-settings.station.imageAnother" } else { "android-settings.station.image" }),
              chevron=false,
              lead=fn() {
                if picture {
                  @sf.station_mark(c, "", icon, mark_row_mark, t.p.text)
                } else {
                  @sf.icon(c, "image-upload", size=mark_row_mark, color=t.p.text) |> ignore
                }
              },
            ) {
            // the picture the system's picker answers with put up as the mark
            let asked = (core.pick_picture)(fn(bytes) {
              mark_pick.asking.set(false)
              match bytes {
                Some(b) =>
                  match picture_mark(b) {
                    Some(url) => pick("", url)
                    None => {
                      mark_pictures.set(mark_pictures.get() + 1)
                      mark_pick.reading.set("mem:station-mark/\{mark_pictures.get()}")
                      @ui.add_image(mark_pick.reading.get(), b)
                    }
                  }
                None => ()
              }
            })
            mark_pick.asking.set(asked)
            if !asked {
              (core.say)(tr("android-settings.station.imageFailed"))
            }
          }
          if @sf.has_station_mark(emoji, icon) &&
            @sf.link_row(c, "mark-none", tr("android-settings.station.emojiClear"), chevron=false, lead=fn() {
              @sf.icon(c, "close", size=mark_row_mark, color=t.p.text) |> ignore
            }) {
            pick("", "")
          }
        })
      })
      |> ignore
    })
    c.box(style=mark_grid_room, fn() {
      @sf.panel_list(c, "mark/" + serial.to_string() + (if emojis { "/e" } else { "/g" }), blocks.length(), mark_row_est, fn(i) {
        (blocks[i])()
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// The picker's body: in a page's room, filling the sheet's share.
// kept across runs: a value (no field of it changes)
let mark_body : @ui.Style = @sf.pg_room.then(@ui.style(h=@sf.grow))

///|
/// The picker's share of the window (a sheet that tall; a dialog at most that tall).
let mark_tall : Double = 0.78

///|
/// The side and its field over the grid, 10 apart, 10 under them.
// kept across runs: a value (no field of it changes)
let mark_head : @ui.Style = @ui.css("w=Full pb=S2_5 gap=S2_5")

///|
/// The colours across, as far apart as they go, 10 under them; each 32 round, ringed 2 in itself where picked, its
/// dot 18.
// kept across runs: a value (no field of it changes)
let mark_colours : @ui.Style = @ui.css("row w=Full pb=S2_5 justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let mark_colour : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let mark_colour_dot : @ui.Style = @ui.style(w=Fixed(mark_dot), h=Fixed(mark_dot), radius=Full)

///|
let mark_dot : Double = 18.0

///|
let mark_ring : Double = 2.0

///|
/// What scrolls: the grid's rows, then a picture or none, in what is left of it (its grid a @sf.panel_list: the sheet
/// as tall as it comes to, up to its share).
// kept across runs: a value (no field of it changes)
let mark_grid_room : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
let mark_row_est : Double = 64.0

///|
/// Six to a row, 4 apart, 4 under each row.
let mark_across : Int = 6

///|
// kept across runs: a value (no field of it changes)
let mark_row : @ui.Style = @ui.css("row w=Full pb=S1 gap=S1")

///|
/// A cell: square, its corner the ladder's for a small block; the one it has on the accent's wash.
// kept across runs: a value (no field of it changes)
let mark_cell : @ui.Style = @ui.style(w=@sf.grow, radius=Xl2, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let mark_cell_on : @ui.Style = mark_cell.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let mark_cell_none : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let mark_emoji_words : @ui.TextStyle = @ui.text_style(size=Heading, wrap=false)

///|
let mark_glyph : Double = 24.0

///|
/// A picture or none under the grid, 6 over them, 24 under.
// kept across runs: a value (no field of it changes)
let mark_foot : @ui.Style = @ui.css("w=Full pt=S1_5 pb=S6")

///|
let mark_row_mark : Double = 20.0

///|
/// The emoji a glyph keeps beside it.
fn glyph_emoji(name : String) -> String {
  match glyph_list.iter().find_first(fn(g) { g.0 == name }) {
    Some(g) => g.1
    None => ""
  }
}
