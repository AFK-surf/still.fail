// What the settings' pages share beside the library's page (src/sf page.mbt): one arrangement's pieces they still draw
// themselves (desk_list_title, narrow_row, …: the library's, named here), counted by detlint's page-look in the pages,
// each file's only falling. The desktop's settings pages not moved here yet take them by these names (sfdesk
// settings_page.mbt).

using @sf {
  type Look,
  desk_lane_most,
  desk_lane_in,
  desk_column_most,
  desk_column_in,
  desk_hint_words,
  desk_card_row,
  desk_card_text,
  desk_strong,
  desk_words,
  desk_muted,
  desk_chevron,
  desk_mark,
  desk_list_link,
  desk_list_text,
  desk_named,
  desk_list_title,
  desk_note_bad,
}

///|
// kept across runs: a value (no field of it changes)
pub let desk_list_row : @ui.Style = @sf.wide_list_row

///|
// kept across runs: a value (no field of it changes)
pub let desk_note : @ui.TextStyle = @sf.wide_list_note

///|
/// How wide the page's column is (pageNarrow: 760 at most), for what is drawn to its width before it is laid out.
pub fn desk_column(c : @ui.Ctx) -> Double {
  dmin(desk_column_most, dmin(c.width - 2.0 * desk_lane_in, desk_lane_most) - 2.0 * desk_column_in)
}

///|
/// A hint and its link in a line (8 under what is over it).
// kept across runs: a value (no field of it changes)
let desk_hint_line : @ui.Style = @ui.css("w=Full pt=S2 gap=S1")

///|
// kept across runs: a value (no field of it changes)
pub let desk_said_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// How the page being drawn is laid out, by the width of its box (a page still drawing one arrangement's pieces).
pub fn look_of(c : @ui.Ctx) -> @sf.Look {
  @sf.look_for(c.width)
}

///|
// kept across runs: a value (no field of it changes)
let narrow_note_box : @ui.Style = @sf.pg_note_box

///|
// kept across runs: a value (no field of it changes)
pub let narrow_note : @ui.TextStyle = @sf.pg_note

///|
// kept across runs: a value (no field of it changes)
let narrow_note_bad : @ui.TextStyle = @sf.pg_note_bad

///|
/// A note's words in a line, as wide as they are (a link after them).
// kept across runs: a value (no field of it changes)
let narrow_note_inline : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let desk_hint_inline : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A finger's press rippling over a row (ListRow's, its corner concentric with its card's).
pub fn finger_ripple(c : @ui.Ctx, id : Int) -> Unit {
  @sf.row_ripple(c, id)
}

///|
// kept across runs: a value (no field of it changes)
pub let narrow_row : @ui.Style = @sf.pg_row

///|
// kept across runs: a value (no field of it changes)
pub let narrow_row_title : @ui.TextStyle = @sf.pg_row_title

///|
let narrow_chevron : Double = @sf.pg_chevron

///|
/// The shapes of a page's cards to come (the library's Waiting, its cards), in the page's room; what could not be read
/// over them in red.
pub fn waiting_cards(c : @ui.Ctx, count? : Int = 3, error? : String = "", failing? : Array[String] = []) -> Unit {
  @sf.waiting(c, shape=Cards, count~, error~, note={ reading: failing.length() == 0, text: "", failing })
}
