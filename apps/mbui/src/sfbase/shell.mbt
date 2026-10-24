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
}

///|
/// The stack's own, until the pages say theirs (as they are first drawn).
pub fn bare_shell() -> Shell {
  { home: nav_home, close_overlays: fn() { app.menu = false }, open_invite: fn(_) {  }, behind: fn(_) {  } }
}

///|
/// The pages' last drawn.
pub let shell : Ref[Shell] = Ref(bare_shell())
