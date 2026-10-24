// What the app's own doings (links opened, notifications, the dock, the system's say) ask of the pages drawn: what is
// over them (sheets, menus) and how an invitation shows are theirs, said as they are drawn (src/sfapp pages_shell).

///|
pub(all) struct Shell {
  /// back to the stack's root (Home), what is over the pages put down
  home : () -> Unit
  /// what is over the pages put down as a page opens from a link (a sheet, a menu)
  close_overlays : () -> Unit
  /// an invitation's link opened: what it leads to shown, before it is accepted (its token)
  open_invite : (String) -> Unit
  /// the app gone behind, between frames (what lives only while it is shown let go)
  behind : (Source) -> Unit
  /// a page opened where the layout has it (docs/architecture.md, the pane table): what pages, links and the app's
  /// own doings call (open), never the stack themselves
  open : (Page) -> Unit
  /// a detail of a chat opened where the layout has it (an agent's history by its key, jobs, letters, files, a
  /// service: the side panel's tabs on the wide frame, toggled): what a page asks of its chat (open_detail)
  detail : (Source, ChatRef, String) -> Unit
}

///|
/// The stack's own, until the pages say theirs (as they are first drawn): a page pushed, a new chat risen from the
/// foot; a detail nowhere.
pub fn bare_shell() -> Shell {
  {
    home: nav_home,
    close_overlays: fn() { app.menu = false },
    open_invite: fn(_) {  },
    behind: fn(_) {  },
    open: stack_open,
    detail: fn(_, _, _) {  },
  }
}

///|
/// Page `p` opened on the stack (a phone's way): pushed, a new chat risen from the foot (App.kt: the new chat slides
/// up).
pub fn stack_open(p : Page) -> Unit {
  match p {
    NewChat => app.nav.rise(NewChat)
    _ => app.nav.push(p)
  }
}


///|
/// Chat `r`'s detail `tab` opened, where the layout has it (Shell's `detail`).
pub fn open_detail(src : Source, r : ChatRef, tab : String) -> Unit {
  (shell.val.detail)(src, r, tab)
}

///|
/// The pages' last drawn.
pub let shell : Ref[Shell] = Ref(bare_shell())
