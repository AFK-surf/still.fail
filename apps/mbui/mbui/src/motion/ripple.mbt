// A press's ripple, as every Compose `clickable` on Android 12 and later draws it: Material 3's ripple() is Android's
// RippleDrawable, which is always its patterned style there (RippleDrawable FORCE_PATTERNED_STYLE; RippleAnimationSession,
// RippleShader). A soft disc of the content's colour (Compose's LocalContentColor: black unless said) at Material 3's
// pressed alpha (.1), from where the finger went down, drifting to the box's middle as it grows: its progress goes to .5
// over 450 ms (FastOutSlowIn) as the finger goes down, then on to 1 over 375 ms (linear) once it lifts and that way in
// is over (a tap however short shown whole first). The disc is at its alpha by progress .13 and fades from .4 to 1; its
// radius is 2.3 times the box's half diagonal and 10 more (Compose's bounded ripple, RippleShader.setRadius) times the
// progress, its edge soft from half that radius to half again (softCircle, blur 1: drawn here as the disc blurred, its
// middle where the edge's is). Its sparkles (white specks in the growing ring, on the clock's noise) are not drawn.
// While a finger is on it, the box it ripples sinks a little (drawn smaller about its middle, by a few points however
// large it is: press_sink), and springs back as it lifts (docs/motion.md kind 7, a control answering: pressed): a box
// that stands on a ground of its own (a button, a card: Ctx::own_ground), not a row lying in a list or a card, whose
// press is its ground lit (a row sunk in its card is drawn in from the card's edges, as if pressed out of it).

///|
/// One press's ripple: where in its box the finger went down, how far it has gone (RippleShader's progress), when it
/// went down and whether it has lifted.
priv struct Ripple {
  x : Double
  y : Double
  progress : Anim
  at : Double
  mut lifted : Bool
  /// when the finger lifted
  mut lifted_at : Double
  /// on its way out (from .5, its way in over)
  mut leaving : Bool
}

///|
/// The ripples going, by the id of what was pressed (put back by layer.mbt's reset: a test that ended with one going
/// left it to the next Tester's box of the same id, its Anim not at rest, screens_wbtest's home-sheet, 2026-10-24).
let ripples : Map[Int, Array[Ripple]] = {}

///|
/// How long a ripple takes to its middle as the finger goes down (RippleAnimationSession ENTER_ANIM_DURATION).
pub let ripple_enter_ms : Double = 450.0

///|
/// How long it takes from there to gone once the finger lifts (RippleAnimationSession EXIT_ANIM_DURATION).
pub let ripple_exit_ms : Double = 375.0

///|
/// How long a tap's ripple lasts, shown whole: its way in, then out.
pub let ripple_tap_ms : Double = ripple_enter_ms + ripple_exit_ms

///|
/// A ripple's colour: black at Material 3's pressed alpha (RippleDefaults: StateTokens.PressedStateLayerOpacity .1).
pub let ripple_ink : Int64 = 0x0000001AL

///|
/// How far past a box's half diagonal its ripple reaches (Compose's BoundedRippleExtraRadius, 10 dp).
let ripple_extra : Double = 10.0

///|
/// How soft a ripple's disc is, as a share of its radius: blurred so, its edge fades from about half its radius to
/// half again (RippleShader's softCircle, blur 1).
let ripple_soft : Double = 0.27

///|
/// How far below its disc a ripple's blur is put: not at all (the disc itself, not a shadow dropped under it).
let ripple_drop : Double = 0.0

///|
/// How far a box sinks under a finger: by so many points across its longer side, no more than so much of it (a
/// small button's).
pub let press_sink : Double = 4.0

///|
let press_sink_most : Double = 0.04

///|
/// The way down and back up: a spring with a little give.
// kept across runs: a value (no field of it changes)
let sink_spring : Spec = motion_spring(0.25, bounce=0.35)

///|
/// The share of `p` between `a` and `b` (RippleShader subProgress).
fn sub_progress(a : Double, b : Double, p : Double) -> Double {
  (clamp(a, b, p) - a) / (b - a)
}

///|
/// What is pressed as `id` rippled as Android's `clickable` ripples (see the file's head): drawn over what the box
/// holds, cut to its corners (`corner`), in `ink` (black at .1 by default). Called in the box's body, after what it
/// holds. `out_x`, `out_y`: its ground reaches that far past the box on each side (Controls.kt pressText: a text
/// button's ground round its words, laid out as the words alone), less than the box where they are below 0 (a card's
/// row clipped LIST_PAD in); `out_top`, `out_bottom` in place of `out_y` at that side. A press however short is shown
/// whole, a tap ended before the press shows in what scrolls too.
pub fn ripple(
  c : @ui.Ctx,
  id : Int,
  corner : Double,
  ink? : Int64 = ripple_ink,
  out_x? : Double = 0.0,
  out_y? : Double = 0.0,
  out_top? : Double,
  out_bottom? : Double,
) -> Unit {
  let top = out_top.unwrap_or(out_y)
  let bottom = out_bottom.unwrap_or(out_y)
  // (the box it is called in: what sinks)
  let holder = c.building()
  let list = match ripples.get(id) {
    Some(l) => l
    None => []
  }
  let down = c.pressed(id)
  // a finger down on it, or a tap let go before the press showed: a ripple from where it went down (watched: what
  // takes the press is what `id` is drawn for)
  if c.watch_press(id) && !list.iter().any(fn(r) { !r.lifted }) {
    let (px, py, _) = c.pointer()
    // (where it is laid this frame; a list's row, laid as the list is, after its build: where it was laid last)
    let (bx, by) = match c.laid_rect(id) {
      Some((x, y, _, _)) => (x, y)
      None =>
        match c.rect_of(id) {
          Some((x, y, _, _)) => (x, y)
          None => (px, py)
        }
    }
    let p = Anim::new(0.0)
    p.name = "ripple"
    p.animate(0.5, tween(ripple_enter_ms, ease=Standard))
    list.push({ x: px - bx + out_x, y: py - by + top, progress: p, at: c.moment(), lifted: false, lifted_at: 0.0, leaving: false })
    ripples[id] = list
  }
  // let go (or the press taken by a scroll): on to its end from where its way in ended, once that is over (the way
  // in's own end brings the frame that sees it)
  for r in list {
    if !down && !r.lifted {
      r.lifted = true
      r.lifted_at = c.moment()
    }
    let out_at = if r.lifted_at > r.at + ripple_enter_ms { r.lifted_at } else { r.at + ripple_enter_ms }
    if r.lifted && !r.leaving && c.moment() >= out_at {
      r.leaving = true
      r.progress.animate(1.0, tween(ripple_exit_ms, ease=Linear), start_at=out_at)
    }
  }
  // a finger on it (its ripple not let go): sunk a little, back as it lifts
  let on = list.iter().any(fn(r) { !r.lifted })
  // (none asked of what no finger has been on: nothing to keep for every box that ripples)
  let sink_key = "\u{2}sink/\{id}"
  let sunk = if c.own_ground(holder) && (on || anims.contains(c.id(sink_key))) {
    animate(c, sink_key, if on { 1.0 } else { 0.0 }, spec=sink_spring)
  } else {
    0.0
  }
  if sunk != 0.0 && c.own_ground(holder) {
    match c.laid_size(id) {
      Some((bw, bh)) if bw > 0.0 && bh > 0.0 => {
        let most = dmin(press_sink_most, press_sink / dmax(bw, bh))
        c.look(holder, @ui.look(scale=1.0 - most * sunk))
      }
      _ => ()
    }
  }
  if list.length() == 0 {
    return
  }
  // (laid out once at least: what it covers, its ground past it where it reaches out)
  guard c.laid_size(id) is Some((bw, bh)) else { return }
  let w = bw + 2.0 * out_x
  let h = bh + top + bottom
  let most = ((w * w + h * h).sqrt() / 2.0 + ripple_extra) * 2.3
  c.layer(fn() {
    c.box(w=Px(w), h=Px(h), tx=-out_x, ty=-top, clip=true, radius=corner, fn() {
      for r in list {
        let p = r.progress.get()
        let fade = sub_progress(0.0, 0.13, p).min(1.0 - sub_progress(0.4, 1.0, p))
        let radius = most * p
        if fade <= 0.0 || radius <= 0.0 {
          continue
        }
        // from the finger to the middle by progress .5
        let k = clamp(0.0, 1.0, p * 2.0)
        let cx = mix(r.x, w / 2.0, k)
        let cy = mix(r.y, h / 2.0, k)
        let alpha = ((ink & 0xFFL).to_double() * fade).round().to_int64()
        let colour = (ink & 0xFFFFFF00L) | alpha
        let across = radius * 2.0
        let blur = radius * ripple_soft
        c.layer(fn() {
          c.box(
            w=Px(across),
            h=Px(across),
            radius~,
            tx=cx - radius,
            ty=cy - radius,
            shadow=blur,
            shadow_y=ripple_drop,
            shadow_color=colour,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  // those faded away let go
  list.retain(fn(r) { !r.leaving || r.progress.get() < 1.0 })
  if list.length() == 0 {
    ripples.remove(id)
  }
}
