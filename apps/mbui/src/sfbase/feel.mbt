// What the app's person feels of what goes on beyond their own hand (@ui.haptic; the prefs' `haptics` turn them all
// off: app_frame.mbt): something on screen coming to be, with the app in front (felt_change), as a chat open coming to
// need them (feel_needed). What their hand does is felt where it is done (a hold, a card answered, what is sent or
// copied).

///|
/// What each thing felt as it changes was last seen to be (felt_change), by its key, and on which of its page's stints
/// (Ctx::page_stint): none until it is first seen.
let felt_seen : Map[String, (Bool, Int)] = {}

///|
/// As at the start (the app's reset).
fn felt_reset() -> Unit {
  felt_seen.clear()
}

///|
/// `kind` felt as what `key` names comes to be (`now`, after it was seen not to be on the same stint of its page), with
/// the app in front; not as it is first seen, nor while it stays, nor as its page is come back to with it so. Once the
/// frame's builds are over, whichever of them saw it.
pub fn felt_change(c : @ui.Ctx, key : String, now : Bool, kind : @ui.Haptic) -> Unit {
  let stint = c.page_stint()
  c.after_build("haptic/change/" + key, fn() {
    if now && felt_seen.get(key) == Some((false, stint)) && app_in_front() {
      @ui.haptic(kind)
    }
    felt_seen[key] = (now, stint)
  })
}

///|
/// The chat open as `v` coming to need the viewer (a card waiting for them, `asks`, or its agent saying it needs them:
/// the state's `need`), felt as something done.
pub fn feel_needed(c : @ui.Ctx, r : ChatRef, v : ChatView) -> Unit {
  let needs = v.asks.length() > 0 ||
    (match v.state {
      Some((_, lead, _)) => lead == "need"
      None => false
    })
  felt_change(c, "needed/" + r.station + "/" + r.session, needs, Confirm)
}
