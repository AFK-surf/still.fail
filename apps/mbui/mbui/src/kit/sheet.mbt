// A sheet from the bottom (not one of Radix's: Vaul's Drawer; still.fail's phone sheets, its Android Sheet.kt
// SheetHost): whether it is open the view's. Modal: the page under it dimmed (its scrim in over 300 ms, CSS's ease),
// out of the semantics tree and taking no press, Tab kept in it (no field given the focus as it opens: the keyboard
// would come up over it; nor one under it left with it: its own ground has it while it is up), the focus back where it
// was as it goes. It rises on a
// spring (critically damped, a third of a second) and sinks away on it. Its top (`drag_h` high: the grabber and the
// head) drags it: a sheet with `detents` (shares of the window) settles at the one it is let go nearer, going on at
// the finger's speed, and closes let go under `close_below`; a tap on its grabber goes to the other end; one without
// only goes down, closing past 80, else back. Escape, the back and a press on the page above it close it. When what it
// shows asks for another height, it goes there on the spring.

///|
/// How short a sheet with detents is dragged at most.
let sheet_least_h : Double = 120.0

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
#derive(Eq, Debug)
pub(all) enum SheetDrag {
  /// let go low enough: it closes
  DraggedClosed
  /// let go not far enough: back where it was
  DraggedBack
  /// let go: on to this share of the window
  DraggedTo(Double)
}

///|
/// What a sheet reports: whether it is open now, whether it is drawn (open, or still sinking away), what a drag let go
/// this frame came to, how tall it stands over the window's foot as it is drawn (0 not drawn: what comes in its place
/// starts from).
pub(all) struct Sheet {
  open : Bool
  shown : Bool
  dragged : SheetDrag?
  stands : Double
}

///|
/// How long a sheet's scrim takes to fade in or out (ms).
pub let sheet_scrim_ms : Double = 300.0

///|
/// The scrim's fade: sheet_scrim_ms on CSS's ease.
fn scrim_fade() -> @motion.Spec {
  @motion.tween(sheet_scrim_ms, ease=Out)
}

///|
/// A sheet's way at rest at `x`: a Move as long as it goes far (a short sheet risen sooner than a tall one), from where
/// it is, as fast as it goes or as the finger let it go.
fn sheet_spring(x : Double) -> @ui.SpringPath {
  @ui.SpringPath::moved(x)
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
  /// open last frame; drawn (until it has sunk away); the height it was asked for last; opened and not
  /// risen yet from below (its height told as what it holds is first laid out comes from below at that)
  mut was_open : Bool
  mut shown : Bool
  mut asked : Double
  mut rising : Bool
  /// whether an editor inside this sheet held the focus last frame (its foot then at the soft keyboard's top, else at
  /// the screen's foot)
  mut in_ime : Bool
  /// opened in another's place (sheet's `in_place`): how tall that one stood and the moment (-1: not), and how much
  /// taller than its own height it stands (shorter: less than none), from that at that moment on a Move to none
  mut placed : Double
  mut placed_at : Double
  lag : @ui.SpringPath
}

///|
/// `key`'s sheet (see the file's head), `open` or not, what `body` builds in it: `h` high (or, when it is not given,
/// `share` of the window), its top `drag_h` high dragging it, its scrim `scrim` (the theme's) at its fullest, named
/// `label` for the semantics tree; an Escape `on_escape` says it took a step back within it (Ctx::overlay's), not
/// closing it. `raised`: how far over its place it is drawn (up out of the way of another over it); closed so, it
/// sinks from there, as far as takes it out of sight. `sinks`: closed, how far it sinks at least (with others closing
/// at once over it, as far as they all do, sinking as one with them). `in_place`: opened in the place of another
/// that stood so tall, gone at that moment (what was chosen in that one opened this): there at once that tall, its
/// scrim whole as that one's was, on a Move to its own height from there, not from below (-1: not so). Whether it is
/// open now, whether it is drawn, what a drag came to.
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
  on_escape? : () -> Bool,
  raised? : Double = 0.0,
  sinks? : Double = 0.0,
  in_place? : Double = -1.0,
) -> Sheet {
  install()
  let th = c.theme()
  let id = c.id(key)
  kit.val.sheet_keys[key] = id
  let mut now = open && !c.will_dismiss(id)
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
        rising: false,
        in_ime: false,
        placed: -1.0,
        placed_at: -1.0,
        lag: sheet_spring(0.0),
      }
      kit.val.sheets[id] = s
      s
    }
  }
  let in_ime = now && (c.focused_editor_in_layer(id) || (s.in_ime && s.was_open && c.ime_inset() > 0.0))
  let total = c.window_size().1 + (if in_ime { 0.0 } else { c.ime_inset() })
  let target = if h >= 0.0 { h } else { share * total }
  let mut dragged : SheetDrag? = None
  let old_hx = s.h.value_at(c) + dmax(s.lag.value_at(c), 0.0)
  // opened: from below at its height; asked another height while open (what it holds laid out another height, the
  // window another): that height at once, as it is laid out (placed by its size, not chased to it)
  if now && !s.was_open && in_place >= 0.0 && !s.shown {
    // (in another's place, that one gone as this comes: its scrim whole as that one's was, at its own height drawn
    // as much taller as that one stood, on a Move to none)
    s.h.put(target)
    s.below.put(0.0)
    s.lag.put(in_place - target)
    s.lag.go_at(c, 0.0)
    s.fade.snap(c, 1.0)
    s.shown = true
    s.asked = target
    s.rising = false
    s.placed = in_place
    s.placed_at = c.moment()
  } else if now && !s.was_open {
    s.placed_at = -1.0
    s.lag.put(0.0)
    if !s.shown || s.below.value_at(c) > 1.0 {
      s.h.put(target)
      s.below.put(target)
    }
    if s.h.target() != target {
      s.h.go_at(c, target)
    }
    s.below.go_at(c, 0.0)
    s.fade.animate(c, 1.0, scrim_fade())
    s.shown = true
    s.asked = target
    s.rising = true
  } else if now && s.rising && s.below.value_at(c) < s.asked - 0.5 {
    // (risen some way: what it is asked for from now on is another height while open)
    s.rising = false
  }
  if now && s.was_open && target != s.asked {
    if s.placed_at >= 0.0 && c.moment() == s.placed_at {
      // (in another's place, its height told anew at the moment it came, as what it holds is first laid out: from
      // where that one stood to this)
      s.h.put(target)
      s.lag.put(s.placed - target)
      s.lag.go_at(c, 0.0)
    } else if s.rising {
      // (opened and not risen yet, its height known only as what it holds is laid out: from below at that)
      s.h.put(target)
      s.below.put(target)
      s.below.go_at(c, 0.0)
    } else if s.held < 0.0 {
      s.h.put(target)
    }
    s.asked = target
  }
  if now && s.was_open && in_ime != s.in_ime && c.ime_inset() > 0.0 {
    let df = if in_ime { -c.ime_inset() } else { c.ime_inset() }
    let new_hx = s.h.value_at(c) + dmax(s.lag.value_at(c), 0.0)
    let (bx0, bv0) = s.below.at(c.moment())
    s.below.put(bx0 - df + (new_hx - old_hx))
    s.below.go_at(c, 0.0, v=bv0)
  }
  if !s.shown {
    s.was_open = now
    s.in_ime = in_ime
    return { open: now, shown: false, dragged: None, stands: 0.0 }
  }
  // the top's drag
  let top_id = c.id(key + "/top")
  let draggable = !detents.is_empty()
  match c.drag_of(top_id) {
    Some(d) if now => {
      let (_, dy) = d.take_move()
      if dy != 0.0 {
        // (`held`: where the finger has it, past its top too; drawn there, past its top given way to: stretched; from
        // as tall as it is drawn, in another's place on its way still)
        let from = if s.held >= 0.0 { s.held } else { s.h.value_at(c) + s.lag.value_at(c) }
        s.lag.put(0.0)
        let top = if draggable { total * detents.fold(init=0.0, fn(a, b) { dmax(a, b) }) } else { target }
        // (one with detents no shorter than its least drag keeps; one without follows the finger down all the way,
        // however short it is: else one shorter than that and 80 could never be dragged closed)
        let least = if draggable { sheet_least_h } else { 0.0 }
        let to = dmax(from - dy, least)
        // drawn past its top: felt as it starts to give
        if from <= top && to > top {
          felt_tick(c, key + "/top")
        }
        s.held = to
        s.h.put(stretched(to, top, total - top))
      }
      if d.take_end() {
        let at = s.h.value_at(c) + s.lag.value_at(c)
        s.lag.put(0.0)
        s.held = -1.0
        // up is more, per second
        let v = -d.vy * 1000.0
        if !draggable {
          if sheet_drag_closes(target - at, d.vy, 80.0) {
            dragged = Some(DraggedClosed)
            now = false
          } else {
            dragged = Some(DraggedBack)
            s.h.go_at(c, target, v~)
          }
        } else {
          match sheet_goes_to(detents, at, d.vy, total, close_below) {
            None => {
              dragged = Some(DraggedClosed)
              now = false
            }
            Some(f) => {
              dragged = Some(DraggedTo(f))
              s.h.go_at(c, f * total, v~)
            }
          }
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
  let mut eff_total = total
  // closed: it sinks away from the height it has, which stays (one still on its way to another height, told as it
  // was opened or while open, stops there: else it would sink to where it was and the rest of it stay up)
  if !now && s.was_open {
    s.held = -1.0
    let at = s.h.value_at(c) + s.lag.value_at(c)
    s.lag.put(0.0)
    s.h.put(at)
    let (bx0, bv0) = s.below.at(c.moment())
    let had_ime = s.in_ime || in_ime
    if had_ime {
      eff_total = c.window_size().1 + c.ime_inset()
      if c.ime_inset() > 0.0 {
        s.below.put(bx0 - c.ime_inset())
      }
    }
    s.below.go_at(c, dmax(at + raised, sinks), v=bv0)
    s.fade.animate(c, 0.0, scrim_fade())
  } else if !now && sinks > s.below.target() {
    // (told how far after it closed, as one under it closed with it: on as far as that, as fast as it goes)
    s.below.go_at(c, sinks)
  }
  // (the springs and the fade say themselves that they move, as they set out: Ctx::moving)
  if c.still() {
    s.h.put(s.h.target())
    s.below.put(s.below.target())
    s.lag.put(0.0)
  }
  // (in another's place, on its way to its own height: what it holds laid out at its own height all the way, nothing
  // laid out again for the way; taller meanwhile, its glass that much taller under what it holds; shorter, as far
  // below its place)
  let own = s.h.value_at(c)
  let lag = s.lag.value_at(c)
  let hx = own + dmax(lag, 0.0)
  let bx = s.below.value_at(c) + dmax(-lag, 0.0)
  // (shown is false only once it has sunk away and its scrim's fade is over, by its declared end, the sheet drawn until
  // then from what it is; sunk as far as it was told to go, not less: one closing with it gone first, the furthest they
  // went no more what it sinks to, it still goes on to where it set out for, not ending where the others' going leaves
  // it)
  if !now && bx >= dmax(dmax(hx + raised, sinks), s.below.target()) - 0.5 && s.fade.over(c) {
    // sunk away
    s.shown = false
    s.fade.snap(c, 0.0)
    s.was_open = false
    s.in_ime = false
    return { open: false, shown: false, dragged, stands: 0.0 }
  }
  // (Tab kept in it, but no field in it given the focus as it opens: a sheet is a touch screen's, where a field
  // focused brings the keyboard up over what the sheet shows; one that asks for words gives its field the focus itself.
  // Nor one under it kept: what has the focus outside it gives it to the sheet's own ground (@ui.layer_ground), the
  // keyboard put away and nothing typed reaching the page under it, given back as the sheet goes)
  // (the scrim as far as it has come, as it is drawn: Ctx::bg_by on the layer's ground)
  let scrim = scrim.unwrap_or(th.scrim)
  let o = c.overlay(key, modal=true, initial_focus=@ui.layer_ground, on_escape?, scrim~, inert=!now, fn() {
    let i = c.box(w=Fill(1.0), h=Px(hx), ty=eff_total - hx + bx - raised, fn() {
      // (its look given the scrim's share as it is built: the sheet's own glass drawn solid darkens with it, a colour
      // with no form read as it is drawn; the sheet is laid out again as it goes anyway, its height and place its
      // springs' as they are built)
      look(c, { t: s.fade.get(c), h: hx, below: bx }, fn() {
        // behind what it shows (its buttons take their taps), over the sheet (it takes the drags): what lies on it
        // (its title, its grabber) pressed through it, while it takes presses (not as it sinks away, nor raised under
        // another, which takes them: its top may be past the window's then; nor while what it drags by is above the
        // window, the sheet pulled past its most and giving way, springing back: nothing of it there to press)
        if now && raised <= 0.0 && eff_total - hx + bx - raised + drag_h > 0.0 {
          c.presses_to(top_id)
        }
        c.layer(fn() { c.drag_area(top_id, axis=Vertical, w=Fill(1.0), h=Px(drag_h), fn() {  }) |> ignore }) |> ignore
        c.box(style=@ui.style(w=Full, h=Fixed(own)), fn() { body() }) |> ignore
      })
    })
    c.semantics(i, Dialog, label~, modal=true)
    // (where it stands, for what is to stay clear of it: sheet_top)
    @motion.measure(c, i, sheet_measured)
  })
  if o.scrim >= 0 {
    c.bg_by(o.scrim, fn() { @ui.alpha(scrim, s.fade.get(c)) })
  }
  if now && o.dismissed is Some(_) {
    now = false
    s.held = -1.0
    s.lag.put(0.0)
    s.h.put(own + lag)
    let (bx0, bv0) = s.below.at(c.moment())
    if in_ime && c.ime_inset() > 0.0 {
      s.below.put(bx0 - c.ime_inset())
    }
    s.below.go_at(c, dmax(own + lag + raised, sinks), v=bv0)
    s.fade.animate(c, 0.0, scrim_fade())
  }
  s.was_open = now
  s.in_ime = now && in_ime
  { open: now, shown: true, dragged, stands: dmax(0.0, hx - bx + raised) }
}

///|
/// How tall a sheet is drawn `h` high under a finger, its top `top` and `room` above that: as high as the finger has it
/// up to its top, past it giving way more the further it is drawn (iOS's rubber band: (1 − 1 / (x·0.55 / d + 1))·d),
/// never past the room there is.
fn stretched(h : Double, top : Double, room : Double) -> Double {
  if h <= top || room <= 0.0 {
    return dmin(h, top)
  }
  let x = h - top
  top + (1.0 - 1.0 / (x * sheet_give / room + 1.0)) * room
}

///|
/// How much a sheet drawn past its top gives way (UIScrollView's rubber band's constant).
let sheet_give : Double = 0.55

///|
/// Where the top of the sheet up is in the window this frame, as it is laid out (None where none is up): for what
/// stays clear of it as it comes and goes (a row held for the menu in it, lifted over its scrim: Stratum's OverScrim), read
/// once this frame is laid out (@motion.placed).
pub fn sheet_top(c : @ui.Ctx) -> Double? {
  match @motion.measured_rect(c, sheet_measured) {
    Some((_, y, _, _)) => Some(y)
    None => None
  }
}

///|
/// Where the top of the sheet up is in the window this frame and how tall it is, as it is laid out (None where none is
/// up): sheet_top's, with how far it has to come up (for what keeps clear of it once it is all the way up).
pub fn sheet_place(c : @ui.Ctx) -> (Double, Double)? {
  match @motion.measured_rect(c, sheet_measured) {
    Some((_, y, _, h)) => Some((y, h))
    None => None
  }
}

///|
let sheet_measured : String = "kit-sheet"

///|
/// When sheet `key` (the key it is built by, the last built by it) is at rest: its height's and its sinking's springs
/// and its scrim's fade all there (the frames' clock; +inf: told to move, not started yet), each over its end as it
/// said it, whichever frames were drawn on its way; -1: none of it has moved. What a test runs to once it opened or
/// closed one.
pub fn sheet_rest(key : String) -> Double {
  match kit.val.sheet_keys.get(key) {
    Some(id) =>
      match kit.val.sheets.get(id) {
        Some(s) => {
          let mut e = -1.0
          for r in [s.h.end(), s.below.end(), s.lag.end(), s.fade.ended_at()] {
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
fn nearest_share(shares : Array[Double], f : Double) -> Double {
  let mut best = shares[0]
  for x in shares {
    if (x - f).abs() < (best - f).abs() {
      best = x
    }
  }
  best
}

///|
/// A sheet's grabber: 38 by 5 in the theme's line colour, 12 above it and 8 under.
pub fn sheet_grabber(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
    c.box(w=Px(38.0), h=Px(5.0), radius=2.5, bg=t.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// How far a sheet's default look reaches on under the window's foot (its foot's corners out of sight).
let sheet_under : Double = 26.0

///|
/// A sheet's default look (still.fail's phone sheets): the theme's surface, its top corners 26 round (26 more of it
/// under the window's foot), a shadow; its grabber, then what it holds.
pub fn sheet_look(c : @ui.Ctx, s : SheetState, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), h=Px(s.h + sheet_under), radius=26.0, bg=t.surface, shadow=24.0, shadow_color=t.shadow, clip=true, pb=sheet_under, fn() {
    sheet_grabber(c)
    body()
  })
  |> ignore
}

///|
/// Whether a sheet without detents let go `down` below its place, going `speed` down (points a ms), closes: landing past
/// `line` on from that speed (@ui.lands_past), or flicked down (@ui.flung_away) however short; else back. So one let
/// go back never goes on down past `line` before it turns (the coordinator of the migration, 2026-11-10). Its node
/// sheet's (sf's sheet_node) the same.
pub fn sheet_drag_closes(down : Double, speed : Double, line : Double) -> Bool {
  @ui.lands_past(down, speed, line) || speed >= @ui.flung_away
}

///|
/// Where a sheet with detents (`shares` of the window, `total` tall) let go `at` tall, going `speed` down (points a ms),
/// settles (none: it closes): flicked (@ui.flung_away) a detent on the way it was flicked from where it was let go,
/// down from its lowest closed, up from its highest its highest; else the detent nearest where it lands on from that
/// speed (@ui.lands_at), closed landing under `close_below` of the window. So one let go short of closing goes on
/// down no further than it was from closing before it turns (the coordinator of the migration, 2026-11-10). Its node
/// sheet's (sf's sheet_node) the same.
pub fn sheet_goes_to(shares : Array[Double], at : Double, speed : Double, total : Double, close_below : Double) -> Double? {
  let f = at / total
  if speed >= @ui.flung_away {
    // (the highest under it)
    let mut below : Double? = None
    for s in shares {
      if s < f && (match below { Some(b) => s > b; None => true }) {
        below = Some(s)
      }
    }
    below
  } else if speed <= -@ui.flung_away {
    // (the lowest over it; over the highest, the highest)
    let mut above : Double? = None
    let mut most = shares[0]
    for s in shares {
      most = if s > most { s } else { most }
      if s > f && (match above { Some(b) => s < b; None => true }) {
        above = Some(s)
      }
    }
    Some(above.unwrap_or(most))
  } else {
    let lands = @ui.lands_at(at, -speed) / total
    if lands < close_below {
      None
    } else {
      Some(nearest_share(shares, lands))
    }
  }
}
