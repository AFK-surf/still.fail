// How a thing answers the hand (docs/architecture.md: the input only says how a thing answers it, never what is shown
// where): what a pointer over a thing shows, a press's ripple, a menu held. The pages ask these, never @ui.pointing().

///|
/// What a pointer over a thing shows (a row's time, its ✕, a dismiss): while `pointed` (it is pointed at, or what it
/// belongs to is), and always to a finger, which hovers over nothing.
pub fn pointed_or_finger(pointed : Bool) -> Bool {
  pointed || @ui.pointing() is Finger
}

///|
/// A press on `id` rippling from where a finger pressed it, its corner `corner` (a mouse's press shows as its ground).
pub fn press_ripple(c : @ui.Ctx, id : Int, corner : Double) -> Unit {
  if @ui.pointing() is Finger {
    @motion.ripple(c, id, corner)
  }
}

///|
/// A menu asked by a hold (`key`: what it is of): with a finger the press is the menu's (lifting it opens nothing)
/// and it is felt as it opens, once for the press. Whether a finger held it (its menu from what was held, not at a
/// pointer).
pub fn menu_held(c : @ui.Ctx, key : String) -> Bool {
  if !(@ui.pointing() is Finger) {
    return false
  }
  c.take_press()
  let at = c.press().frame
  if held_felt.get(key) != Some(at) {
    held_felt[key] = at
    c.after_build("haptic/hold/" + key, fn() { @ui.haptic(LongPress) })
  }
  true
}

///|
/// The press each menu held was last felt for (menu_held), by what it is of.
// kept across runs: let go as the app begins anew (parts_reset)
let held_felt : Map[String, Int] = {}
