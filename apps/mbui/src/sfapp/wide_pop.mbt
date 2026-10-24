// What opens over the wide frame: the frame's own (sfdesk's overlays.mbt), ⌘K's switcher and ⌘/'s shortcuts over a
// scrim.

///|
/// Everything open over the wide frame, drawn after it.
fn wide_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // the menus and 待处理's panel (sfdesk/overlays.mbt)
  @sfdesk.overlays(c, src, w, desk_pages())
  // ⌘K (sfdesk/switcher.mbt): what the frame can do now offered to it, and where it opens a chat found
  @sfdesk.switcher(c, src, w.id, switcher_offered(c, src), {
    chat: fn(item) { @sfdesk.open_row(desk_pages(), item) },
    message: fn(r, seq, words) { open_chat_found(r, seq, words) },
  })
  keys_dialog(c, src)
}

