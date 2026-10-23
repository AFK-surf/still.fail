// A settings page on the desktop as the web's frames one (ember web/src/styles/pages.css.ts page, pageNarrow,
// pageHead; brand.css.ts: the narrow page's column): its head, then what it holds in the 760 column in the pane's
// middle, 28 under the head, 80 room at its foot. The pages ported from the web's onto the library's parts
// (web_notifications.mbt, …) are laid out in it; their words in the library's true sizes (home.mbt `page`: no wide
// scale over them).

///|
/// `title`'s page holding `content`, a block at a time (each laid out as it comes into view), `about` what it is for
/// said by a mark beside its title, or `lead` under it.
fn desk_page(
  c : @ui.Ctx,
  core : Core,
  key : String,
  title : String,
  content : Array[() -> Unit],
  about? : String = "",
  lead? : String = "",
  back? : String = tr("android-settings.title"),
) -> Unit {
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, back) },
    fn() { large_title(c, title, about~, says=lead) },
  ]
  for i, b in content {
    blocks.push(fn() { c.box(style=if i == 0 { desk_first } else { desk_block }, fn() { b() }) |> ignore })
  }
  scroll_page(c, key, blocks)
}

///|
/// How wide the page's column is (pageNarrow: 760 at most), for what is drawn to its width before it is laid out.
fn desk_column(c : @ui.Ctx) -> Double {
  dmin(desk_column_most, c.width - 2.0 * wide_side(c) - 2.0 * desk_column_in)
}

///|
let desk_column_most : Double = 760.0

///|
let desk_column_in : Double = 16.0

///|
/// A block of the page, at the column's edges; the first 28 under the head (its own 12 and these 16).
// kept across runs: a value (no field of it changes)
let desk_block : @ui.Style = @ui.style(w=Full, px=S4)

///|
// kept across runs: a value (no field of it changes)
let desk_first : @ui.Style = desk_block.then(@ui.style(pt=S4))

///|
/// What the option chosen above it does (chat.css.ts appearanceHint: 8 under it, the meta's 12 muted, 52em at most).
fn desk_hint(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=desk_hint_box, fn() { c.text(words, style=desk_hint_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_hint_box : @ui.Style = @ui.style(w=Full, max_w=Fixed(desk_hint_most), pt=S2)

///|
let desk_hint_most : Double = 624.0

///|
// kept across runs: a value (no field of it changes)
let desk_hint_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
/// A hint and its link in a line (8 under what is over it).
// kept across runs: a value (no field of it changes)
let desk_hint_line : @ui.Style = @ui.style(w=Full, pt=S2, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let desk_said_line : @ui.Style = @ui.style(row=true, w=Full, align=ACenter)

///|
/// A card of words (pages.css.ts card: 20 in, its rows 14 apart, the settings' corner on the card's ground; a row of
/// it: cardRow, 12 apart in its middle; its words cardRowText, 2 apart, the ui's 13 on 20, the title in 600).
// kept across runs: a value (no field of it changes)
let desk_card : @ui.Style = @ui.style(w=Full, p=S5, gap=S3_5, radius=Xl3, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let desk_card_row : @ui.Style = @ui.style(row=true, w=Full, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_card_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let desk_strong : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_muted : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
/// A list (pages.css.ts list, listRow: reaching 12 past the column, its rows 2 apart, each 52 high at least, 10 by 12 in,
/// 12 apart, the field's corner; one that opens on the list's ground under the pointer; its title in 500, what is under
/// it the meta's 12 muted, red where it is wrong; a station's mark before its name, 6 apart; a chevron 16).
let desk_row_least : Double = 52.0

///|
let desk_chevron : Double = 16.0

///|
let desk_mark : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let desk_list : @ui.Style = @sf.outset(desk_list_out).then(@ui.style(gap=S0_5))

///|
let desk_list_out : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=Fixed(desk_row_least),
  px=S3,
  py=S2_5,
  gap=S3,
  align=ACenter,
  radius=Xl,
)

///|
// kept across runs: a value (no field of it changes)
let desk_list_link : @ui.Style = desk_list_row.then(@ui.style(hovered=@ui.patch(bg=Hover)))

///|
// kept across runs: a value (no field of it changes)
let desk_list_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let desk_named : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_list_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_note_bad : @ui.TextStyle = desk_note.then(@ui.text_style(color=Danger))

///|
/// A choice of a few (Segmented) as wide as its options, at the column's start.
fn desk_choice(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=desk_choice_row, fn() { body() }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_choice_row : @ui.Style = @ui.style(row=true, w=Full)
