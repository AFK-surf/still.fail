// A file and a quote as a message and the composer show them (ember web/src/Chat.tsx FileTile, FileName, FileCard,
// QuoteCard; Chat.css.ts fileTile, fileCard…, quoteCard…, later.css.ts fileCard): a file's sheet with its extension on
// it, its name cut in its middle, its card with its size or how far it has gone; a quote's card with whose it is, its
// own picture and what is said about it.

///|
/// What a file is, at a glance (FileTile): a sheet 30 by 36, its top corner folded, drawn in the muted ink 1.5 wide,
/// its extension on it in the text's ink (six letters at most, upper case), or two lines where it has none; a folder its
/// own shape (`dir`). `progress`: how far it has gone (going up, coming down), the sheet filling from its foot with the
/// accent at 22%; `error`: its extension red.
pub fn file_tile(c : @ui.Ctx, name : String, dir? : Bool = false, progress? : Double? = None, error? : Bool = false) -> Unit {
  let t = theme()
  if dir {
    c.box(style=tile_box, fn() {
      c.shapes(
        [@ui.shape_of(@pixels.svg_path(tile_folder, c.scale), stroke=t.p.muted, width=tile_stroke)],
        w=Px(tile_w),
        h=Px(tile_h),
        name="file-tile",
      )
      |> ignore
    })
    |> ignore
    return
  }
  let dot = name.rev_find(".")
  let ext = match dot {
    Some(i) if i > 0 && name.length() - i <= tile_ext_most => name.view(start_offset=i + 1).to_string().to_upper()
    _ => ""
  }
  let shapes = match progress {
    Some(part) => [file_tile_fill(c.scale, part, alpha(t.p.accent, tile_fill_share))]
    None => []
  }
  shapes.push(
    @ui.shape_of(
      @pixels.svg_path(tile_outline + tile_fold + (if ext == "" { tile_lines } else { "" }), c.scale),
      stroke=t.p.muted,
      width=tile_stroke,
    ),
  )
  c.box(style=tile_box, fn() {
    c.shapes(shapes, w=Px(tile_w), h=Px(tile_h), name="file-tile") |> ignore
    if ext != "" {
      // on the sheet's lower part, its middle at 14.5 (FileTile's <text x=14.5 y=27>), .62 of the card's 14
      c.layer(fn() {
        c.box(style=tile_ext_room, fn() {
          // det-ok(box-loose): FileTile's extension is .62 of the card's 14 (8.68), off the type scale
          c.text(ext, style=if error { tile_ext_failed } else { tile_ext }, size=tile_ext_size) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The sheet filled from its foot `part` of its height (FileTile's rect from y = 36 − 36 × part, cut to the sheet's
/// outline): the outline's inside (a convex shape) cut below that line, in the sheet's points (its curves cut for
/// `scale` pixels a point).
pub fn file_tile_fill(scale : Double, part : Double, color : Int64) -> @ui.Shape {
  let share = if part < 0.0 { 0.0 } else if part > 1.0 { 1.0 } else { part }
  let from = tile_h * (1.0 - share)
  let cut = @pixels.svg_path(tile_outline, scale).filter_map(fn(o) {
    let (pts, closed) = o
    let n = pts.length() / 2
    let out : Array[Double] = []
    for i in 0..<n {
      let (ax, ay) = (pts[2 * i], pts[2 * i + 1])
      let j = (i + 1) % n
      let (bx, by) = (pts[2 * j], pts[2 * j + 1])
      if ay >= from {
        out.push(ax)
        out.push(ay)
      }
      if (ay >= from) != (by >= from) {
        let k = (from - ay) / (by - ay)
        out.push(ax + (bx - ax) * k)
        out.push(from)
      }
    }
    // (nothing of it come yet: nothing filled)
    if out.length() < 6 {
      None
    } else {
      Some((out, closed))
    }
  })
  @ui.shape_of(cut, fill=color)
}

///|
/// The sheet's outline, its fold, its two lines (where it has no extension), a folder's shape (FileTile's paths), and
/// what it is drawn with.
let tile_outline : String = "M6 1.75H19L26.25 9V31Q26.25 34.25 23 34.25H6Q2.75 34.25 2.75 31V5Q2.75 1.75 6 1.75Z"

///|
let tile_fold : String = "M19 1.75V6.5Q19 9 21.5 9H26.25"

///|
let tile_lines : String = "M8.5 19H20.5M8.5 23.5H17"

///|
let tile_folder : String = "M2.75 8.5Q2.75 5.75 5.5 5.75H11.5L14.5 9H24.5Q27.25 9 27.25 11.75V28.5Q27.25 31.25 24.5 31.25H5.5Q2.75 31.25 2.75 28.5Z"

///|
let tile_stroke : Double = 1.5

///|
let tile_h : Double = 36.0

///|
let tile_w : Double = 30.0

///|
let tile_fill_share : Double = 0.22

///|
/// The most an extension is long, its dot with it (FileTile: 5 letters and the dot; FileName: 7).
let tile_ext_most : Int = 6

///|
let name_ext_most : Int = 8

///|
// kept across runs: a value (no field of it changes)
let tile_box : @ui.Style = @ui.style(w=file_sheet_w, h=file_sheet_h)

///|
// kept across runs: a value (no field of it changes)
let tile_ext_room : @ui.Style = @ui.css("w=Full h=Full pt=S4_5 align=ACenter")

///|
/// The extension: .62 of the card's 14, 600 (fileTileExt), red when it failed.
// kept across runs: a value (no field of it changes)
let tile_ext : @ui.TextStyle = @ui.text_style(weight=Semibold, color=Fg, wrap=false)

///|
/// (.62 of the card's 14: 8.68)
let tile_ext_size : Double = 14.0 * 0.62

///|
// kept across runs: a value (no field of it changes)
let tile_ext_failed : @ui.TextStyle = tile_ext.then(@ui.text_style(color=Danger))

///|
/// A file's name on one line, what is cut short the middle of it, never its extension (FileName: an extension of 7 at
/// most, the dot with it), 13 on 20.
pub fn file_name(c : @ui.Ctx, name : String) -> Unit {
  let (stem, ext) = match name.rev_find(".") {
    Some(i) if i > 0 && name.length() - i <= name_ext_most =>
      (name.view(end_offset=i).to_string(), name.view(start_offset=i).to_string())
    _ => (name, "")
  }
  c.box(style=name_row, fn() {
    c.box(style=name_stem, fn() { c.text(stem, style=card_name) |> ignore }) |> ignore
    if ext != "" {
      c.text(ext, style=card_name) |> ignore
    }
  })
  |> ignore
}

///|
/// What was done with a file's card this frame: its ✕, its ↻ or its ✎ pressed, or (one that opens) the card itself.
pub(all) struct FileCardDone {
  removed : Bool
  retried : Bool
  restored : Bool
  opened : Bool
}

///|
/// A file as a card (FileCard; later.css.ts fileCard): its sheet, its name over its size (or how far it has gone up,
/// `pending`, `sent` of it; or what the core's `download` says while it comes down, its share filling the sheet; or why
/// it failed, `error`, in red), 236 wide at most, 8 by 10 in and 7 at the sheet's side, rounded as the sheet stands in
/// (13), on the neutral ground; its path (or its name) its tip. `remove` and `retry` its own ✕ and ↻ at its end, `slot`
/// room there for a button laid over it (a message's). `open`: pressing it opens the file (a message's: fileCardOpen),
/// the hover ground under the pointer. `key` names it. Pasted words kept as a file (Chat.tsx PendingFile's pasted
/// card): `title` in place of its name (what they begin with), `meta` in place of its size (how many characters), their
/// own ✕'s `remove_label`, `restore` its ✎ putting them back as words. A message's file the core downloads: its ✕ and ↻
/// said as calling that off and asking it again (`remove_label`, `retry_label`). `dir`: a folder's (file_tile).
/// `named`: a file named where it is and not going (a station's file sent as its path: Chat.css.ts fileCard[data-named]),
/// its card no ground, its edge dashed in the strong line. Going up and how far not known yet (`pending`, no `sent`),
/// a spinner where its sheet is: what goes on is seen to (an empty sheet that stays so looks stuck).
pub fn file_card(
  c : @ui.Ctx,
  key : String,
  name : String,
  size : Double,
  path? : String = "",
  dir? : Bool = false,
  named? : Bool = false,
  pending? : Bool = false,
  sent? : Double? = None,
  error? : String = "",
  download? : (Double, String)? = None,
  remove? : Bool = false,
  retry? : Bool = false,
  slot? : Bool = false,
  open? : Bool = false,
  title? : String = "",
  meta? : String = "",
  restore? : Bool = false,
  remove_label? : String = "",
  retry_label? : String = "",
) -> FileCardDone {
  let id = c.id(key)
  if open {
    c.cursor(id, Hand)
  }
  let x = c.id(key + "/remove")
  let again = c.id(key + "/retry")
  let back = c.id(key + "/restore")
  let said = meta
  let going = match sent {
    Some(s) if pending && size > 0.0 =>
      t(
        "web-main.file.uploadingPart",
        args=[("percent", (s / size * 100.0).floor().to_int().to_string()), ("size", file_size(size))],
      )
    _ => t("common.uploading")
  }
  let meta = if error != "" {
    error
  } else if pending {
    going
  } else if said != "" {
    said
  } else {
    match download {
      Some((_, words)) => words
      None => file_size(size)
    }
  }
  let progress = if pending {
    Some(sent.unwrap_or(0.0) / (if size > 1.0 { size } else { 1.0 }))
  } else {
    download.map(fn(d) { d.0 })
  }
  let ground = if named { card_named } else { card_box }
  let b = c.box(
    style=if open && c.hovered(id) { ground.then(card_hot) } else { ground },
    border_color?=if named { Some(theme().p.line_strong) } else { None },
    id~,
    fn() {
      if pending && sent is None {
        c.box(style=tile_going, fn() { spinner(c, size=tile_going_spinner) |> ignore }) |> ignore
      } else {
        file_tile(c, name, dir~, progress~, error=error != "")
      }
      c.box(style=card_words, fn() {
        if title != "" {
          c.box(style=name_row, fn() { c.box(style=name_stem, fn() { c.text(title, style=card_name) |> ignore }) |> ignore })
          |> ignore
        } else {
          file_name(c, name)
        }
        c.text(meta, style=if error != "" { card_failed } else { card_meta }) |> ignore
      })
      |> ignore
      if retry {
        let label = if retry_label != "" { retry_label } else { t("web-main.composer.retryUpload") }
        card_button(c, again, "refresh", label)
        tip(c, key + "/retry-tip", again, label)
      }
      if restore {
        card_button(c, back, "edit", t("web-main.composer.expandPaste"))
        tip(c, key + "/restore-tip", back, t("web-main.composer.expandPaste"))
      }
      if remove {
        card_button(c, x, "close", if remove_label != "" {
          remove_label
        } else {
          t("web-main.file.remove", args=[("name", name)])
        })
      }
      if slot {
        c.box(style=card_slot, fn() {  }) |> ignore
      }
    },
  )
  c.semantics(b, Group, id~, label=if title != "" { title } else { name })
  // (pasted words: all of what is said of them, a failure at length)
  tip(c, key + "/tip", id, if path != "" { path } else if title != "" { meta } else { name })
  let removed = remove && c.clicked(x)
  let retried = retry && c.clicked(again)
  let restored = restore && c.clicked(back)
  { removed, retried, restored, opened: open && !removed && !retried && !restored && c.clicked(id) }
}

///|
/// A card's own button at its end (fileCardRemove): 22 round, nothing under it but under the pointer (the hover
/// ground), its icon in the muted ink (the text's under the pointer); named.
fn card_button(c : @ui.Ctx, id : Int, icon_name : String, label : String) -> Unit {
  let p = theme().p
  c.cursor(id, Hand)
  let hot = c.lit(id)
  let b = c.box(style=if hot { card_button_hot } else { card_button_box }, id~, fn() {
    icon(c, icon_name, size=if icon_name == "close" { card_close_icon } else { card_button_icon }, color=if hot {
      p.text
    } else {
      p.muted
    })
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
}

///|
/// What a file's card, a message's pictures and its pasted text are rounded (MESSAGE_FILE_CORNER: the sheet's room 9.75
/// and its corner 3.25).
pub let message_file_corner : Double = 13.0

///|
pub let message_file_radius : @ui.Radius = rounded(message_file_corner)

///|
/// The composer's box's corner: a card's of the ladder's (its buttons round in its corners its padding in, what waits
/// in it a block of the ladder's there: composer_inner).
pub let composer_corner : @ui.Radius = rounded(card_corner)

///|
/// A file's card at its widest (fileCard: 236).
pub let file_card_w : Double = 236.0

///|
let card_button_icon : Double = 13.0

///|
let card_close_icon : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let card_box : @ui.Style = @ui.style(
  row=true,
  max_w=Fixed(file_card_w),
  pl=file_sheet_in,
  pr=S2_5,
  py=S2,
  gap=S2_5,
  bg=Neutral,
  // (in a corner of what holds it, a composer's box: as far in as from its edges, its corner concentric)
  radius=InnerOr(message_file_radius),
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let card_hot : @ui.Style = @ui.css("bg=Hover")

///|
/// A named file's card (fileCard[data-named]: no ground, 1px dashed in --line-strong, given as it is drawn).
// kept across runs: a value (no field of it changes)
let card_named : @ui.Style = card_box.then(@ui.css("bg=Clear border=B1 dashed"))

///|
/// Where the sheet is while what goes up says not how far (the old phone's going card: a 16 spinner).
// kept across runs: a value (no field of it changes)
let tile_going : @ui.Style = tile_box.then(@ui.css("align=ACenter justify=JCenter"))

///|
let tile_going_spinner : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let card_words : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let card_slot : @ui.Style = @ui.style(w=Fixed(card_button_side), h=Fixed(card_button_side))

///|
// kept across runs: a value (no field of it changes)
let card_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let card_meta : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, leading=L4, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let card_failed : @ui.TextStyle = card_meta.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let card_button_box : @ui.Style = @ui.style(
  w=Fixed(card_button_side),
  h=Fixed(card_button_side),
  radius=Full,
  align=ACenter,
  justify=JCenter,
)

///|
/// A card's own button across (fileCardRemove: 22).
let card_button_side : Double = 22.0

///|
// kept across runs: a value (no field of it changes)
let card_button_hot : @ui.Style = card_button_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let name_row : @ui.Style = @ui.css("row w=Full")

///|
/// As wide as it is, short of the room the extension leaves (fileCardStem: cut with an ellipsis), the extension right
/// after it.
// kept across runs: a value (no field of it changes)
let name_stem : @ui.Style = @ui.css("w=Hug")

///|
/// What was done with a quote's card this frame: its source pressed (`jump`), its ✕ pressed.
pub(all) struct QuoteCardDone {
  jumped : Bool
  removed : Bool
}

///|
/// One quote (QuoteCard): the passage, two lines at most, small and quiet (the text's ink under the pointer when it
/// leads to its message, `jump`), after a quote's mark and whose it is (a page's or an image's mark: its pin's number
/// and its first line instead); its own `picture` under it; what is said about it (`comment`'s words, or `comment_field`
/// where it is written: the composer's); ✕ at its corner where it can be let go (`remove`). In the composer
/// (`composer`) its corner the composer's inner and its words further in. `key` names it.
pub fn quote_card(
  c : @ui.Ctx,
  key : String,
  author : String,
  words : String,
  role? : String = "",
  comment? : String = "",
  composer? : Bool = false,
  jump? : Bool = false,
  remove? : Bool = false,
  picture? : () -> Unit,
  comment_field? : () -> Unit,
) -> QuoteCardDone {
  let p = theme().p
  let source = c.id(key + "/source")
  let x = c.id(key + "/remove")
  // a mark on a previewed page or an image: its pin's number
  let pin = if role == "page" || role == "image" {
    let digits = StringBuilder::new()
    for ch in author.rev_iter() {
      if ch >= '0' && ch <= '9' {
        digits.write_char(ch)
      } else {
        break
      }
    }
    digits.to_string().rev()
  } else {
    ""
  }
  if jump {
    c.cursor(source, Hand)
    tip(c, key + "/jump-tip", source, t("web-main.quote.jump"))
  } else if pin != "" {
    tip(c, key + "/pin-tip", source, words)
  }
  let hot = jump && c.lit(source)
  c.box(style=if composer { quote_box_composer } else { quote_box }, fn() {
    // (a pin in its top corner: there the ladder's inset from both its edges, concentric with it)
    let source_look = match (composer, pin != "") {
      (true, false) => quote_source_composer
      (true, true) => quote_source_composer_pin
      (false, false) => quote_source
      (false, true) => quote_source_pin
    }
    c.box(style=source_look, id=source, fn() {
      c.box(style=quote_words, fn() {
        if pin != "" {
          c.box(style=quote_pin, fn() { c.text(pin, style=quote_pin_words) |> ignore }) |> ignore
          c.text(words.split("\n").next().map(fn(s) { s.to_string() }).unwrap_or(""), style=quote_text) |> ignore
        } else {
          c.box(style=quote_mark, fn() { icon(c, "quote", size=quote_icon, color=p.accent) |> ignore }) |> ignore
          c.rich(
            [
              @ui.span(t("web-main.quote.author", args=[("author", author)]), weight=500, color=p.text),
              @ui.span(words),
            ],
            style=if hot { quote_text_hot } else { quote_text },
          )
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    match picture {
      Some(f) => c.box(style=if composer { quote_picture_composer } else { quote_picture }, f) |> ignore
      None => ()
    }
    match comment_field {
      Some(f) => c.box(style=quote_comment_composer, f) |> ignore
      None =>
        if comment != "" {
          c.box(style=quote_comment, fn() { c.text(comment, style=quote_said) |> ignore }) |> ignore
        }
    }
    if remove {
      c.layer(fn() {
        c.box(style=quote_remove_at, fn() {
          card_button(c, x, "close", t("web-main.quote.remove"))
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  { jumped: jump && c.clicked(source), removed: remove && c.clicked(x) }
}

///|
/// A quote's mark (11, the accent's) in a box as tall as its line.
let quote_icon : Double = 11.0

///|
/// quoteCard: 12 round (in the composer its inner corner), the text at 4% over the canvas.
// kept across runs: a value (no field of it changes)
let quote_box : @ui.Style = @ui.style(w=Full, radius=rounded(quote_corner), bg=Over(Bg, faint_ground), clip=true)

///|
/// A quote's corner: a block's of the ladder's, in a message as in the composer (the web's 12 in a message).
let quote_corner : Double = row_corner

///|
// kept across runs: a value (no field of it changes)
let quote_box_composer : @ui.Style = quote_box.then(@ui.style(radius=InnerOr(rounded(composer_inner))))

///|
/// What sits in the composer's corners is rounded concentric with it, the ladder's next step in.
pub let composer_inner : Double = row_corner

///|
/// The composer's padding: the ladder's inset, so what stands in its corners has the ladder's next corner (a quote's,
/// a file's; its round controls round there: the computer's 32 and the phone's 36 alike).
pub let composer_pad : Double = corner_inset

///|
/// quoteCardSource: 7 by 11 over the words (in the composer 9 over, 16 at its start, 34 at its end for its ✕).
// kept across runs: a value (no field of it changes)
let quote_source : @ui.Style = @ui.style(w=Full, px=room(quote_in), pt=room(quote_over), pb=room(quote_over))

///|
/// A quote card's words 11 in and 7 over (quoteCardSource); in the composer 16 in, 34 at its end, 9 over; what is said
/// 3 under the words, 7 under it (10 in the composer).
let quote_in : Double = 11.0

///|
let quote_over : Double = 7.0

///|
let quote_end_composer : Double = 34.0

///|
let quote_over_composer : Double = 9.0

///|
let quote_said_over : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let quote_source_composer : @ui.Style = @ui.style(w=Full, pl=S4, pr=room(quote_end_composer), pt=room(quote_over_composer))

///|
/// A page mark's quote: its pin (a capsule 16 high) the ladder's inset from its top and start, concentric with its
/// corner (capsule_in(quote_corner, 16) = corner_inset).
// kept across runs: a value (no field of it changes)
let quote_source_pin : @ui.Style = quote_source.then(@ui.style(pl=inset_room, pt=inset_room))

///|
// kept across runs: a value (no field of it changes)
let quote_source_composer_pin : @ui.Style = quote_source_composer.then(@ui.style(pl=inset_room, pt=inset_room))

///|
// kept across runs: a value (no field of it changes)
let quote_words : @ui.Style = @ui.css("row w=Full gap=S1 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let quote_mark : @ui.Style = @ui.css("h=S4_5 justify=JCenter")

///|
/// quoteCardText: 12 on 18 (1.5), two lines at most, muted; the text's ink under the pointer when it leads somewhere.
// kept across runs: a value (no field of it changes)
let quote_text : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let quote_text_hot : @ui.TextStyle = quote_text.then(@ui.text_style(color=Fg))

///|
/// quoteCardPin: a page mark's number as its pin, 16 high, the accent's ground, white; a capsule (a circle for one
/// figure), so in its quote's corner it stands where its shape is concentric with it (the web's corner 8 8 8 2).
// kept across runs: a value (no field of it changes)
let quote_pin : @ui.Style = @ui.css("h=S4 min_w=S4 px=S1 radius=Full bg=Accent align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let quote_pin_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnAccent, wrap=false)

///|
/// quoteCardPicture: 6 over it, 11 in (in the composer 16).
// kept across runs: a value (no field of it changes)
let quote_picture : @ui.Style = @ui.style(row=true, px=room(quote_in), pt=S1_5)

///|
// kept across runs: a value (no field of it changes)
let quote_picture_composer : @ui.Style = @ui.css("row px=S4 pt=S1_5")

///|
/// quoteCardComment: 3 over, 16 in, 10 under it in the composer; under a message's, 11 in and 7 under.
// kept across runs: a value (no field of it changes)
let quote_comment : @ui.Style = @ui.style(w=Full, px=room(quote_in), pt=room(quote_said_over), pb=room(quote_over))

///|
// kept across runs: a value (no field of it changes)
let quote_comment_composer : @ui.Style = @ui.style(w=Full, px=S4, pt=room(quote_said_over), pb=S2_5)

///|
// kept across runs: a value (no field of it changes)
let quote_said : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)

///|
/// Its ✕ at its top right corner, as far in as makes it concentric with it (a circle: capsule_in).
// kept across runs: a value (no field of it changes)
let quote_remove_at : @ui.Style = @ui.style(
  w=Full,
  pt=capsule_room(quote_corner, card_button_side),
  pr=capsule_room(quote_corner, card_button_side),
  align=AEnd,
)
