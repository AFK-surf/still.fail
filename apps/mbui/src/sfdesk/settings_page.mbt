// What the desktop's settings pages not moved to sfpages yet share beside the library's page (src/sf page.mbt): a
// place's page across the pane, a list's filter, a dialog, a page still laid out wide alone (desk_page). The pieces of
// one arrangement they still draw themselves (desk_card, desk_list, narrow_row, …: the library's, and
// sfpages' settings_page.mbt) are counted by detlint's page-look in the pages, each file's only falling.

///|
/// The pieces the settings' pages moved to sfpages draw with (sfpages settings_page.mbt), these pages' too.
using @sfpages {
  look_of,
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
