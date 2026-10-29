// A loupe (iOS's text loupe, Android's Magnifier): what a finger hides as it drags what needs seeing where it is
// (@ui.Ctx::finger_reads: a field's caret or the ends of what is picked by their handles, a long press's word slid on)
// shown larger over it, in a capsule of the glass given (a knob's held: switch.mbt's lens), loupe_lift over the
// finger. It is the switch's knob's lens and the bar's ball, not one of its own: it comes in as the knob held does
// (switch_held's spring, larger by lens_grow, fading in), follows the finger as the ball does (follow_spring) and is
// drawn out by its speed as the ball is (speed_stretch); let go, it goes where it is. What shows in it is the frame
// there larger (@ui.Ctx::magnified), under the glass, which bends it at its rim. Drawn only.

///|
/// The loupe `key` over where `reads` (where the finger reads: None, none), of `glass` (none: what it shows bare).
#callsite(autofill(loc))
pub fn loupe(c : @ui.Ctx, key : String, reads : (Double, Double)?, glass? : @ui.Glass, loc~ : SourceLoc) -> Unit {
  install()
  // (come anew: where the finger is, not from where it last was)
  let fresh = !kit.val.loupes.contains(key)
  match reads {
    Some(at) => kit.val.loupes[key] = at
    None => ()
  }
  let held = switch_held(c, key + "/held", reads is Some(_))
  let (px, py) = match kit.val.loupes.get(key) {
    Some(at) => at
    None => return
  }
  if reads is None && held <= 0.001 {
    kit.val.loupes.remove(key)
    return
  }
  let (ww, _) = c.window_size()
  let half = loupe_w / 2.0
  let tx = dclamp(px, half + loupe_side, dmax(half + loupe_side, ww - half - loupe_side))
  let ty = dmax(loupe_h / 2.0 + loupe_side, py - loupe_lift)
  let ax = @motion.anim(c, key + "/x", tx)
  let ay = @motion.anim(c, key + "/y", ty)
  if fresh {
    ax.snap(tx)
    ay.snap(ty)
  }
  ax.follow(tx, follow_spring, loc~)
  ay.follow(ty, follow_spring, loc~)
  let x = ax.get()
  let y = ay.get()
  // (its way a frame at 60, as the ball's; none where it is all but there)
  let v = if (tx - x).abs() < 0.5 { 0.0 } else { ax.velocity / 60.0 }
  let (longer, lower) = speed_stretch(v)
  let w = loupe_w + longer
  let h = loupe_h - lower
  // (drawn out toward where it goes, its back where it was)
  let mid = x + (if v < 0.0 { -longer } else { longer }) / 2.0
  // over everything, a sheet's and a menu's too, taking no press nor the focus: what it shows, the lens over it, as a
  // sliding group's thumb's lens is drawn (toggle.mbt: raised by a shadow as far as it is in the finger, as large,
  // as faded in)
  c.overlay(key, escape=false, outside=false, initial_focus=0, inert=true, fn() {
    let full = dmin(1.0, held)
    let shade : @ui.Shadow = Cast(lens_shadow * full, lens_shadow_y * full, c.theme().shadow)
    let at = c.box(style=lens_capsule(w, h), tx=mid - w / 2.0, ty=y - h / 2.0, fn() {
      c.magnified(px, py, loupe_zoom, w, h) |> ignore
      // (where glass is drawn solid, what it shows bare, as a switch's knob is its knob then)
      let lens = match glass {
        Some(g) if !c.glass_solid() => Some(g)
        _ => None
      }
      c.layer(fn() {
        c.box(style=lens_capsule(w, h).then(@ui.style(shadow=shade)), glass?=lens, fn() {  }) |> ignore
      })
      |> ignore
    })
    c.look(at, @ui.look(alpha=full, scale=1.0 + (knob_lens_grow - 1.0) * held))
  })
  |> ignore
}

///|
/// How much larger the loupe shows what is under the finger, its size, how far over the finger its middle is, and how
/// far in from the window's sides it stays; how much larger a knob's lens grows as it comes (a switch's, the loupe's).
pub let loupe_zoom : Double = 1.35

///|
pub let loupe_w : Double = 124.0

///|
pub let loupe_h : Double = 48.0

///|
pub let loupe_lift : Double = 92.0

///|
let loupe_side : Double = 8.0

///|
pub let knob_lens_grow : Double = 1.25

///|
/// How a thing a finger moves follows it (the bar's ball: 300, damped as the web's, ZETA 0.635).
// kept across runs: a value (no field of it changes)
pub let follow_spring : @motion.Spec = @motion.lift_spring

///|
/// How much longer a thing a finger moves is drawn toward where it goes, and how much lower, by `v` (its way a frame
/// at 60): the bar's ball's (a frame's way times 1.6, at most 36; a fifth of that off its height, at most 6).
pub fn speed_stretch(v : Double) -> (Double, Double) {
  let longer = dmin(stretch_most, v.abs() * stretch_by)
  (longer, dmin(lower_most, longer * lower_by))
}

///|
let stretch_by : Double = 1.6

///|
let stretch_most : Double = 36.0

///|
let lower_by : Double = 0.2

///|
let lower_most : Double = 6.0
