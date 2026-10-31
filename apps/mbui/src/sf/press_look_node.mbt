// A press's ripple and sink on a node of the window's tree (@motion.ripple's, Android's `clickable`'s, as nodes): a
// soft disc from where the finger or the button went down, drifting to the node's middle as it grows, its way in over
// ripple_enter_ms from that moment, on to gone over ripple_exit_ms once it is let go and its way in is over (a short
// press shown whole); while it is down, a node standing on a ground of its own sunk a little, springing back as it is
// let go. Each a motion's way from its cause's moment (there at once with motion reduced), drawn as each frame is
// while it goes, let go with the node.

///|
/// One press's ripple: where in the node it went down, its way, when it went down, when it was let go (none yet).
priv struct PressRipple {
  x : Double
  y : Double
  /// how big the node was said to be as it went down (what its disc's size and drift are worked out by)
  w : Double
  h : Double
  way : @motion.Way
  at : Double
  mut lifted : Double?
  /// what is due for it (its way out set off, it let go), let go as it is
  due : Array[() -> Unit]
}

///|
/// A press's ripple and sink over node `v`, as big as `size` says (what its own width and height are said by, as
/// the press is: nothing read back of its layout), its corners
/// `corner`, the disc in `ink` (black at .1 by default, @motion.ripple_ink); sunk while pressed where `grounded` (a
/// ground of its own). What its gesture's press is told (View::gesture's `press`): the press's where and when. Its
/// letting go is the node's (View::pressed).
fn press_look(
  v : @view.View,
  size : () -> (Double, Double),
  corner : @view.Live[Double],
  grounded : () -> Bool,
  ink? : Int64 = @motion.ripple_ink,
) -> (@view.Drag) -> Unit {
  // (the ripples going, by their numbers, in the order they began)
  let ripples : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let made : Map[Int, PressRipple] = Map([])
  let next = Ref(0)
  // (sunk while down, back as it is let go, from where it is then; how far, by how big it is as it goes down)
  let sink = @motion.Way::new(0.0)
  let sink_most = Ref(0.0)
  v.scale(By(fn() {
    sink.said()
    let s = if sink.goes_at(v.logic_at()) { sink.value_at(v.drawn_at()) } else { sink.target() }
    1.0 - sink_most.val * s
  }))
  |> ignore
  // (let go: each ripple not yet let go on its way out once its way in is over; the sink back)
  v.reacts(fn() { v.pressed() }, fn(down) {
    let at = v.cause_at()
    if down {
      if @signals.untracked(grounded) {
        let (bw, bh) = @signals.untracked(size)
        sink_most.val = dmin(press_sink_most, @motion.press_sink / dmax(dmax(bw, bh), 1.0))
        sink.go(1.0, @motion.lift_spring, at~)
      }
      return
    }
    sink.go(0.0, @motion.lift_spring, at~)
    for n in @signals.untracked(fn() { ripples.get() }) {
      guard made.get(n) is Some(r) else { continue }
      if r.lifted is None {
        r.lifted = Some(at)
        let out_at = dmax(at, r.at + @motion.ripple_enter_ms)
        r.due.push(
          v.at_moment(out_at, fn() {
            r.way.go(1.0, @motion.tween(@motion.ripple_exit_ms, ease=Linear), at=out_at)
            r.due.push(
              v.at_moment(r.way.end(), fn() {
                made.remove(n)
                ripples.set(@signals.untracked(fn() { ripples.get() }).filter(fn(o) { o != n }))
              }),
            )
          }),
        )
      }
    }
  })
  // (the discs, over what it holds, cut to its corners)
  v.box(fn(over) {
    over.over(Is(true)).radius(corner).clips(Is(true)) |> ignore
    over.each(fn() { ripples.get() }, fn(n) { n }, fn(d, n) {
      match made.get(@signals.untracked(fn() { n.get() })) {
        Some(r) => ripple_disc(d, r, ink)
        None => ()
      }
    })
  })
  |> ignore
  v.owns(fn() {
    for _, r in made {
      for f in r.due {
        f()
      }
    }
  })
  |> ignore
  fn(d) {
    let way = @motion.Way::new(0.0)
    way.go(0.5, @motion.tween(@motion.ripple_enter_ms, ease=Out), at=d.at)
    let n = next.val
    next.val = n + 1
    let (w, h) = @signals.untracked(size)
    made[n] = { x: d.x, y: d.y, w, h, way, at: d.at, lifted: None, due: [] }
    let now = @signals.untracked(fn() { ripples.get() }).copy()
    now.push(n)
    ripples.set(now)
  }
}

///|
/// How far a node under a press sinks at most, a share of it (@motion.ripple's).
let press_sink_most : Double = 0.04

///|
/// One ripple's disc in `d` (over what it ripples, as big as `r` says it was as it went down): its progress as the
/// ripple's way has it as each frame is drawn while it goes; its alpha the ink's from .13 of the way and fading from .4;
/// its radius 2.3 times that half diagonal and 10 more, times the progress; from where it went down to the middle by .5; blurred by .27
/// of its radius (@motion.ripple's).
fn ripple_disc(d : @view.View, r : PressRipple, ink : Int64) -> Unit {
  let p = fn() {
    r.way.said()
    if r.way.goes_at(d.logic_at()) {
      r.way.value_at(d.drawn_at())
    } else {
      r.way.target()
    }
  }
  let geom = fn() {
    let (w, h) = (r.w, r.h)
    let most = ((w * w + h * h).sqrt() / 2.0 + 10.0) * 2.3
    let k = p()
    let radius = most * k
    let t = dmin(1.0, k * 2.0)
    let cx = r.x + (w / 2.0 - r.x) * t
    let cy = r.y + (h / 2.0 - r.y) * t
    (cx, cy, radius, k)
  }
  d
  .over(Is(true))
  .offset(By(fn() {
    let (cx, cy, radius, _) = geom()
    (cx - radius, cy - radius)
  }))
  .width(By(fn() { Some(geom().2 * 2.0) }))
  .height(By(fn() { Some(geom().2 * 2.0) }))
  .radius(By(fn() { geom().2 }))
  .shadow(By(fn() {
    let (_, _, radius, k) = geom()
    let sub = fn(a : Double, b : Double) { (dmin(dmax(k, a), b) - a) / (b - a) }
    let fade = dmin(sub(0.0, 0.13), 1.0 - sub(0.4, 1.0))
    let alpha = ((ink & 0xFFL).to_double() * dmax(fade, 0.0)).round().to_int64()
    (radius * 0.27, 0.0, (ink & 0xFFFFFF00L) | alpha)
  }))
  |> ignore
}
