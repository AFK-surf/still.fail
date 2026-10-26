// What the desktop's settings pages not moved to sfpages yet share beside the library's page (src/sf page.mbt): a
// place's page across the pane, a list's filter, a dialog, a page still laid out wide alone (desk_page). The pieces of
// one arrangement they still draw themselves (desk_card, desk_list, narrow_row, …: the library's, named here, and
// sfpages' settings_page.mbt) are counted by detlint's page-look in the pages, each file's only falling.

using @sf {
  type Look,
  desk_lanes,
  desk_lane,
  desk_lane_column,
  desk_lane_most,
  desk_lane_in,
  desk_column_most,
  desk_column_in,
  desk_own_head,
  desk_hint_box,
  desk_hint_words,
  desk_card,
  desk_card_row,
  desk_card_text,
  desk_strong,
  desk_words,
  desk_muted,
  desk_row_least,
  desk_chevron,
  desk_mark,
  desk_list,
  desk_list_out,
  desk_list_link,
  desk_list_text,
  desk_named,
  desk_list_title,
  desk_note_line,
  desk_note_bad,
}

///|
/// The pieces the settings' pages moved to sfpages draw with (sfpages settings_page.mbt), these pages' too.
using @sfpages {
  desk_list_row,
  desk_note,
  desk_column,
  desk_said_line,
  look_of,
  narrow_note,
  finger_ripple,
  narrow_row,
  narrow_row_title,
  waiting_cards,
}

///|
/// What the option chosen above it does (chat.css.ts appearanceHint: 8 under it, the meta's 12 muted, 52em at most).
fn desk_hint(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=desk_hint_box, fn() { c.text(words, style=desk_hint_words) |> ignore }) |> ignore
}

///|
/// A choice of a few (Segmented) as wide as its options, at the column's start.
fn desk_choice(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=desk_choice_row, fn() { body() }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_choice_row : @ui.Style = @ui.css("row w=Full")


///|
/// A page of the desktop's settings still drawn with its desktop pieces alone: the library's page laid out wide (counted
/// by page-look where a page asks for it), back over it on a page under another (`back` where it goes; `on_back`, else
/// the page popped).
fn desk_page(
  c : @ui.Ctx,
  core : Core,
  key : String,
  title : String,
  content : Array[() -> Unit],
  about? : String = "",
  lead? : String = "",
  back? : String = @sf.t("android-settings.title"),
  actions? : () -> Unit,
  head? : () -> Unit,
  on_back? : () -> Unit,
  deep? : Bool = settings_deep.val,
) -> Unit {
  let deep = deep || on_back is Some(_)
  let go = match on_back {
    Some(f) => f
    None => core.pop
  }
  let frame = { ..@sf.no_frame, back: if deep { Some(back) } else { None } }
  @sf.page_wide(c, key, title, content, on_back=go, frame~, lead~, about~, actions?, head?)
}

// ── one arrangement's pieces, as pages still draw them ──────────────────

///|
let narrow_most : Double = @sf.narrow_most

///|
// kept across runs: a value (no field of it changes)
let narrow_lead_box : @ui.Style = @sf.pg_lead_box

///|
// kept across runs: a value (no field of it changes)
let narrow_lead : @ui.TextStyle = @sf.pg_lead

///|
// kept across runs: a value (no field of it changes)
let narrow_card_room : @ui.Style = @sf.pg_card_room

///|
// kept across runs: a value (no field of it changes)
let narrow_said_row : @ui.Style = @sf.pg_said_row

///|
// kept across runs: a value (no field of it changes)
let narrow_row_words : @ui.Style = @sf.pg_row_words

///|
// kept across runs: a value (no field of it changes)
let narrow_value : @ui.TextStyle = @sf.pg_value

///|
// kept across runs: a value (no field of it changes)
let narrow_link_note : @ui.TextStyle = @sf.pg_link_note

///|
// kept across runs: a value (no field of it changes)
let wide_heading : @ui.TextStyle = @sf.wide_heading

///|
// kept across runs: a value (no field of it changes)
let wide_value : @ui.TextStyle = @sf.wide_value
