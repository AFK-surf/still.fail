// What the app's person feels of what goes on beyond their own hand (@ui.haptic; the prefs' `haptics` turn them all
// off: app_frame.mbt): something on screen coming to be, with the app in front (felt_change), as a chat open coming to
// need them (feel_needed). What their hand does is felt where it is done (a hold, a card answered, what is sent or
// copied).

///|
/// What each thing felt as it changes was last seen to be (felt_change), by its key, and on which of its page's stints
/// (Ctx::page_stint): none until it is first seen.
let felt_seen : Map[String, (Bool, Int)] = {}

///|
/// What the last build saw of each (felt_change: its key, whether it is, its page's stint, how it is felt), and which
/// build that was.
let felt_now : Map[String, (Bool, Int, @ui.Haptic)] = {}

///|
let felt_build : Ref[Int] = Ref(-1)

///|
/// As at the start (the app's reset).
fn felt_reset() -> Unit {
  felt_seen.clear()
  felt_now.clear()
  felt_build.val = -1
}

///|
/// `kind` felt as what `key` names comes to be (`now`, after it was seen not to be on the same stint of its page), with
/// the app in front; not as it is first seen, nor while it stays, nor as its page is come back to with it so. Once the
/// frame's builds are over, what the last of them saw (felt_take): nothing told outside for it, so that what is felt
/// builds no frame after it, whatever chat is open and whichever builds see it.
pub fn felt_change(c : @ui.Ctx, key : String, now : Bool, kind : @ui.Haptic) -> Unit {
  if !felt_hooked.val {
    felt_hooked.val = true
    @ui.on_frame_built(fn(_) { felt_take() })
  }
  if felt_build.val != c.build_number() {
    felt_build.val = c.build_number()
    felt_now.clear()
  }
  felt_now[key] = (now, c.page_stint(), kind)
}

///|
/// Whether felt_take runs as each frame's builds are over (installed once in the process).
// kept across runs: installed once
let felt_hooked : Ref[Bool] = Ref(false)

///|
/// What the last build saw felt where it came to be, and kept as seen; let go once taken.
fn felt_take() -> Unit {
  felt_now.each(fn(key, seen) {
    let (now, stint, kind) = seen
    if now && felt_seen.get(key) == Some((false, stint)) && app_in_front() {
      @ui.haptic(kind)
    }
    felt_seen[key] = (now, stint)
  })
  felt_now.clear()
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
