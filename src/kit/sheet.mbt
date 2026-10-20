// A sheet from the bottom (not one of Radix's: Vaul's Drawer; still.fail's phone sheets, its Android Sheet.kt
// SheetHost): whether it is open the view's. Modal: the page under it dimmed (its scrim in over 300 ms, CSS's ease),
// out of the semantics tree and taking no press, Tab kept in it, the focus back where it was as it goes. It rises on a
// spring (critically damped, a third of a second) and sinks away on it. Its top (`drag_h` high: the grabber and the
// head) drags it: a sheet with `detents` (shares of the window) settles at the one it is let go nearer, going on at
// the finger's speed, and closes let go under `close_below`; a tap on its grabber goes to the other end; one without
// only goes down, closing past 80, else back. Escape, the back and a press on the page above it close it. When what it
// shows asks for another height, it goes there on the spring.

///|
/// What a sheet's look is given: its scrim's share (0 … 1, how far in it is), its height (on the spring), how far
/// below its place it is.
pub(all) struct SheetState {
  t : Double
  h : Double
  below : Double
}

///|
/// What a drag on a sheet's top came to (for logs and scripted runs).
pub(all) enum SheetDrag {
  /// let go low enough: it closes
  DraggedClosed
  /// let go not far enough: back where it was
  DraggedBack
  /// let go: on to this share of the window
  DraggedTo(Double)
} derive(Eq, Show, Debug)

///|
/// What a sheet reports: whether it is open now, whether it is drawn (open, or still sinking away), what a drag let go
/// this frame came to.
pub(all) struct Sheet {
  open : Bool
  shown : Bool
  dragged : SheetDrag?
}

///|
/// still.fail's sheet spring (Motion.kt SheetSpring: motionSpring(0.32), critically damped): its stiffness.
let sheet_k : Double = {
  let w = 2.0 * 3.141592653589793 / (1.2 * 0.32)
  w * w
}

///|
/// How long a sheet's scrim takes to fade in or out (ms).
pub let sheet_scrim_ms : Double = 300.0

///|
/// The scrim's fade: sheet_scrim_ms on CSS's ease (Sheet.kt's scrim tween).
fn scrim_fade() -> @motion.Spec {
  @motion.tween(sheet_scrim_ms, ease=Css)
}

///|
/// A sheet's spring at rest at `x` (at rest within half a point).
fn sheet_spring(x : Double) -> @ui.SpringPath {
  @ui.SpringPath::new(x, k=sheet_k, c=2.0 * sheet_k.sqrt(), rest=0.5)
}

///|
/// A sheet's state between frames, by its id.
priv struct SheetKept {
  h : @ui.SpringPath
  below : @ui.SpringPath
  /// where a finger has its height while dragging (-1 none)
  mut held : Double
  /// how much of its scrim shows (0 … 1), fading in and out over sheet_scrim_ms
  fade : @motion.Anim
  /// open last frame; drawn (until it has sunk away); the height it was asked for last
  mut was_open : Bool
  mut shown : Bool
  mut asked : Double
}

///|
/// `key`'s sheet (see the file's head), `open` or not, what `body` builds in it: `h` high (or, when it is not given,
/// `share` of the window), its top `drag_h` high dragging it, its scrim `scrim` (the theme's) at its fullest, named
/// `label` for the semantics tree. Whether it is open now, whether it is drawn, what a drag came to.
pub fn sheet(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  body : () -> Unit,
  h? : Double = -1.0,
  share? : Double = 0.5,
  detents? : Array[Double] = [],
  close_below? : Double = 0.3,
  drag_h? : Double = 64.0,
  scrim? : Int64,
  label? : String = "",
  look? : (@ui.Ctx, SheetState, () -> Unit) -> Unit = sheet_look,
) -> Sheet {
  install()
  let th = c.theme()
  let id = c.id(key)
  kit.val.sheet_keys[key] = id
  let (_, total) = c.window_size()
  let target = if h >= 0.0 { h } else { share * total }
  let s = match kit.val.sheets.get(id) {
    Some(s) => s
    None => {
      let s = {
        h: sheet_spring(0.0),
        below: sheet_spring(0.0),
        held: -1.0,
        fade: @motion.Anim::new(0.0),
        was_open: false,
        shown: false,
        asked: -1.0,
      }
      kit.val.sheets[id] = s
      s
    }
  }
  let mut now = open
  let mut dragged : SheetDrag? = None
  // opened: from below at its height; asked another height while open: there on the spring
  if open && !s.was_open {
    if !s.shown || s.below.value_at(c) > 1.0 {
      s.h.put(target)
      s.below.put(target)
    }
    if s.h.target() != target {
      s.h.go_at(c, target)
    }
    s.below.go_at(c, 0.0)
    s.fade.animate(1.0, scrim_fade())
    s.shown = true
    s.asked = target
  } else if open && target != s.asked {
    s.h.go_at(c, target)
    s.asked = target
  }
  if !s.shown {
    s.was_open = open
    return { open, shown: false, dragged: None }
  }
  // the top's drag
  let top_id = c.id(key + "/top")
  let draggable = !detents.is_empty()
  match c.drag_of(top_id) {
    Some(d) if open => {
      let (_, dy) = d.take_move()
      if dy != 0.0 {
        let from = if s.held >= 0.0 { s.held } else { s.h.value_at(c) }
        let top = if draggable { total * detents.fold(init=0.0, fn(a, b) { dmax(a, b) }) } else { target }
        let to = dclamp(from - dy, 120.0, top)
        s.held = to
        s.h.put(to)
      }
      if d.take_end() {
        let at = if s.held >= 0.0 { s.held } else { s.h.value_at(c) }
        s.held = -1.0
        // up is more, per second
        let v = -d.vy * 1000.0
        if !draggable {
          if target - at > 80.0 {
            dragged = Some(DraggedClosed)
            now = false
          } else {
            dragged = Some(DraggedBack)
            s.h.go_at(c, target, v~)
          }
        } else if at / total < close_below {
          dragged = Some(DraggedClosed)
          now = false
        } else {
          let f = nearest(detents, at / total)
          dragged = Some(DraggedTo(f))
          s.h.go_at(c, f * total, v~)
        }
      }
      // a tap on the grabber (its top 30): to the other end
      if d.take_tap() && draggable && d.y - (total - s.h.value_at(c) + s.below.value_at(c)) < 30.0 {
        let lo = detents.fold(init=1.0, fn(a, b) { dmin(a, b) })
        let hi = detents.fold(init=0.0, fn(a, b) { dmax(a, b) })
        s.h.go_at(c, if s.h.value_at(c) > (lo + hi) / 2.0 * total { lo * total } else { hi * total }, v=0.0)
      }
    }
    _ => ()
  }
  // closed: it sinks away
  if !now && s.was_open {
    s.held = -1.0
    s.below.go_at(c, s.h.value_at(c))
    s.fade.animate(0.0, scrim_fade())
  }
  // (the springs and the fade say themselves that they move, as they set out: Ctx::moving)
  if c.still() {
    s.h.put(s.h.target())
    s.below.put(s.below.target())
  }
  let hx = s.h.value_at(c)
  let bx = s.below.value_at(c)
  let scrim_t = s.fade.get()
  // (logic on a motion's end, to be told at once instead: shown is false only once it has sunk away and its scrim
  // faded, the sheet drawn until then from what it is)
  if !now && bx >= hx - 0.5 && !s.fade.moving() {
    // sunk away
    s.shown = false
    s.fade.snap(0.0)
    s.was_open = false
    return { open: false, shown: false, dragged }
  }
  let o = c.overlay(key, modal=true, scrim=@ui.alpha(scrim.unwrap_or(th.scrim), scrim_t), inert=!now, fn() {
    let i = c.box(w=Fill(1.0), h=Px(hx), ty=total - hx + bx, fn() {
      look(c, { t: scrim_t, h: hx, below: bx }, fn() {
        // behind what it shows (its buttons take their taps), over the sheet (it takes the drags): what lies on it
        // (its title, its grabber) pressed through it, while it takes presses (not as it sinks away)
        if now {
          c.presses_to(top_id)
        }
        c.layer(fn() { c.drag_area(top_id, axis=Vertical, w=Fill(1.0), h=Px(drag_h), fn() {  }) |> ignore }) |> ignore
        body()
      })
    })
    c.semantics(i, Dialog, label~, modal=true)
  })
  if now && o.dismissed is Some(_) {
    now = false
    s.held = -1.0
    s.below.go_at(c, hx)
    s.fade.animate(0.0, scrim_fade())
  }
  s.was_open = now
  { open: now, shown: true, dragged }
}

///|
/// When sheet `key` (the key it is built by, the last built by it) is at rest: its height's and its sinking's springs
/// and its scrim's fade all there (the frames' clock; -1: it is not moving; +inf: told to move, not started yet).
/// What a test runs to once it opened or closed one.
pub fn sheet_rest(key : String) -> Double {
  match kit.val.sheet_keys.get(key) {
    Some(id) =>
      match kit.val.sheets.get(id) {
        Some(s) => {
          let mut e = -1.0
          for r in [s.h.end(), s.below.end(), s.fade.ends_at()] {
            if r > e {
              e = r
            }
          }
          e
        }
        None => -1.0
      }
    None => -1.0
  }
}

///|
/// Of `shares`, the one nearest `f`.
fn nearest(shares : Array[Double], f : Double) -> Double {
  let mut best = shares[0]
  for x in shares {
    if (x - f).abs() < (best - f).abs() {
      best = x
    }
  }
  best
}

///|
/// A sheet's grabber (still.fail's Sheet.kt SheetGrab): 38 by 5 in the theme's line colour, 12 above it and 8 under.
pub fn sheet_grabber(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
    c.box(w=Px(38.0), h=Px(5.0), radius=2.5, bg=t.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A sheet's default look (still.fail's phone sheets): the theme's surface, its top corners 26 round (26 more of it
/// under the window's foot), a shadow; its grabber, then what it holds.
pub fn sheet_look(c : @ui.Ctx, s : SheetState, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), h=Px(s.h + 26.0), radius=26.0, bg=t.surface, shadow=24.0, shadow_color=t.shadow, clip=true, pb=26.0, fn() {
    sheet_grabber(c)
    body()
  })
  |> ignore
}
