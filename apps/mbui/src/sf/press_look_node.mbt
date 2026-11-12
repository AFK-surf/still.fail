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
/// What a press's look is told by its gesture: its press as it goes down (View::gesture's `press`), and a tap
/// (`tap`'s), which shows a press a finger let go before it showed.
priv struct PressLook {
  down : (@view.Drag) -> Unit
  tapped : (@view.Drag) -> Unit
}

///|
/// A press's ripple and sink over node `v`, as big as the press says it is laid out as it goes down (Drag's `w`, `h`:
/// nothing read back of its layout), its corners
/// `corner`, the disc in `ink` as it is now (black at .1 by default, @motion.ripple_ink; a theme's, followed as it changes); sunk while pressed where `grounded` (a
/// ground of its own). Told the press's where, when and how big it is then; its letting go is the node's
/// (View::pressed). A finger's press in what scrolls shows once it has stayed tap_indication_ms (Ctx::pressed's, Compose's
/// clickable in a scrollable container): one that goes on to scroll shows nothing; a tap quicker than that shows
/// as it is let go.
#callsite(autofill(loc))
fn press_look(
  v : @view.View,
  corner : @view.Live[Double],
  grounded : () -> Bool,
  ink? : () -> Int64 = fn() { @motion.ripple_ink },
  loc~ : SourceLoc,
) -> PressLook {
  // (the ripples going, by their numbers, in the order they began)
  let ripples : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let made : Map[Int, PressRipple] = Map([])
  let next = Ref(0)
  // (a finger's press in what scrolls not shown yet, and its showing, due)
  let late : Ref[@view.Drag?] = Ref(None)
  let late_due : Ref[() -> Unit] = Ref(fn() {  })
  // (sunk while down, back as it is let go, from where it is then; how far, by how big it is as it goes down)
  let sink = @motion.Way::new(0.0)
  let sink_most = Ref(0.0)
  v.scale(By(fn() {
    let s = sink.shown_on(v)
    1.0 - sink_most.val * s
  }))
  |> ignore
  // (let go at `at`: each ripple not yet let go on its way out once its way in is over; the sink back)
  let lift = fn(at : Double) {
    sink.go(0.0, @motion.lift_spring, at~)
    for n in ripples.untracked() {
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
                ripples.set(ripples.untracked().filter(fn(o) { o != n }))
              }),
            )
          }),
        )
      }
    }
  }
  v.reacts(fn() { v.pressed() }, fn(down) {
    // (sunk as the press goes down, by how big it is then: the press's own)
    if down {
      return
    }
    // (not shown yet: shown now only by a tap, told as it is let go)
    (late_due.val)()
    late_due.val = fn() {  }
    lift(v.cause_at())
  })
  // (the discs, over what it holds, cut to its corners: made as its first press shows, nothing of them before; a row or
  // a key that is never pressed holds none; over what it holds, no room of the column's to come into: at once)
  let pressed_once : @signals.Signal[Bool] = @signals.signal(false)
  v.show(fn() { pressed_once.get() }, at_once=true, fn(over) {
    over.made_for(loc).over(Is(true)).radius(corner).clips(Is(true)) |> ignore
    over.each(fn() { ripples.get() }, fn(n) { n }, fn(d, n) {
      match made.get(n.untracked()) {
        Some(r) => ripple_disc(d, r, ink)
        None => ()
      }
    })
  })
  v.owns(fn() {
    (late_due.val)()
    for _, r in made {
      for f in r.due {
        f()
      }
    }
  })
  |> ignore
  // (press `d` shown from `at`)
  let show = fn(d : @view.Drag, at : Double) {
    if @signals.untracked(grounded) {
      sink_most.val = dmin(press_sink_most, @motion.press_sink / dmax(dmax(d.w, d.h), 1.0))
      sink.go(1.0, @motion.lift_spring, at~)
    }
    let way = @motion.Way::new(0.0)
    way.go(0.5, @motion.tween(@motion.ripple_enter_ms, ease=Out), at~)
    let n = next.val
    next.val = n + 1
    made[n] = { x: d.x, y: d.y, w: d.w, h: d.h, way, at, lifted: None, due: [] }
    pressed_once.set(true)
    let now = ripples.untracked().copy()
    now.push(n)
    ripples.set(now)
  }
  {
    down: fn(d) {
      (late_due.val)()
      late_due.val = fn() {  }
      late.val = None
      if @ui.pointing() is Finger && v.scroll_holding() is Some(_) {
        late.val = Some(d)
        let due = d.at + @ui.tap_indication_ms
        late_due.val = v.at_moment(due, fn() {
          late.val = None
          late_due.val = fn() {  }
          show(d, due)
        })
      } else {
        show(d, d.at)
      }
    },
    tapped: fn(t) {
      guard late.val is Some(d) else { return }
      late.val = None
      (late_due.val)()
      late_due.val = fn() {  }
      show(d, t.at)
      // (let go already: on its way out as its way in ends)
      if !@signals.untracked(fn() { v.pressed() }) {
        lift(t.at)
      }
    },
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
fn ripple_disc(d : @view.View, r : PressRipple, ink_now : () -> Int64) -> Unit {
  let p = fn() {
    r.way.shown_on(d)
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
  // (laid out once, as nothing: as big as it goes drawn so, its ground's, not laid out again each frame it grows)
  .width(Is(Some(0.0)))
  .height(Is(Some(0.0)))
  .ground_drawn(By(fn() {
    let radius = geom().2
    { dx: 0.0, dy: 0.0, dw: radius * 2.0, dh: radius * 2.0, corners: Some((radius, radius, radius, radius)) }
  }))
  .radius(By(fn() { geom().2 }))
  .shadow(By(fn() {
    let (_, _, radius, k) = geom()
    let sub = fn(a : Double, b : Double) { (dmin(dmax(k, a), b) - a) / (b - a) }
    let fade = dmin(sub(0.0, 0.13), 1.0 - sub(0.4, 1.0))
    let ink = ink_now()
    let alpha = ((ink & 0xFFL).to_double() * dmax(fade, 0.0)).round().to_int64()
    (radius * 0.27, 0.0, (ink & 0xFFFFFF00L) | alpha)
  }))
  |> ignore
}
