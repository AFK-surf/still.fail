// Time for the components (docs/components.md, "Time and motion"): everything in them that waits or moves goes
// through these three, on the Ctx's clock (a Tester moves it; screenshots and reduced motion put motion at its end at
// once), so that nothing counts frames of its own and one scheduler can stand behind all of it later. `after` is a
// delay (a tooltip's, a toast's time); `presence` is Motion's AnimatePresence (what is shown comes in, and once it is
// not shown stays built, inert, until its exit has played); `animate` a value going where it is told by a transition
// (Motion's animate, a spring or a tween: @motion.Spec).

///|
/// A delay kept by its id: how long its condition has held, when it was last seen holding (-1 not), the frame it
/// was last asked.
priv struct Wait {
  mut held : Double
  mut last : Double
  mut used : Int
}

///|
/// What the components keep from frame to frame outside the Ctx, made anew when a Tester starts.
priv struct KitState {
  waits : Map[Int, Wait]
}

///|
let kit : Ref[KitState] = Ref({ waits: {} })

///|
let installed : Ref[Bool] = Ref(false)

///|
/// Plugged into ui (once): what the components keep forgotten when a Tester starts anew.
fn install() -> Unit {
  if installed.val {
    return
  }
  installed.val = true
  @ui.on_reset(fn() { kit.val = { waits: {} } })
}

///|
/// Whether `on` has held for `ms` (by the Ctx's clock), asked each frame: a frame is asked for when it will have.
/// Not on, it starts again from nothing, unless `keep`: then it waits where it was (a toast's time, paused while the
/// pointer is over it). `key` in the scope it is asked in.
pub fn after(c : @ui.Ctx, key : String, on : Bool, ms : Double, keep? : Bool = false) -> Bool {
  install()
  let id = c.id("\u{2}after/" + key)
  let w = match kit.val.waits.get(id) {
    Some(w) => w
    None => {
      if !on {
        return false
      }
      let w = { held: 0.0, last: -1.0, used: 0 }
      kit.val.waits[id] = w
      w
    }
  }
  w.used = c.frame_number()
  sweep(c)
  if !on {
    w.last = -1.0
    if !keep {
      w.held = 0.0
    }
    return false
  }
  if w.last >= 0.0 {
    w.held = w.held + (c.now() - w.last)
  }
  w.last = c.now()
  if w.held >= ms {
    true
  } else {
    c.wake_in(ms - w.held)
    false
  }
}

///|
/// Forgets the delays not asked for a while (a widget gone).
fn sweep(c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  if frame % 120 != 0 {
    return
  }
  let old : Array[Int] = []
  kit.val.waits.each(fn(id, w) { if frame - w.used > 120 { old.push(id) } })
  for id in old {
    kit.val.waits.remove(id)
  }
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
/// Motion's AnimatePresence for one thing (see the file's head): `shown` comes in by `enter`, goes out by `exit`
/// (Motion's `animate` and `exit` transitions) and is built until it is out. `initial`: shown from the start comes in
/// too (Motion's `initial`); else it starts in.
pub fn presence(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : @motion.Spec = @motion.tween(150.0, ease=Out),
  exit? : @motion.Spec = @motion.tween(100.0, ease=LeaveFade),
  initial? : Bool = true,
) -> Presence {
  let k = "\u{2}presence/" + key
  let a = @motion.anim(c, k, if shown && !initial { 1.0 } else { 0.0 })
  if shown {
    a.follow(1.0, enter)
  } else {
    a.follow(0.0, exit)
  }
  let t = a.get()
  { built: shown || t > 0.0 || a.moving(), shown, t }
}

///|
/// A number going to `target` by `transition` (Motion's animate; by default a spring): from where it is, as fast as
/// it goes, when told anew. Its value this frame. `key` in the scope it is asked in.
pub fn animate(
  c : @ui.Ctx,
  key : String,
  target : Double,
  transition? : @motion.Spec = @motion.spring(),
) -> Double {
  @motion.animate(c, "\u{2}animate/" + key, target, spec=transition)
}
