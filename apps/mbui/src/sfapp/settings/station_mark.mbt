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
  mut emojis : Bool
  /// the icons' colour ("": the words')
  mut color : String
  /// a count of times opened: its fields are their own
  mut serial : Int
  /// a picture asked of the system's photo picker
  mut asking : Bool
  /// a picture picked too large to put up as it is, being read to make it small (its key), "" none
  mut reading : String
}

///|
let mark_pick : MarkPick = { emojis: false, color: "", serial: 0, asking: false, reading: "" }

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
/// the workspace (46 000 characters), or a GIF (156 000: it may move); None otherwise (made small first:
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
  let url = "data:image/" + kind + ";base64," + base64_of(bytes)
  // a GIF may move, and may be larger (cloud/src/directory.ts GIF_BYTES)
  if url.length() <= (if kind == "gif" { 156000 } else { 46000 }) {
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
    base64_of(@pixels.jpeg(mark_picture_px, mark_picture_px, icon.pixels(), quality=85))
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
let mark_pictures : Ref[Int] = Ref(0)

///|
/// Bytes in base64 (RFC 4648, padded).
fn base64_of(b : Bytes) -> String {
  let abc : Array[Char] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".iter().collect()
  let out = StringBuilder()
  let n = b.length()
  let mut i = 0
  while i < n {
    let b0 = b[i].to_int()
    let b1 = if i + 1 < n { b[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < n { b[i + 2].to_int() } else { 0 }
    out.write_char(abc[b0 >> 2])
    out.write_char(abc[((b0 & 3) << 4) | (b1 >> 4)])
    out.write_char(if i + 1 < n { abc[((b1 & 15) << 2) | (b2 >> 6)] } else { '=' })
    out.write_char(if i + 2 < n { abc[b2 & 63] } else { '=' })
    i += 3
  }
  out.to_string()
}

///|
/// The mark picker (openMarkPick) for `name`, whose mark is `emoji` and `icon` now: `save(emoji, icon)` sets one,
/// `what` naming it should it fail ("" and "" take it away).
fn open_mark_pick(
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
  let pick = fn(e : String, i : String) {
    close_sheet()
    set(e, i)
  }
  let glyph = glyph_of(icon)
  let picture = icon.has_prefix("data:image/")
  mark_pick.emojis = glyph is None && !picture && emoji != ""
  mark_pick.color = match glyph {
    Some((_, col)) => col
    None => ""
  }
  mark_pick.serial += 1
  mark_pick.asking = false
  mark_pick.reading = ""
  let serial = mark_pick.serial
  open_sheet(0.78, fn(c, core) {
    let t = @sf.theme()
    // a picture too large as it is, read: made small and put up
    if mark_pick.reading != "" {
      match c.image_pixels(mark_pick.reading, mark_picture_read) {
        PixelsComing => ()
        PixelsRead(w, h, px) => {
          mark_pick.reading = ""
          match picture_mark_small(w, h, px) {
            Some(url) => pick("", url)
            None => (core.say)(tr("android-settings.station.imageFailed"))
          }
        }
        PixelsFailed => {
          mark_pick.reading = ""
          (core.say)(tr("android-settings.station.imageFailed"))
        }
      }
    }
    sheet_head(c, fill("android-settings.station.emojiTitle", [("name", name)]))
    let emojis = mark_pick.emojis
    let typed_key = "mark-typed/" + serial.to_string()
    let query_key = "mark-query/" + serial.to_string()
    // the fields, each frame's words (the one not shown keeps its own)
    let mut query = ""
    let head = fn() {
      c.box(w=Fill(1.0), pl=18.0, pr=18.0, pb=10.0, gap=10.0, fn() {
        let i = seg(c, "mark-side/" + serial.to_string(), [tr("android-settings.station.glyphs"), "Emoji"], if emojis { 1 } else { 0 }, fill=true, height=34.0, radius=17.0)
        mark_pick.emojis = i == 1
        if emojis {
          let typed = field_box(c, typed_key, tr("android-settings.station.emojiPaste"))
          match first_emoji(typed) {
            Some(e) => {
              field_of(typed_key).set("")
              pick(e, "")
            }
            None => ()
          }
        } else {
          query = field_box(c, query_key, tr("android-settings.station.glyphSearch"))
        }
      })
      |> ignore
    }
    head()
    // the icons' colour: the words' own first, then the marks'; the one picked ringed; it colours the grid, and the
    // icon it has, at once
    if !emojis {
      c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pb=10.0, justify=JBetween, fn() {
        for col in [""] + mark_colors {
          let of = mark_color(col).unwrap_or(t.p.text)
          let id = c.id("mark-color/" + col)
          if hit(c, id) {
            mark_pick.color = col
            match glyph {
              Some((g, _)) =>
                set(
                  glyph_emoji(g),
                  "glyph:" + g + (if col == "" { "" } else { ":" + col }),
                )
              None => ()
            }
          }
          c.box(
            w=Px(32.0),
            h=Px(32.0),
            radius=16.0,
            border=if col == mark_pick.color { 2.0 } else { 0.0 },
            border_color=of,
            align=ACenter,
            justify=JCenter,
            id~,
            fn() { c.box(w=Px(18.0), h=Px(18.0), radius=9.0, bg=of, fn() {  }) |> ignore },
          )
          |> ignore
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
    let tint = mark_color(mark_pick.color)
    let rows = (offered.length() + 5) / 6
    let blocks : Array[() -> Unit] = []
    if offered.length() == 0 {
      blocks.push(fn() {
        c.box(w=Fill(1.0), pady=24.0, fn() {
          c.text(tr("android-settings.station.glyphNone"), size=15.0, color=t.p.muted, center=true, w=Fill(1.0)) |> ignore
        })
        |> ignore
      })
    }
    for r in 0..<rows {
      blocks.push(fn() {
        // six to a row, wide enough for a thumb
        c.box(dir=Row, w=Fill(1.0), pl=14.0, pr=14.0, pb=4.0, gap=4.0, fn() {
          for k in 0..<6 {
            let i = r * 6 + k
            if i >= offered.length() {
              c.box(w=Fill(1.0), fn() {  }) |> ignore
              continue
            }
            let key = offered[i]
            let on = (if emojis { bare_emoji(key) } else { key }) == kept
            let id = c.id("mark/" + key)
            if hit(c, id) {
              if emojis {
                pick(key, "")
              } else {
                pick(glyph_emoji(key), "glyph:" + key + (if mark_pick.color == "" { "" } else { ":" + mark_pick.color }))
              }
            }
            c.box(
              w=Fill(1.0),
              h=Px(56.0),
              radius=14.0,
              bg=if on {
                t.p.accent_bg
              } else if c.pressed(id) {
                @sf.alpha(t.p.text, 0.05)
              } else {
                0L
              },
              align=ACenter,
              justify=JCenter,
              id~,
              fn() {
                if emojis {
                  c.text(key, size=26.0, wrap=false, line=30.0) |> ignore
                } else {
                  @sf.station_mark(c, "", "glyph:" + key, 24.0, tint.unwrap_or(if on { t.p.accent } else { t.p.text }))
                }
              },
            )
            |> ignore
          }
        })
        |> ignore
      })
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), pt=6.0, fn() {
        if pick_row(
            c,
            "mark-picture",
            tr(if picture { "android-settings.station.imageAnother" } else { "android-settings.station.image" }),
            mark=fn() {
              if picture {
                @sf.station_mark(c, "", icon, 20.0, t.p.text)
              } else {
                @sf.icon(c, "image-upload", size=20.0, color=t.p.text) |> ignore
              }
            },
          ) {
          // the picture the system's picker answers with put up as the mark
          let asked = (core.pick_picture)(fn(bytes) {
            mark_pick.asking = false
            match bytes {
              Some(b) =>
                match picture_mark(b) {
                  Some(url) => pick("", url)
                  None => {
                    mark_pictures.val += 1
                    mark_pick.reading = "mem:station-mark/\{mark_pictures.val}"
                    @ui.add_image(mark_pick.reading, b)
                  }
                }
              None => ()
            }
          })
          mark_pick.asking = asked
          if !asked {
            (core.say)(tr("android-settings.station.imageFailed"))
          }
        }
        if @sf.has_station_mark(emoji, icon) &&
          pick_row(c, "mark-none", tr("android-settings.station.emojiClear"), mark=fn() {
            @sf.icon(c, "close", size=20.0, color=t.p.text) |> ignore
          }) {
          pick("", "")
        }
        gap(c, 24.0)
      })
      |> ignore
    })
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { scroll_page(c, "mark/" + serial.to_string() + (if emojis { "/e" } else { "/g" }), blocks) })
    |> ignore
  })
}

///|
/// The emoji a glyph keeps beside it.
fn glyph_emoji(name : String) -> String {
  match glyph_list.iter().find_first(fn(g) { g.0 == name }) {
    Some(g) => g.1
    None => ""
  }
}
