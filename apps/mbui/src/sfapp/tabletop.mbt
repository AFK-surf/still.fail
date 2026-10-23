// A chat on a device half open on its back half (a laptop's pose, Android's tabletop: @ui.system_tabletop, the hinge
// partly open and its fold across the view, as the system says them): what is read over the fold, what is touched
// under it. Its messages end over the fold (all that keeps clear of the composer keeps clear of the fold and what is
// under it: chat_foot_room); under the fold its composer, and under that the latest chats, one tap to another (the
// latest chats' button not over the page then). The keyboard up, the composer rides on it, the chats under it out of
// the way. The page across the window whatever the size classes (not the wide frame: wide.mbt is_touch_wide); open
// flat, upright as a book, or closed, it is as on any screen.

///|
/// What a page keeps clear at its foot (over the navigation bar) on a device half open: the fold and all under it. 0
/// otherwise.
fn tabletop_clear(c : @ui.Ctx) -> Double {
  match @ui.system_tabletop() {
    Some((top, _)) => dmax(0.0, c.height - nav_foot() - top)
    None => 0.0
  }
}

///|
/// What a chat keeps clear at its page's foot (over the navigation bar) for its composer (composer_room_for), and on a
/// device half open for the fold and all under it.
fn chat_foot_room(c : @ui.Ctx, r : ChatRef, v : ChatView?) -> Double {
  dmax(composer_room_for(c, draft_key(r), v), tabletop_clear(c))
}

///|
/// A chat's page's foot, over the messages: the composer over the navigation bar; on a device half open the composer
/// at the top of the half under the fold (as far down as the keyboard, up, leaves it room) and the latest chats under
/// it.
fn chat_foot(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?) -> Unit {
  match @ui.system_tabletop() {
    Some((_, foot)) => {
      let room = composer_own_room(c, draft_key(r), v)
      bar_room_box(c, dmax(0.0, dmin(foot, c.height - nav_foot() - room)))
      composer(c, src, r, v)
      c.box(style=tabletop_recent, fn() { recent_list(c, src, w, app.nav.top()) }) |> ignore
    }
    None => {
      c.spacer()
      composer(c, src, r, v, beside=corners_on.val)
    }
  }
  // over the navigation bar (a layer goes on under the page's padding)
  bar_room_box(c, nav_foot())
}

///|
/// Under a chat's composer on a device half open: the latest chats, as much of them as the half has room for.
// kept across runs: a value (no field of it changes)
let tabletop_recent : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)
