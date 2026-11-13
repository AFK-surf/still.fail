// A station's or a workspace's mark picked in a sheet: one of
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
/// The colours a glyph can be given, in the picker's order.
// kept across runs: a table of constants, never written
let mark_colors : Array[String] = ["red", "orange", "amber", "green", "teal", "blue", "purple", "pink"]

///|
/// The picker as it is while up, its own each time it opens (what reads it told as it changes).
priv struct MarkPick {
  /// the side shown: the icons' (0), the emoji's (1), a picture's (2)
  side : @signals.Signal[Int]
  /// the icons' colour ("": the words')
  color : @signals.Signal[String]
  /// a picture picked too large to put up as it is, being read to make it small (its key), "" none
  reading : @signals.Signal[String]
  /// an emoji pasted or typed, and words to find an icon by: each side's field its own
  typed : @ui.Field
  query : @ui.Field
  /// whether it is still up: what comes for it after it has gone (the system's picker's answer, a picture read) is let
  /// go of, neither put up nor said to have failed
  up : Ref[Bool]
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
/// A picture too large to put up as it is made small: its middle square at 96 px, read
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
let mark_pictures : Ref[Int] = Ref(0)

///|
/// The mark picker (openMarkPick) for `name`, whose mark is `emoji` and `icon` now: `save(emoji, icon)` sets one,
/// `what` naming it should it fail ("" and "" take it away). What it holds is nodes of the window's tree, made once as it
/// opens (@sf.panel_nodes).
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
  let st : MarkPick = {
    side: @signals.signal(if picture { 2 } else if glyph is None && emoji != "" { 1 } else { 0 }),
    color: @signals.signal(match glyph {
      Some((_, col)) => col
      None => ""
    }),
    reading: @signals.signal(""),
    typed: @ui.Field::new(),
    query: @ui.Field::new(),
    up: Ref(true),
  }
  // (a sheet of its own with touch, a dialog with keyboard and mouse: the presenters'; its grid scrolls in what is left)
  @sf.panel_nodes(
    fill("android-settings.station.emojiTitle", [("name", name)]),
    fn(v, close) {
      let close = fn() {
        st.up.val = false
        close()
      }
      mark_pick_body(v, core, st, emoji, icon, glyph, picture, set, close)
    },
    from=Unanchored,
    tall=mark_tall,
    gone=fn() { st.up.val = false },
  )
}

///|
/// What the picker holds, in node `v`, given what sets a mark and what closes it.
fn mark_pick_body(
  v : @view.View,
  core : Core,
  st : MarkPick,
  emoji : String,
  icon : String,
  glyph : (String, String)?,
  picture : Bool,
  set : (String, String) -> Unit,
  close : () -> Unit,
) -> Unit {
  let pick = fn(e : String, i : String) {
    close()
    set(e, i)
  }
  // a picture too large as it is, read: made small and put up as its pixels come, or said to be none as its read
  // fails (the decode's word, tree_image_pixels)
  v.pick(fn() { st.reading.get() }, fn(r, src) {
    guard src != "" else { return }
    let read = @ui.tree_image_pixels(r, src, mark_picture_read)
    let state = fn() {
      match read() {
        None => 0
        Some(PixelsRead(_, _, _)) => 1
        Some(_) => 2
      }
    }
    r.reacts(state, fn(s) {
      guard s != 0 && st.up.val else { return }
      let made = match @signals.untracked(read) {
        Some(PixelsRead(w, h, px)) => picture_mark_small(w, h, px)
        _ => None
      }
      st.reading.set("")
      match made {
        Some(url) => pick("", url)
        None => (core.say)(tr("android-settings.station.imageFailed"))
      }
    })
  })
  // (filling its share, it lays out its own sides: a page's room)
  v.box(fn(b) {
    @sf.style_node(b, fn() { mark_body })
    mark_head_node(b, st)
    // each side all of what is under the sides, one in the other's place at once (a tab's): its field, the icons'
    // colours, the grid; a picture's its own. A picture its own side, as the icons and the emoji are; none the grid's
    // first cell, on both of theirs: neither at the end of the hundreds of icons, scrolled to, nor a card under the
    // grid taking its room (the user, 2026-11-13: 要翻很久, 整体重新设计一下布局)
    b.pick(fn() { st.side.get() }, fn(room, side) {
      room.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      if side == 2 {
        mark_picture_node(room, core, st, icon, picture, pick)
        return
      }
      mark_field_node(room, st, side == 1, pick)
      // the icons' colour: the words' own first, then the marks'; the one picked ringed; it colours the grid, and the
      // icon it has, at once
      if side == 0 {
        room.box(fn(row) { mark_colours_node(row, st, glyph, set) }) |> ignore
      }
      mark_grid_node(room, st, emoji, icon, glyph, picture, pick)
    })
  })
  |> ignore
}

///|
/// The sides across node `v`: the icons', the emoji's, a picture's.
fn mark_head_node(v : @view.View, st : MarkPick) -> Unit {
  v.box(fn(h) {
    @sf.style_node(h, fn() { mark_head })
    h.box(fn(line) {
      line.row(Is(true)) |> ignore
      line.box(fn(slot) {
        @sf.segmented_node(
          slot,
          fn() { [tr("android-settings.station.glyphs"), "Emoji", tr("android-settings.station.pictures")] },
          fn() { st.side.get() },
          fn(i) { st.side.set(i) },
        )
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A side's field in node `v`: the emoji's (`emojis`) an emoji pasted or typed (picked as it is), the icons' words to
/// find an icon by; each keeps its own as the other is shown.
fn mark_field_node(v : @view.View, st : MarkPick, emojis : Bool, pick : (String, String) -> Unit) -> Unit {
  v.box(fn(f) {
    @sf.style_node(f, fn() { mark_field })
    if emojis {
      @sf.input_node(f, st.typed, placeholder=tr("android-settings.station.emojiPaste"), edited=fn(words) {
        match first_emoji(words) {
          Some(e) => {
            st.typed.set("")
            pick(e, "")
          }
          None => ()
        }
      })
      |> ignore
    } else {
      @sf.input_node(f, st.query, placeholder=tr("android-settings.station.glyphSearch")) |> ignore
    }
  })
  |> ignore
}

///|
/// The icons' colours across node `row`, each a round button named by it (the words' own by the icons' name), the one
/// picked ringed and said to be; pressed, the icon the mark has (`glyph`) set in it at once.
fn mark_colours_node(row : @view.View, st : MarkPick, glyph : (String, String)?, set : (String, String) -> Unit) -> Unit {
  @sf.style_node(row, fn() { mark_colours })
  for col in [""] + mark_colors {
    // (as far apart as they go: an equal share of what they leave between each two, mark_colours' JBetween)
    if col != "" {
      row.box(fn(apart) { apart.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore }) |> ignore
    }
    let of = fn() { mark_color(col).unwrap_or(@sf.theme().p.text) }
    let on = fn() { st.color.get() == col }
    row.box(fn(ring) {
      @sf.style_node(ring, fn() { mark_colour }, in_row=true)
      ring.edge(By(fn() { (if on() { mark_ring } else { 0.0 }, of()) })) |> ignore
      @sf.presses_node(ring, fn() {
        st.color.set(col)
        match glyph {
          Some((g, _)) => set(glyph_emoji(g), "glyph:" + g + (if col == "" { "" } else { ":" + col }))
          None => ()
        }
      })
      ring.says(By(fn() {
        Some(@view.said(Button, label=if col == "" { tr("android-settings.station.glyphs") } else { col }, selected=on()))
      }))
      |> ignore
      ring.box(fn(dot) {
        @sf.style_node(dot, fn() { mark_colour_dot })
        dot.ground(By(of)) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// What scrolls, in node `v` (all of what is left: the sheet as tall as it comes to, up to its share): the grid's rows
/// in a @sf.panel_list_node, its first cell none (on the accent's wash where the mark has none), then the side's own.
/// Its rows are those of the side shown and the words typed: either changed, they are other rows, the old let go and
/// the new made at once, as the list's are as it scrolls.
fn mark_grid_node(
  v : @view.View,
  st : MarkPick,
  emoji : String,
  icon : String,
  glyph : (String, String)?,
  picture : Bool,
  pick : (String, String) -> Unit,
) -> Unit {
  // the one it has, on the accent's wash; none's cell where it has none
  let kept = fn(emojis : Bool) {
    if !@sf.has_station_mark(emoji, icon) {
      mark_none_cell
    } else if emojis {
      if glyph is None && !picture && emoji != "" { bare_emoji(emoji) } else { "" }
    } else {
      match glyph {
        Some((g, _)) => g
        None => ""
      }
    }
  }
  // none first; then the icons found by every word typed (in their names, English or Chinese), all of them for none;
  // the emoji, the mark's own first where it is none of them
  let offered = @signals.computed(fn(_) {
    let emojis = st.side.get() == 1
    let k = kept(emojis)
    let l = [mark_none_cell]
    if !emojis {
      let terms = st.query.text().to_lower().split(" ").map(fn(x) { x.to_owned() }).filter(fn(x) { x != "" }).collect()
      for g in glyph_list {
        if terms.iter().all(fn(term) { g.2.contains(term) }) {
          l.push(g.0)
        }
      }
    } else if k != "" && k != mark_none_cell && !station_emoji.iter().any(fn(e) { bare_emoji(e) == k }) {
      l.push(emoji)
      for i in 0..<(station_emoji.length() - 1) {
        l.push(station_emoji[i])
      }
    } else {
      for e in station_emoji {
        l.push(e)
      }
    }
    l
  })
  // (a block's key: what it shows of, the side and the words typed, then which; under none alone, that none was found)
  let of = fn() { if st.side.get() == 1 { "e//" } else { "g/" + st.query.text() + "/" } }
  let keys = fn() {
    let at = of()
    let n = offered.get().length()
    let l : Array[String] = []
    for r in 0..<((n + mark_across - 1) / mark_across) {
      l.push(at + r.to_string())
    }
    if n == 1 {
      l.push(at + "none")
    }
    l
  }
  v.box(fn(room) {
    @sf.style_node(room, fn() { mark_grid_room })
    // (the other side's list another, from its top, as the old one's key was the side's)
    room.pick(fn() { st.side.get() == 1 }, fn(list, _) {
      list.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      @sf.panel_list_node(
        list,
        keys,
        fn(r, k) {
          if k.has_suffix("/none") {
            @sf.page_note_node(r, fn() { tr("android-settings.station.glyphNone") })
            return
          }
          let emojis = k.has_prefix("e/")
          let mut row = 0
          for ch in k.exact_view(start=k.rev_find("/").unwrap_or(0) + 1) {
            row = row * 10 + (ch.to_int() - '0'.to_int())
          }
          let all = @signals.untracked(fn() { offered.get() })
          let cells : Array[String] = []
          let end = (row + 1) * mark_across
          for i in (row * mark_across)..<(if end < all.length() { end } else { all.length() }) {
            cells.push(all[i])
          }
          mark_row_node(r, st, cells, emojis, kept(emojis), pick)
        },
        est=mark_row_est,
      )
      |> ignore
    })
  })
  |> ignore
}

///|
/// The key of none's cell, the grid's first: no icon's or emoji's, nor the "" of the one a side's grid does not have.
let mark_none_cell : String = "none:"

///|
/// A row of the grid in node `v`: `cells` six to it, each as wide as a sixth of it (a thumb's), square, the one the mark
/// has (`kept`) on the accent's wash; pressed, picked (an icon in the colour picked; none, the mark taken away).
fn mark_row_node(
  v : @view.View,
  st : MarkPick,
  cells : Array[String],
  emojis : Bool,
  kept : String,
  pick : (String, String) -> Unit,
) -> Unit {
  v.box(fn(row) {
    @sf.style_node(row, fn() { mark_row })
    for k in 0..<mark_across {
      if k >= cells.length() {
        row.box(fn(none) { @sf.style_node(none, fn() { mark_cell_none }, in_row=true) }) |> ignore
        continue
      }
      let key = cells[k]
      let none = key == mark_none_cell
      let on = (if emojis && !none { bare_emoji(key) } else { key }) == kept
      let press = fn() {
        if none {
          pick("", "")
        } else if emojis {
          pick(key, "")
        } else {
          let col = st.color.get()
          pick(glyph_emoji(key), "glyph:" + key + (if col == "" { "" } else { ":" + col }))
        }
      }
      let label = if none { tr("android-settings.station.emojiClear") } else { key }
      row.box(fn(cell) {
        @sf.style_node(cell, fn() { if on { mark_cell_on } else { mark_cell } }, in_row=true)
        // (square: as tall as it is wide)
        cell.aspect(Is(1.0)) |> ignore
        if none {
          // (a cross in the muted ink: no mark; the accent's where it is the one the mark has)
          @sf.icon_node(cell, "close", mark_glyph, By(fn() {
            let t = @sf.theme()
            if on { t.p.accent_text } else { t.p.muted }
          }))
          |> ignore
        } else if emojis {
          @sf.words_node(cell, fn() { key }, fn() { mark_emoji_words }) |> ignore
        } else {
          @sf.station_mark_node(cell, fn() { "" }, fn() { "glyph:" + key }, mark_glyph, fn() {
            let t = @sf.theme()
            mark_color(st.color.get()).unwrap_or(if on { t.p.accent_text } else { t.p.text })
          }, fn() { 0 })
        }
        // (a finger's press rippling over it, as an old row's: square outside a card)
        @sf.rippled_node(cell, press, 0.0, fn() { label })
        cell.says(By(fn() { Some(@view.said(Button, label~, selected=on)) })) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A picture's side, in node `v` (what is left, its things in its middle): the picture the mark has, large, or the
/// upload's icon where it has none; under it 上传图片 (更换图片 where it has one): the system's picker's answer put up, one
/// too large read and made small first.
fn mark_picture_node(
  v : @view.View,
  core : Core,
  st : MarkPick,
  icon : String,
  picture : Bool,
  pick : (String, String) -> Unit,
) -> Unit {
  let up = fn() {
    // the picture the system's picker answers with put up as the mark, while the picker is up
    let asked = (core.pick_picture)(fn(bytes) {
      guard st.up.val else { return }
      match bytes {
        Some(b) =>
          match picture_mark(b) {
            Some(url) => pick("", url)
            None => {
              mark_pictures.val += 1
              let key = "mem:station-mark/\{mark_pictures.val}"
              @ui.add_image(key, b)
              st.reading.set(key)
            }
          }
        None => ()
      }
    })
    if !asked {
      (core.say)(tr("android-settings.station.imageFailed"))
    }
  }
  v.box(fn(side) {
    @sf.style_node(side, fn() { mark_picture_side })
    side.box(fn(shown) {
      @sf.style_node(shown, fn() { mark_picture_shown })
      if picture {
        @sf.station_mark_node(shown, fn() { "" }, fn() { icon }, mark_picture, fn() { @sf.theme().p.text }, fn() { 0 })
      } else {
        @sf.icon_node(shown, "image-upload", mark_picture_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      }
    })
    |> ignore
    @sf.button_node(
      side,
      fn() { tr(if picture { "android-settings.station.imageAnother" } else { "android-settings.station.image" }) },
      up,
      icon="image-upload",
    )
    |> ignore
  })
  |> ignore
}

///|
/// The picker's body: in a page's room, filling the sheet's share.
// kept across runs: a value (no field of it changes)
let mark_body : @ui.Style = @sf.pg_room.then(@ui.style(h=@sf.grow))

///|
/// The picker's share of the window (a sheet that tall; a dialog at most that tall).
let mark_tall : Double = 0.78

///|
/// The sides, 10 under them.
// kept across runs: a value (no field of it changes)
let mark_head : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
/// A side's field, 10 under it.
// kept across runs: a value (no field of it changes)
let mark_field : @ui.Style = @ui.css("w=Full pb=S2_5")

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
/// What scrolls: the grid's rows, in what is left of it (its grid a @sf.panel_list: the sheet
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
/// A picture's side: what is left, its picture (or the upload's icon) and its button in its middle, 16 apart, a little
/// over its middle (24 under).
// kept across runs: a value (no field of it changes)
let mark_picture_side : @ui.Style = @ui.css("w=Full gap=S4 pb=S6 align=ACenter justify=JCenter").then(@ui.style(h=@sf.grow))

///|
/// The picture shown: a square of a large block's corner, the canvas's raised ground.
// kept across runs: a value (no field of it changes)
let mark_picture_shown : @ui.Style = @ui.css("w=S24 h=S24 radius=Xl2 bg=Surface align=ACenter justify=JCenter")

///|
let mark_picture : Double = 96.0

///|
let mark_picture_icon : Double = 32.0

///|
/// The emoji a glyph keeps beside it.
fn glyph_emoji(name : String) -> String {
  match glyph_list.iter().find_first(fn(g) { g.0 == name }) {
    Some(g) => g.1
    None => ""
  }
}
