// A chat on a device half open on its back half (a laptop's pose, Android's tabletop: @ui.system_tabletop, the hinge
// partly open and its fold across the view, as the system says them): what is read over the fold, what is touched
// under it. Its messages end over the fold (all that keeps clear of the composer keeps clear of the fold and what is
// under it: tabletop_clear_in); under the fold its composer, and under that the latest chats, one tap to another. The
// keyboard up, the composer rides on it, the chats under it out of the way. The page across the window whatever the size classes (laid out Small: @sf.layout); open flat, upright as
// a book, or closed, it is as on any screen.

///|
/// What a page keeps clear at its foot (over the navigation bar) on a device half open: the fold and all under it. 0
/// otherwise.
fn tabletop_clear(c : @ui.Ctx) -> Double {
  tabletop_clear_in(c.height, nav_foot())
}

///|
fn tabletop_clear_in(height : Double, foot : Double) -> Double {
  match @ui.system_tabletop() {
    Some((top, _)) => dmax(0.0, height - foot - top)
    None => 0.0
  }
}

///|
/// How many of the list's chats it has, and how many rows are shown in their bones while they are read.
let recent_chats_most : Int = 6

///|
let recent_sample : Int = 4

///|
// kept across runs: a value (no field of it changes)
let recent_empty : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let recent_rows : @ui.Style = @ui.css("w=Full px=S1_5")

///|
/// A chat's row: concentric with what it is in where that is rounded, a row's of the ladder's where it stands alone
/// (under the fold, on the page's ground).
// kept across runs: a value (no field of it changes)
let recent_row : @ui.Style = @ui.style(w=Full, radius=InnerOr(@sf.row_radius), clip=true)

///|
// kept across runs: a value (no field of it changes)
let recent_row_here : @ui.Style = recent_row.then(@ui.css("bg=AccentBg"))

///|
/// `p` in the place of the page on top, or over Home when it is alone (AppState.open), the sheets and the menu put
/// away.
fn open_in_place(p : Page) -> Unit {
  @sfbase.history_push()
  lower_sheet()
  app.menu = false
  if app.nav.depth() > 1 {
    app.nav.replace(p)
  } else {
    app.nav.push(p)
  }
}
