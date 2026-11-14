// What the app's person feels of what goes on beyond their own hand (@ui.haptic; the prefs' `haptics` turn them all
// off: app_frame.mbt): something on screen coming to be, with the app in front (felt_change), as a chat open coming to
// need them (feel_needed). What their hand does is felt where it is done (a hold, a card answered, what is sent or
// copied).

///|
/// What each thing felt as it changes was last seen to be (felt_change), by its key, and on which of its page's stints
/// (Ctx::page_stint): none until it is first seen.
let felt_seen : Map[String, (Bool, Int)] = Map([])

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
/// `kind` felt as what `now` says comes to be while node `v` is there (felt_change's, of a part made once): after it
/// was seen not to be, with the app in front; not as it is first seen, nor while it stays.
pub fn felt_change_node(v : @view.View, now : () -> Bool, kind : @ui.Haptic) -> Unit {
  // (as of its changes alone: turning true is coming to be after it was not, never what it is as it is first seen)
  v.reacts(now, fn(holds) { if holds && app_in_front() { @ui.haptic(kind) } }, at_start=false)
}

///|
/// The chat open as `v` coming to need the viewer (a card waiting for them, `asks`, or its agent saying it needs them:
/// the state's `need`), felt as something done.
pub fn feel_needed(c : @ui.Ctx, r : ChatRef, v : ChatView) -> Unit {
  felt_change(c, "needed/" + r.station + "/" + r.session, chat_needs(v), Confirm)
}

///|
/// feel_needed's where chat `r`'s page is made as nodes (chat_page_made's, chat_page_nodes on), in node `n`: its view
/// as source `src` reads it. Till the view is read nothing is seen of it: what it first comes to is seen, not felt, as
/// feel_needed sees the view first read (a chat opened while it needs its viewer is no change; felt as it came on
/// opening it till 2026-11-15).
fn feel_needed_node(n : @view.View, src : Source, r : ChatRef) -> Unit {
  let seen : Ref[Bool?] = Ref(None)
  n.reacts(fn() { view_of_chat(src, r).0.map(chat_needs) }, fn(now) {
    guard now is Some(needs) else { return }
    if needs && seen.val is Some(false) && app_in_front() {
      @ui.haptic(Confirm)
    }
    seen.val = now
  })
}

///|
/// Whether chat `v` needs its viewer: a card waits for them, or its agent says it needs them.
fn chat_needs(v : ChatView) -> Bool {
  v.asks.length() > 0 ||
  (match v.state {
    Some((_, lead, _)) => lead == "need"
    None => false
  })
}
