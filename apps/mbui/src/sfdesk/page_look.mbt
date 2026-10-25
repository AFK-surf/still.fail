// The settings pages' frame as the app gives it (sfbase's PageFrame: back, the room over and under, a place's bar)
// round the library's page (src/sf page.mbt: one page for every frame and input, laid out by its own width). The
// pieces of one arrangement a page still draws itself (narrow_*, desk_*: the library's, named here) are counted by
// detlint's page-look, each file's only falling.

using @sf {
  type Look,
}

///|
/// How the page being drawn is laid out, by the width of its box (a page still drawing one arrangement's pieces).
fn look_of(c : @ui.Ctx) -> @sf.Look {
  @sf.look_for(c.width)
}

///|
/// A page of the settings in the frame it is given (`frame`: back where there is somewhere to go back to, the room
/// over and under it, a place's bar naming it): the library's page (@sf.page), back popping it; in a panel of its own
/// on the tape, under a chat's bar there holding its title, back and what it does (pane_page.mbt).
fn look_page(
  c : @ui.Ctx,
  core : Core,
  frame : PageFrame,
  key : String,
  title : String,
  content : Array[() -> Unit],
  lead? : String = "",
  about? : String = "",
  actions? : () -> Unit,
  head? : () -> Unit,
  small? : String = "",
) -> Unit {
  let on_back = fn() { (core.pop)() }
  let page = fn(barred : Bool) {
    @sf.page(
      c,
      key,
      title,
      content,
      on_back,
      back?=frame.back,
      top=frame.top,
      foot=frame.foot,
      named=frame.named,
      named_actions=fn(f) { @settings.root_bar_actions.val = Some(f) },
      lead~,
      about~,
      actions?,
      head?,
      small~,
      barred~,
    )
  }
  if @sf.in_pane() {
    pane_page(c, frame.back.map(fn(label) { (label, on_back) }), title, about~, small~, actions?, head?, fn() { page(true) })
  } else {
    page(false)
  }
}

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
  top? : Double = 0.0,
  foot? : Double = 0.0,
) -> Unit {
  let deep = deep || on_back is Some(_)
  let go = match on_back {
    Some(f) => f
    None => fn() { (core.pop)() }
  }
  let back = if deep { Some(back) } else { None }
  let page = fn(barred : Bool) {
    @sf.page_wide(c, key, title, content, go, back?, top~, foot~, lead~, about~, actions?, head?, barred~)
  }
  // (in a panel of its own on the tape, under a chat's bar there: pane_page.mbt)
  if @sf.in_pane() {
    pane_page(c, back.map(fn(label) { (label, go) }), title, about~, actions?, head?, fn() { page(true) })
  } else {
    page(false)
  }
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
let narrow_note_box : @ui.Style = @sf.pg_note_box

///|
// kept across runs: a value (no field of it changes)
let narrow_note : @ui.TextStyle = @sf.pg_note

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
// kept across runs: a value (no field of it changes)
let narrow_said_row : @ui.Style = @sf.pg_said_row

///|
/// A finger's press rippling over a row (ListRow's, its corner concentric with its card's).
fn finger_ripple(c : @ui.Ctx, id : Int) -> Unit {
  @sf.row_ripple(c, id)
}

///|
// kept across runs: a value (no field of it changes)
let narrow_row : @ui.Style = @sf.pg_row

///|
// kept across runs: a value (no field of it changes)
let narrow_row_words : @ui.Style = @sf.pg_row_words

///|
// kept across runs: a value (no field of it changes)
let narrow_row_title : @ui.TextStyle = @sf.pg_row_title

///|
// kept across runs: a value (no field of it changes)
let narrow_value : @ui.TextStyle = @sf.pg_value

///|
let narrow_chevron : Double = @sf.pg_chevron

///|
// kept across runs: a value (no field of it changes)
let narrow_link_note : @ui.TextStyle = @sf.pg_link_note

///|
// kept across runs: a value (no field of it changes)
let wide_heading : @ui.TextStyle = @sf.wide_heading

///|
// kept across runs: a value (no field of it changes)
let wide_value : @ui.TextStyle = @sf.wide_value

///|
/// What back over a page says: the title of the page it goes back to.
pub fn back_label(p : Page) -> String {
  match p {
    Home => @sf.t("android-misc.bar.place.chats")
    Settings | Setting(Route::Home) => @sf.t("android-settings.title")
    Setting(Route::About) => @sf.t("web-pages.settings.nav.about")
    Setting(Route::Permissions) => @sf.t("web-pages.settings.nav.permissions")
    Setting(Route::Memories) => @sf.t("web-pages.settings.memory.title")
    Setting(Route::AutoDecisions) => @sf.t("web-pages.automaticDecisions.title")
    Setting(Route::Archiving) => @sf.t("web-pages.archiving.title")
    Setting(Route::Shortcuts) => @sf.t("web-main.shortcuts.title")
    Setting(Route::Usage) => @sf.t("web-pages.settings.nav.usage")
    Setting(Route::Security) => @sf.t("web-pages.security.title")
    Setting(Route::Vault) => @sf.t("web-pages.vault.title")
    Setting(Route::VaultItems) => @sf.t("web-pages.vault.all")
    Setting(Route::Connects(_)) | Place("connects") => @sf.t("android-settings.connects.title")
    Place("usage") => @sf.t("web-pages.settings.nav.usage")
    _ => @sf.t("common.back")
  }
}

///|
/// The shapes of a page's cards to come (the library's Waiting, its cards), in the page's room; what could not be read
/// over them in red.
fn waiting_cards(c : @ui.Ctx, count? : Int = 3, error? : String = "", failing? : Array[String] = []) -> Unit {
  @sf.waiting(c, shape=Cards, count~, error~, note={ reading: failing.length() == 0, text: "", failing })
}
