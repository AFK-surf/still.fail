// A chat on a device half open on its back half (a laptop's pose, Android's tabletop: @ui.system_tabletop, the hinge
// partly open and its fold across the view, as the system says them): what is read over the fold, what is touched
// under it. Its messages end over the fold (all that keeps clear of the composer keeps clear of the fold and what is
// under it: chat_foot_room); its composer, and the latest chats' button level with it, at the top of the half lying
// down, under the fold; the keyboard up and reaching higher than that leaves, they ride on it as on any screen. Open
// flat, upright as a book, or closed, the page is as it is anywhere.

///|
/// How far over the navigation bar a chat's composer sits on a device half open: its top at the fold's foot, as far as
/// the half under the fold holds it (`room`: the composer's own, composer_own_room). 0 otherwise.
fn tabletop_raise(c : @ui.Ctx, room : Double) -> Double {
  match @ui.system_tabletop() {
    Some((_, foot)) => dmax(0.0, c.height - nav_foot() - foot - room)
    None => 0.0
  }
}

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
