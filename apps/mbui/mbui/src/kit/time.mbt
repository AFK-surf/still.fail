// Time for the components (docs/components.md, "Time and motion"): everything in them that waits or moves goes
// through these three, on the Ctx's clock (a Tester moves it; screenshots and reduced motion put motion at its end at
// once), so that nothing counts frames of its own and one scheduler can stand behind all of it later. `after` is a
// delay (a tooltip's, a toast's time); `presence` is Motion's AnimatePresence (what is shown comes in, and once it is
// not shown stays built, inert, until its exit has played); `animate` a value going where it is told by a transition
// (Motion's animate, a spring or a tween: @motion.Spec).

///|
/// What the components keep from frame to frame outside the Ctx, made anew when a Tester starts.
priv struct KitState {
  /// what opens by itself (a tooltip, a hover card), by its id: open last frame
  opens : Map[Int, Bool]
  /// a tooltip kept shut until the pointer leaves its trigger (pressed, or Escape)
  shut : Map[Int, Bool]
  /// a tooltip a finger held open on its trigger, until a moment after it is lifted or the next press: whether it has
  /// been lifted
  held_tips : Map[Int, Bool]
  /// where what a popover, a hover card or a tooltip hangs on was drawn, by the panel's id, and the frame it was last
  /// put by it (beside): kept on while it is shown, for the frames its trigger is drawn nowhere (gone as it goes out)
  anchors : Map[Int, ((Double, Double, Double, Double), Int)]
  /// toasts as drawn (toast.mbt), by their viewport's id; when the next of a viewport's goes (toast_due), by its key
  toasts : Map[Int, Kept]
  toast_dues : Map[String, Double]
  /// a menu's panel's open submenu (its entry's index, menu.mbt), by the panel's id
  subs : Map[Int, Int]
  /// where each loupe last read (loupe.mbt), by its key: where it goes as it is let go
  loupes : Map[String, (Double, Double)]
  /// what was typed to find an entry by its first letters, by the panel's id (when: Ctx::mark, by that id)
  typed : Map[Int, String]
  /// where a context menu opened, by its id; which of a menubar's menus is open (-1 none), by its id
  at : Map[Int, (Double, Double)]
  bars : Map[Int, Int]
  /// a form's state (form.mbt), by its id
  forms : Map[Int, FormState]
  /// a sheet's springs and scrim (sheet.mbt), by its id; the id of the one built last by each key (sheet_rest)
  sheets : Map[Int, SheetKept]
  sheet_keys : Map[String, Int]
  /// the pointer this frame and the last (whether it moved: what moves a menu's highlight), as of frame `ptr_frame`
  mut ptr : (Double, Double)
  mut ptr_was : (Double, Double)
  mut ptr_frame : Int
}

///|
fn KitState::new() -> KitState {
  {
    opens: {},
    shut: {},
    held_tips: {},
    anchors: {},
    toasts: {},
    toast_dues: {},
    subs: {},
    loupes: {},
    typed: {},
    at: {},
    bars: {},
    forms: {},
    sheets: {},
    sheet_keys: {},
    ptr: (-1.0, -1.0),
    ptr_was: (-1.0, -1.0),
    ptr_frame: -1,
  }
}

///|
/// Whether the pointer moved since the last frame.
fn pointer_moved(c : @ui.Ctx) -> Bool {
  install()
  let k = kit.val
  if k.ptr_frame != c.frame_number() {
    k.ptr_frame = c.frame_number()
    k.ptr_was = k.ptr
    let (x, y, _) = c.pointer()
    k.ptr = (x, y)
  }
  k.ptr != k.ptr_was
}

///|
let kit : Ref[KitState] = Ref(KitState::new())

///|
// kept across runs: the hooks it guards are kept too (installed once in the process, by the packages over ui)
let installed : Ref[Bool] = Ref(false)

///|
/// Plugged into ui (once): what the components keep forgotten when a Tester starts anew.
fn install() -> Unit {
  if installed.val {
    return
  }
  installed.val = true
  @ui.on_reset(fn() { kit.val = KitState::new() })
}

///|
/// Whether `on` has held for `ms`, asked each frame: the framework's wait (Ctx::held), a wake when it will have.
/// Not on, it starts again from nothing, unless `keep`: then it waits where it was (a toast's time, paused while the
/// pointer is over it). `key` in the scope it is asked in. `later`: what is shown does not wait for it (a toast going
/// away after its time); by default it does (a menu opening once the pointer rests). `since`, `owned`: Ctx::held's.
#callsite(autofill(loc))
pub fn after(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  ms : Double,
  keep? : Bool = false,
  later? : Bool = false,
  since? : Double = -1.0,
  owned? : Bool = false,
  loc~ : SourceLoc,
) -> Bool {
  c.held(key, on, ms, keep~, later~, since~, owned~, loc~)
}

///|
/// What `presence` says of something shown or not: whether to build it (shown, or still leaving), whether it is
/// shown (not leaving: it takes input), how far in it is (0 out … 1 in; a spring may pass 1).
pub(all) struct Presence {
  built : Bool
  shown : Bool
  t : Double
} derive(Show)

///|
/// Whether it is leaving (built, not shown: inert, its exit drawn).
pub fn Presence::leaving(self : Presence) -> Bool {
  self.built && !self.shown
}

///|
/// How long `presence` takes by default to come in (ms), and to go out: a tween each.
pub let presence_in_ms : Double = 150.0

///|
pub let presence_out_ms : Double = 100.0

///|
/// Motion's AnimatePresence for one thing (see the file's head): `shown` comes in by `enter`, goes out by `exit`
/// (Motion's `animate` and `exit` transitions) and is built until it is out. `initial`: shown from the start comes in
/// too (Motion's `initial`); else it starts in.
#callsite(autofill(loc))
pub fn presence(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : @motion.Spec = @motion.tween(presence_in_ms, ease=Out),
  exit? : @motion.Spec = @motion.tween(presence_out_ms, ease=Leave),
  initial? : Bool = true,
  loc~ : SourceLoc,
) -> Presence {
  let k = "\u{2}presence/" + key
  let a = @motion.anim(c, k, if shown && !initial { 1.0 } else { 0.0 })
  if shown {
    a.follow(1.0, enter, loc~)
  } else {
    a.follow(0.0, exit, loc~)
  }
  let t = a.get()
  { built: shown || t > 0.0 || a.moving(), shown, t }
}

///|
/// A number going to `target` by `transition` (Motion's animate; by default a spring): from where it is, as fast as
/// it goes, when told anew. Its value this frame. `key` in the scope it is asked in.
#callsite(autofill(loc))
pub fn animate(
  c : @ui.Ctx,
  key : String,
  target : Double,
  transition? : @motion.Spec = @motion.spring(),
  loc~ : SourceLoc,
) -> Double {
  @motion.animate(c, "\u{2}animate/" + key, target, spec=transition, loc~)
}
