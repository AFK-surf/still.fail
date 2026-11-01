// How a thing answers the hand (docs/architecture.md: the input only says how a thing answers it, never what is shown
// where): what a pointer over a thing shows, a press's ripple, a menu held. The pages ask these, never @ui.pointing().

///|
/// Whether the hand rests over things (a mouse's pointer: its moves are seen, a press is a click, words are picked by
/// a drag) rather than on nothing (a finger: what a press does is what it presses; it is never over anything): what
/// an answer of the hand's turns on where the library has no part of its own for it. What is shown, where and how big
/// never asks it (detlint's page-hand).
pub fn pointer_rests() -> Bool {
  @ui.pointing() is Mouse
}

///|
/// What a pointer over a thing shows (a row's time, its ✕, a dismiss): while `pointed` (it is pointed at, or what it
/// belongs to is: Ctx::hand_lit, so a test's frame with all of it shown shows it), and always to a finger, which hovers
/// over nothing.
pub fn pointed_or_finger(c : @ui.Ctx, pointed : Bool) -> Bool {
  c.hand_lit(pointed) || @ui.pointing() is Finger
}

///|
/// Whether what a row's ⋯ would offer is had by holding the row, its ⋯ not drawn (touch's: the native input,
/// docs/architecture.md, what only a pointer's hover would show), else by its ⋯ under the pointer or a right click.
/// The same for either hand on one screen: the boxes never follow the hand (hand_layout_wbtest).
pub fn more_held() -> Bool {
  (native_input() is Finger)
}

///|
/// Whether this device types on a keyboard raised on asking and short of a computer's keys (Esc, Tab, the arrows, ⌘
/// held), and points with a finger resting on nothing (touch's: the native input, docs/architecture.md). What drives
/// another machine's screen from it makes up for both: a keyboard to raise, a keys row, a finger as a trackpad, its
/// tools under the thumb, and a page of the machine's browser laid out as this device's own browser would lay it out.
/// With keyboard and mouse none of that: the keyboard types into the screen as it is, the mouse is its pointer, and its
/// tools are the viewer bar's across the window's top (viewer_bar), as every full-window layer's are.
pub fn soft_keyboard() -> Bool {
  native_input() is Finger
}

///|
/// Whether Enter in a box of lines sends what is in it (⇧Enter a new line), as where the keyboard is at hand (the web's
/// `hover: hover`), or is a new line, as on the screen's keyboard (its send is the page's button): the native input's.
pub fn enter_sends() -> Bool {
  !soft_keyboard()
}

///|
/// Whether what is attached is picked from a sheet of what the device holds (its photos, its camera, its files: touch's,
/// a phone's or a tablet's attach sheet) rather than the system's file picker at once (keyboard and mouse's): the native
/// input's.
pub fn attach_from_sheet() -> Bool {
  native_input() is Finger
}

///|
/// Whether a page `width` wide that a browser's keys drive (a web service's) has them under it, in a thumb's reach, as a
/// phone's browser has them and an iPad's Safari as narrow (its own width's: a phone's, a tablet's side panel), rather
/// than in a row over it: touch's, the native input's, in the narrow arrangement (look_for).
pub fn keys_at_foot(width : Double) -> Bool {
  native_input() is Finger && look_for(width) is Narrow
}

///|
/// How far an edge standing in a gap `gap` wide between two panels (the tape's, sfdesk's tape_edge) takes presses past
/// the gap, into the panel it sizes and into the one beside it: with touch none of its own (a row there is swiped
/// across) and edge_finger_reach of the other, the gap and that as wide as a finger aims at a thing that thin; with
/// keyboard and mouse as much of each as makes the wide frame's edge's 12 (S3: Rail.css.ts edge). The native input's:
/// the boxes never follow the hand.
pub fn edge_reach(gap : Double) -> (Double, Double) {
  if native_input() is Finger {
    (0.0, edge_finger_reach)
  } else {
    let each = (@ui.Space::px(S3) - gap) / 2.0
    (each, each)
  }
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
  // (told once the frame's builds are over, whichever build took the hold: one built again sees the press taken)
  c.tell("haptic/hold/" + key, fn() {
    if held_felt.get(key) != Some(at) {
      held_felt[key] = at
      @ui.haptic(LongPress)
    }
  })
  true
}

///|
/// The press each menu held was last felt for (menu_held), by what it is of.
// kept across runs: let go as the app begins anew (parts_reset)
let held_felt : Map[String, Int] = {}

///|
/// Where a menu asked of a thing on a line opens along it (`mid`: the line's middle): under the finger that held it,
/// or, right clicked (a pointer, whose press is not the click's), at the line's middle.
pub fn menu_along(c : @ui.Ctx, mid : Double) -> Double {
  if pointer_rests() {
    mid
  } else {
    c.press().x
  }
}
