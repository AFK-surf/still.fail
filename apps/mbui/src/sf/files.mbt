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
        [@ui.shape_of(tile_outlines(tile_folder, c.scale), stroke=t.p.muted, width=tile_stroke)],
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
      tile_outlines(if ext == "" { tile_sheet_lines } else { tile_sheet }, c.scale),
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
/// The outlines of a tile's drawing (its path data) at `scale`: cut once for each, not again on every frame each tile is
/// drawn.
fn tile_outlines(d : String, scale : Double) -> Array[(Array[Double], Bool)] {
  match tiles_made.get((d, scale)) {
    Some(o) => o
    None => {
      let o = @pixels.svg_path(d, scale)
      tiles_made[(d, scale)] = o
      o
    }
  }
}

///|
/// The tiles' outlines cut so far, by their path data and scale (tile_outlines).
let tiles_made : Map[(String, Double), Array[(Array[Double], Bool)]] = {}

///|
/// The sheet filled from its foot `part` of its height (FileTile's rect from y = 36 − 36 × part, cut to the sheet's
/// outline): the outline's inside (a convex shape) cut below that line, in the sheet's points (its curves cut for
/// `scale` pixels a point).
pub fn file_tile_fill(scale : Double, part : Double, color : Int64) -> @ui.Shape {
  let share = if part < 0.0 { 0.0 } else if part > 1.0 { 1.0 } else { part }
  let from = tile_h * (1.0 - share)
  let cut = tile_outlines(tile_outline, scale).filter_map(fn(o) {
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
/// The sheet with its fold, as drawn with an extension on it; and with its two lines, without.
let tile_sheet : String = tile_outline + tile_fold

///|
let tile_sheet_lines : String = tile_sheet + tile_lines

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
/// (13), on the neutral ground; its path (or its name) its tip. `remove` and `retry` its own ✕ and ↻ at its end (in a
/// message; what waits in the composer has its ✕ on its corner: with_corner_remove), `slot`
/// room there for a button laid over it (a message's). `open`: pressing it opens the file (a message's: fileCardOpen),
/// the hover ground under the pointer. `key` names it. Pasted words kept as a file (Chat.tsx PendingFile's pasted
/// card): `title` in place of its name (what they begin with), `meta` in place of its size (how many characters), their
/// own ✕'s `remove_label`, `restore` its ✎ putting them back as words. A message's file the core downloads: its ✕ and ↻
/// said as calling that off and asking it again (`remove_label`, `retry_label`). `dir`: a folder's (file_tile).
/// `named`: a file named where it is and not going (a station's file sent as its path: Chat.css.ts fileCard[data-named]),
/// its card no ground, its edge dashed in the strong line. Going up and how far not known yet (`pending`, no `sent`),
/// a spinner where its sheet is: what goes on is seen to (an empty sheet that stays so looks stuck). `composer`: waiting
/// in the composer, on composer_card's ground.
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
  composer? : Bool = false,
) -> FileCardDone {
  let id = c.id(key)
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
  let ground = if named && composer {
    card_named.then(card_waiting).then(card_composer_corner())
  } else if named {
    card_named
  } else if composer && open {
    card_composer().then(composer_card()).then(card_open)
  } else if composer {
    card_composer().then(composer_card())
  } else {
    card_box
  }
  let b = c.box(
    // (in the composer, pointed at: the hover's tint over its own ground, not in its place)
    style=if open && !(composer && !named) && c.hovered(id) { ground.then(card_hot) } else { ground },
    border_color?=if named { Some(theme().p.line_strong) } else { None },
    id~,
    fn() {
      if pending && sent is None {
        c.box(style=tile_going, fn() { spinner(c, size=tile_going_spinner) |> ignore }) |> ignore
      } else {
        file_tile(c, name, dir~, progress~, error=error != "")
      }
      // (in a message as wide as what it says; waiting in the composer as wide as its room, its words taking the rest)
      c.box(style=if composer { card_words } else { card_words_hug }, fn() {
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
        // (calling a download off says so on hover, as ↻ does: MessageFileCard's Tip)
        if remove_label != "" {
          tip(c, key + "/remove-tip", x, remove_label)
        }
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
/// What waits to go with a message (a composer's picture, a file's card, a quote), `w` wide (none: the width it is
/// given) and rounded `corner`, with its ✕
/// hung on its top right corner (docs/ui-panels.md: the user, 2026-10-17, on the corner, not in it): 20 round, solid
/// (the ink's, the page's ✕ on it: part of it is on the ground round it), its centre on the corner's curve where it
/// turns 45° (on_corner), reaching past the top as far as past the right edge. `w` wide, the room for that kept at its
/// end, so what comes next in its row stands the row's gap past it; the width it is given (a quote: nothing beside it),
/// none: it reaches past its right edge into the room round it as past its top, as far from that room's edge there as
/// it is from its top (the user, 2026-10-26: 上边距和右边距不一致). `key` names it (its ✕ `key/remove`), `label` what a screen reader
/// calls its ✕; `turn` how far its ✕ is turned (a quarter of a half turn: a ＋, which puts back what was taken out: a
/// shared picture's attachments). Whether its ✕ was pressed.
pub fn with_corner_remove(
  c : @ui.Ctx,
  key : String,
  label : String,
  corner : Double,
  body : () -> Unit,
  w? : Double,
  turn? : Double = 0.0,
) -> Bool {
  let x = c.id(key + "/remove")
  let reach = corner_remove_reach(corner)
  let outer = match w {
    Some(w) => @ui.style(w=Fixed(w + reach))
    None => @ui.style(row=true, w=Full)
  }
  c.box(style=outer, fn() {
    // (the ✕ over the corner of what it is hung on, as far past its right edge as past its top)
    c.box(
      style=match w {
        Some(w) => @ui.style(w=Fixed(w))
        None => @ui.style(w=grow)
      },
      fn() {
        body()
        c.layer(fn() {
          c.box(style=corner_remove_at, fn() {
            let b = c.box(style=corner_remove_box, id=x, tx=reach, ty=-reach, fn() {
              let m = c.box(fn() { corner_remove_mark(c) })
              if turn != 0.0 {
                c.look(m, @ui.look(rot=turn))
              }
            })
            c.semantics(b, Button, id=x, label~)
          })
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(x)
}

///|
/// How far the ✕ of what waits to go reaches past its top and its right edge, its corner `corner` (with_corner_remove):
/// the room a row of them keeps between its lines.
pub fn corner_remove_reach(corner : Double) -> Double {
  on_corner(corner, corner_remove_side)
}

///|
let corner_remove_side : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let corner_remove_at : @ui.Style = @ui.css("w=Full align=AEnd")

///|
/// The ✕ on it: the page's colour on the ink's.
fn corner_remove_mark(c : @ui.Ctx) -> Unit {
  icon(c, "close", size=card_close_icon, color=theme().p.canvas) |> ignore
}

///|
/// A ✕ hung on a corner as with_corner_remove hangs it, drawn and nothing more (its box; where it goes is the caller's:
/// its top right as far past the corner's top and right edge as corner_remove_reach): a quote sent leaves with its ✕
/// as it sets off from the composer (sfbase's flight.mbt).
pub fn corner_remove_face(c : @ui.Ctx) -> Int {
  c.box(style=corner_remove_box, fn() { corner_remove_mark(c) })
}

///|
// kept across runs: a value (no field of it changes)
let corner_remove_box : @ui.Style = @ui.style(
  w=Fixed(corner_remove_side),
  h=Fixed(corner_remove_side),
  radius=Full,
  bg=Fg,
  align=ACenter,
  justify=JCenter,
)

///|
/// A card's own button at its end (fileCardRemove): 22 round, nothing under it but under the pointer (the hover
/// ground), its icon in the muted ink (the text's under the pointer); named.
fn card_button(c : @ui.Ctx, id : Int, icon_name : String, label : String) -> Unit {
  let p = theme().p
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
/// What a message carries is rounded as every card in a chat is (a question's, a screen's with its picture, pictures,
/// videos, pasted text): the ladder's card step (26). One a row high (a file's card, a screen's or a service's
/// without a picture) is a capsule (card_box).
pub let message_file_corner : Double = card_corner

///|
pub let message_file_radius : @ui.Radius = rounded(message_file_corner)

///|
/// A file's card at its widest (fileCard: 236).
pub let file_card_w : Double = 236.0

///|
/// A file's card's width in a message (card_box: as wide as what it says): its sheet and its name or its size, the
/// wider, with its room round them; file_card_w at most.
pub fn file_card_across(c : @ui.Ctx, name : String, size : Double) -> Double {
  let words = dmax(
    @ui.text_advance(name, size=c.text_size(Ui).0),
    @ui.text_advance(file_size(size), size=c.text_size(Caption).0),
  )
  let room = @ui.Space::px(S1_25) + tile_w + @ui.Space::px(S2_5) + @ui.Space::px(S1_5)
  dmin(file_card_w, (room + words).ceil())
}

///|
let card_button_icon : Double = 13.0

///|
let card_close_icon : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let card_box : @ui.Style = @ui.style(
  row=true,
  max_w=Fixed(file_card_w),
  // (a row high, a capsule, 48: its sheet's ink as far from its end as from its top and foot, 7 (the sheet's own 2
  // drawn in it), its words' end as far from the other, as its width comes to the pixel: file_card_across)
  pl=S1_25,
  pr=S1_5,
  py=S1_5,
  gap=S2_5,
  bg=Neutral,
  // (in a corner of what holds it, a composer's box: as far in as from its edges, its corner concentric)
  radius=InnerOr(Full),
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
/// What waits in the composer (a file's card, a quote) stands off its frosted ground by its own ground alone, no shadow
/// (the user, 2026-10-16: 附件有点难以分辨; 2026-10-25: 背景色好分辨就行了，不用这么深阴影): the capsule whiter than its
/// paper, the neutral one; in the dark a step up (the text at 10% over what floats). One named by its path keeps
/// card_named's: no ground, outlined.
pub fn composer_card() -> @ui.Style {
  composer_card_ground
}

///|
// kept across runs: a value (no field of it changes)
let composer_card_ground : @ui.Style = @ui.css("bg=Neutral dark{bg=Over(Raised, A(Fg, O10))}")

///|
/// A file's card waiting in the composer: as tall as a picture's tile beside it (56), its words on its middle, and its
/// sheet's ink as far from its side as from its top and foot, its words' end as far from the other side, as the web's
/// composer card does (14 round its sheet in its 64). Its 56 leaves 11 over and under the sheet's ink (10 and the
/// sheet's 1): 12 at its sides, the scale's nearest (10 and the sheet's 2; 12 at its end, rule 4's as far in from
/// both). At 7 in it stood 9 in, 2 short of over and under it (the user, 2026-10-30: 距离左边太近了); 8 over and under.
// kept across runs: a value (no field of it changes)
let card_waiting : @ui.Style = @ui.css("h=S14 pl=S2_5 pr=S3 py=S2")

///|
fn card_composer() -> @ui.Style {
  card_box.then(card_waiting).then(card_composer_corner())
}

///|
/// Round as what waits in the composer is (composer_inner): the first in its corner concentric with it, all alike.
fn card_composer_corner() -> @ui.Style {
  @ui.style(radius=composer_inner_radius())
}

///|
// kept across runs: a value (no field of it changes)
let card_open : @ui.Style = @ui.css("hovered{bg=Hover}")

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
let card_words_hug : @ui.Style = @ui.style(w=Cut)

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
/// What was done with a quote's card this frame: its source pressed (`jump`), its ✕ pressed; and the card's own box
/// (its ground: what a quote sent flies from and to, sfbase's flight.mbt).
pub(all) struct QuoteCardDone {
  jumped : Bool
  removed : Bool
  card : Int
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
  let pin = pin_of(author, role)
  if jump {
    tip(c, key + "/jump-tip", source, t("web-main.quote.jump"))
  } else if pin != "" {
    tip(c, key + "/pin-tip", source, words)
  }
  let hot = jump && c.lit(source)
  // (waiting in the composer, its ✕ hung on its corner as everything's there: with_corner_remove)
  let hung = composer && remove
  let node = Ref::new(-1)
  let card = fn() {
    node.val = c.box(style=if composer { quote_box_composer().then(composer_card()) } else { quote_box_message }, fn() {
    // (a pin in its top corner: there the ladder's inset from both its edges, concentric with it)
    let source_look = match (composer, pin != "") {
      (true, false) => if hung { quote_source_hung } else { quote_source_composer }
      (true, true) => if hung { quote_source_hung_pin } else { quote_source_composer_pin }
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
          c.box(style=if composer { quote_comment_composer } else { quote_comment }, fn() {
            c.text(comment, style=quote_said) |> ignore
          })
          |> ignore
        }
    }
    if remove && !hung {
      c.layer(fn() {
        c.box(style=quote_remove_at, fn() {
          card_button(c, x, "close", t("web-main.quote.remove"))
        })
        |> ignore
      })
      |> ignore
    }
  })
  }
  let removed = if hung {
    with_corner_remove(c, key, t("web-main.quote.remove"), composer_inner(), card)
  } else {
    card()
    remove && c.clicked(x)
  }
  { jumped: jump && c.clicked(source), removed, card: node.val }
}

///|
/// A mark on a previewed page or an image (`role`): its pin's number, the digits `author` ends with; "" for any other
/// quote.
fn pin_of(author : String, role : String) -> String {
  if role != "page" && role != "image" {
    return ""
  }
  let digits = StringBuilder::new()
  for ch in author.rev_iter() {
    if ch >= '0' && ch <= '9' {
      digits.write_char(ch)
    } else {
      break
    }
  }
  digits.to_string().rev()
}

///|
/// How much further in from its card's corner a quote's words are in the composer than in a message, across and down
/// (quote_source_composer's padding and quote_source's; a pin as far in in both): sent, its card in the message sets
/// out from its card in the composer by as much, so that its words set out from where they were.
pub fn quote_sent_shift(author : String, role : String) -> (Double, Double) {
  if pin_of(author, role) != "" {
    (0.0, 0.0)
  } else {
    (quote_in_composer.px() - (quote_card_in + quote_in), quote_over_composer - quote_card_in)
  }
}

///|
/// A quote's mark (11, the accent's) in a box as tall as its line.
let quote_icon : Double = 11.0

///|
/// quoteCard: a bubble's corner in a message (quote_box_message), in the composer its inner corner; the text at 4% over
/// the canvas.
// kept across runs: a value (no field of it changes)
let quote_box : @ui.Style = @ui.style(w=Full, radius=rounded(quote_corner), bg=Over(Bg, faint_ground), clip=true)

///|
/// In a message, as a message's bubble (sfpages message.mbt bubble: Xl2, its words 14 across and 8 over and under):
/// what it holds the bubble's 8 in from its edges (its picture there, concentric with it), 6 apart; its words as far
/// in across as a bubble's.
// kept across runs: a value (no field of it changes)
let quote_box_message : @ui.Style = quote_box.then(@ui.style(p=room(quote_card_in), gap=S1_5))

///|
let quote_card_in : Double = 8.0

///|
/// A quote's corner in a message: a message's bubble's.
let quote_corner : Double = radii.xl2

///|
fn quote_box_composer() -> @ui.Style {
  quote_box.then(@ui.style(radius=composer_inner_radius()))
}

///|
/// What sits in the composer's corners is rounded concentric with it, its padding in (composer_corner: alone a card's,
/// so the ladder's next step, a row's; at the tape's foot 24.8, so 16.8): what waits in it (a quote, a file's card, a
/// picture), every one alike.
pub fn composer_inner() -> Double {
  @ui.concentric(composer_corner(), composer_pad)
}

///|
/// The composer's box's corner as a style's (composer_corner).
pub fn composer_radius() -> @ui.Radius {
  rounded(composer_corner())
}

///|
pub fn composer_inner_radius() -> @ui.Radius {
  rounded(composer_inner())
}

///|
/// The composer's padding: the ladder's inset, so what stands in its corners has the ladder's next corner (a quote's,
/// a file's; its round controls round there: the computer's 32 and the phone's 36 alike).
pub let composer_pad : Double = corner_inset

///|
/// How much short of the box's padding the files over a composer's words end their lines: the rest of its top corner
/// past the padding (composer_corner less composer_pad). What wraps there ends where it lands, so the last of the first
/// line would otherwise stand in that corner at some widths, neither concentric with it nor out of it (the corner
/// rule); kept out of it, it is out at every width.
pub fn composer_files_end() -> Double {
  composer_corner() - composer_pad
}

///|
/// Its words in a message: a bubble's 14 in from its edge, its card's padding over and under them (in the composer 9
/// over, 16 at its start, 34 at its end for its ✕).
// kept across runs: a value (no field of it changes)
let quote_source : @ui.Style = @ui.style(w=Full, px=room(quote_in))

///|
/// A quote card's words in a message further in across than its card's padding, to a bubble's 14 (none further
/// over); in the composer 16 in, 34 at its end, 9 over; what is said 3 under the words, 10 under it there.
let quote_in : Double = 14.0 - quote_card_in

///|
let quote_end_composer : Double = 34.0

///|
let quote_in_composer : @ui.Space = S4

///|
let quote_over_composer : Double = 9.0

///|
let quote_said_over : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let quote_source_composer : @ui.Style = @ui.style(
  w=Full,
  pl=quote_in_composer,
  pr=room(quote_end_composer),
  pt=room(quote_over_composer),
)

///|
/// How far from a quote's top and start its pin (a capsule quote_pin_h high) stands, concentric with its corner
/// (capsule_in); in the composer, with a row's.
let quote_pin_in : Double = capsule_in(quote_corner, quote_pin_h)

///|
let quote_pin_in_composer : Double = capsule_in(row_corner, quote_pin_h)

///|
let quote_pin_h : Double = 16.0

///|
/// A page mark's quote: its pin (a capsule 16 high) as far from its top and start as makes it concentric with its
/// corner (quote_pin_in).
// kept across runs: a value (no field of it changes)
let quote_source_pin : @ui.Style = quote_source.then(
  @ui.style(pl=room(quote_pin_in - quote_card_in), pt=room(quote_pin_in - quote_card_in)),
)

///|
// kept across runs: a value (no field of it changes)
let quote_source_composer_pin : @ui.Style = quote_source_composer.then(
  @ui.style(pl=room(quote_pin_in_composer), pt=room(quote_pin_in_composer)),
)

///|
/// With its ✕ hung on its corner (with_corner_remove), nothing kept at its end for it: its words as far in at its end
/// as at its start.
// kept across runs: a value (no field of it changes)
let quote_source_hung : @ui.Style = quote_source_composer.then(@ui.css("pr=S4"))

///|
// kept across runs: a value (no field of it changes)
let quote_source_hung_pin : @ui.Style = quote_source_hung.then(
  @ui.style(pl=room(quote_pin_in_composer), pt=room(quote_pin_in_composer)),
)

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
/// Its picture in a message: at its card's padding (in the composer 6 over it, 16 in).
// kept across runs: a value (no field of it changes)
let quote_picture : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let quote_picture_composer : @ui.Style = @ui.css("row px=S4 pt=S1_5")

///|
/// quoteCardComment: 3 over, 16 in, 10 under it in the composer; in a message's, as far in as its words.
// kept across runs: a value (no field of it changes)
let quote_comment : @ui.Style = @ui.style(w=Full, px=room(quote_in))

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
