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
  desk_list_text,
  desk_named,
  desk_list_title,
  desk_note_bad,
}


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
/// What a page shows while it is read the first time (the library's Waiting): `sample`, what it will show of made-up
/// words, in its bones; what could not be read over it in red (`error`, and the core's `wait`'s failing: a list's
/// stations not read yet), the bones then still.
pub fn block_waiting(c : @ui.Ctx, sample : () -> Unit, error? : String = "", wait? : Json? = None) -> Unit {
  let failing = failing_of(wait)
  @sf.waiting(c, sample, error~, note={ reading: failing.length() == 0, text: "", failing })
}

///|
/// A workspace's stations made up (the `stations` topic's), for what a page shows of them while they are read: three,
/// online, their names as long as a station's.
pub fn sample_stations() -> Array[Json] {
  [5, 3, 7].mapi(fn(i, n) {
    Json::object({
      "station": Json::string("sample/" + i.to_string()),
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(n)),
      "online": Json::boolean(true),
    })
  })
}

///|
/// How many dialogs were put up (a dialog's fields' keys, new each time it opens).
// kept across runs: counted by open_dialog; reset puts it back
pub let desk_dialogs : Ref[Int] = Ref(0)

///|
/// Puts up a dialog over the page (parts.tsx Dialog: the library's panel opened by nothing, @sf.panel): its title,
/// what it is about, what it holds, its buttons at its foot, each given what closes it; `wide`, 640 wide; `live`: its
/// title, its step's count and what it is about as they are now (a wizard's); `on_gone`: what is let go of as it closes
/// by its ✕, Esc or a press outside.
pub fn open_dialog(
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  foot : (@ui.Ctx, () -> Unit) -> Unit,
  description? : String = "",
  wide? : Bool = false,
  live? : () -> (String, String, String),
  on_gone? : () -> Unit = fn() {  },
  steps? : Bool = false,
  back? : () -> Unit,
) -> Unit {
  desk_dialogs.val += 1
  @sf.panel(title, body, from=Unanchored, description~, foot~, wide~, live?, gone=on_gone, steps~, back?)
}

// ── who a profile or a key is, at the head of its page (the web's Accounts.css.ts identity), and a card's foot ──

///|
/// A card's buttons at its foot (cardFoot).
// kept across runs: a value (no field of it changes)
pub let pf_card_foot : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// Who the account is (identity: its mark 48, its words beside it, 16 apart, 28 over what follows), where the page's
/// frame puts it (the page's own top is the frame's: desk_own_head).
// kept across runs: a value (no field of it changes)
pub let pf_head : @ui.Style = @ui.css("row w=Full pb=S7 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let pf_identity : @ui.Style = @ui.style(w=@sf.grow, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
pub let pf_mark : @ui.Style = @ui.css("w=S12 h=S12 radius=Lg bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
pub let pf_name : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
pub let pf_name_line : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
pub let pf_spin : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
pub let pf_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)
