// A workspace where it is switched to (the web's WorkspaceMark.tsx): the mark its managers gave it (an icon of
// still.fail's, a picture or an emoji, as a station's), else its first letter; and what is said beside it: an
// invitation waiting (workspace.css.ts inviteDot). Where it goes and how large is its place's (the rail's squares, the
// workspaces' rows, Home's name).

///|
/// Whether the workspace has a mark of its own (else its letter is shown).
pub fn workspace_marked(w : Workspace) -> Bool {
  @sf.has_station_mark(w.emoji, w.icon)
}

///|
/// Its mark `size` across in `ink`, else its first letter in `letter`. `still`: a GIF holds its first frame (a workspace
/// listed beside the one in use: only that one's moves).
pub fn workspace_mark(
  c : @ui.Ctx,
  w : Workspace,
  size : Double,
  ink : Int64,
  letter : @ui.TextStyle,
  still? : Bool = false,
) -> Unit {
  if workspace_marked(w) {
    @sf.station_mark(c, w.emoji, w.icon, size, ink, still~)
  } else {
    c.text(@sf.initial(w.name), style=letter) |> ignore
  }
}

///|
/// An invitation waiting (inviteDot): the viewer's turn, so the chats' blue dot (chat_mark.mbt), 8 across; said as
/// `label`.
pub fn invite_dot(c : @ui.Ctx, label : String) -> Unit {
  c.box(style=invite_dot_look, label~, fn() {  }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let invite_dot_look : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_blue)
