// A hold handed through (View::gesture's `through`): a cover over a node that takes a hold, each as it goes.

///|
let through_ms : Double = 500.0

///|
let through_slop : Double = 6.0

///|
/// Moments of a step after the finger went down, before the hold's (soon, later) and after it (past).
let soon_ms : Double = 50.0

///|
let later_ms : Double = 100.0

///|
let past_ms : Double = 200.0

///|
/// A step of a finger on the window, at its moment: down, moved, up at (x, y); or the tree brought to a moment.
priv enum Step {
  Down(Double, Double, Double)
  Move(Double, Double, Double)
  Up(Double, Double, Double)
  To(Double)
  // at its moment, as one change: the cover gone, what is under it made anew in its place
  CoverGone(Double)
  UnderAnew(Double)
}

///|
/// A node taking a hold (as gesture says, held through_ms) and over it a cover holding through to it; `off_drops`: the
/// cover told it is called off lets go of what is under it. What each is told, in order, as `steps` go, frames drawn
/// at `frames` between (none: a jump each step).
fn through_said(
  steps : Array[Step],
  off_drops? : Bool = false,
  frames? : Double = 0.0,
  under_hold? : Double = through_ms,
) -> Array[String] {
  let said : Array[String] = []
  let under_on = @signals.signal(true, same=fn(a, b) { a == b })
  let cover_on = @signals.signal(true, same=fn(a, b) { a == b })
  let made = Ref(0)
  let t = @view.Tree::new(
    fn(top) {
      top
      .box(fn(root) {
      root.width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      root.show(fn() { under_on.get() }, fn(v) {
        made.val = made.val + 1
        let name = "under\{made.val}"
        v.over(Is(true)) |> ignore
        v.box(fn(b) {
          b
          .over(Is(true))
          .gesture(
            through_slop,
            press=fn(d) { said.push("\{name} press at \{d.at} since \{d.since}") },
            hold=(under_hold, fn(d) { said.push("\{name} held at \{d.at}") }),
            tap=fn(_) { said.push("\{name} tap") },
            drag=fn(d) { said.push("\{name} drag \{d.kind}") },
          )
          |> ignore
        })
        |> ignore
      })
      root.show(fn() { cover_on.get() }, fn(v) {
        v.over(Is(true)) |> ignore
        v.box(fn(b) {
          b
          .over(Is(true))
          .gesture(
            through_slop,
            press=fn(_) { said.push("cover press") },
            tap=fn(_) { said.push("cover tap") },
            through=through_ms,
            drag=fn(d) {
              said.push("cover drag \{d.kind}")
              if off_drops && d.kind == Off {
                under_on.set(false)
              }
            },
          )
          |> ignore
        })
        |> ignore
      })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let now = Ref(0.0)
  let go = fn(at : Double) {
    if frames > 0.0 {
      let mut f = now.val + frames
      while f < at {
        t.frame(390.0, 844.0, now=f) |> ignore
        f = f + frames
      }
    }
    now.val = at
  }
  let held = fn() {
    match t.holder() {
      Some(h) => h
      None => abort("held by none")
    }
  }
  for s in steps {
    match s {
      Down(x, y, at) => {
        go(at)
        match t.target_at(x, y) {
          Dragged(id) => t.drag_at(id, Down, x, y, at) |> ignore
          other => abort("no cover: \{other is Nothing} \{t.drawn().map(fn(d) { (d.id.at, d.x, d.y, d.w, d.h) })}")
        }
      }
      Move(x, y, at) => {
        go(at)
        if t.holder() is Some(_) {
          t.drag_at(held(), Moved, x, y, at) |> ignore
        }
      }
      Up(x, y, at) => {
        go(at)
        if t.holder() is Some(_) {
          t.drag_at(held(), Up, x, y, at) |> ignore
        }
      }
      To(at) => {
        go(at)
        t.bring_to(at)
      }
      CoverGone(at) => {
        go(at)
        t.event(at, fn() { cover_on.set(false) })
      }
      UnderAnew(at) => {
        go(at)
        // (let go, then another made in its place: two changes, at that moment)
        t.event(at, fn() { under_on.set(false) })
        t.event(at, fn() { under_on.set(true) })
      }
    }
  }
  said
}

///|
test "a cover holding through, tapped: its tap; what is under it told nothing" {
  assert_eq(through_said([Down(10.0, 10.0, 0.0), Up(10.0, 10.0, soon_ms), To(through_ms + later_ms)]), [
    "cover press", "cover tap",
  ])
}

///|
test "a cover holding through, dragged across before the hold: its drag; what is under it told nothing, at the hold's moment either" {
  assert_eq(
    through_said([
      Down(10.0, 10.0, 0.0),
      Move(40.0, 10.0, soon_ms),
      To(through_ms + later_ms),
      Up(40.0, 10.0, through_ms + past_ms),
    ]),
    ["cover press", "cover drag Down", "cover drag Up"],
  )
}

///|
test "a cover holding through, held still: at the hold's moment its hold called off (Off, no tap, no up), then what is under it pressed then, held as long as since the finger went down; let go, its" {
  let want = [
    "cover press",
    "cover drag Off",
    "under1 press at \{through_ms} since 0",
    "under1 held at \{through_ms}",
    "under1 drag Up",
  ]
  let steps = [Down(10.0, 10.0, 0.0), Move(12.0, 11.0, later_ms), To(through_ms + later_ms), Up(12.0, 11.0, through_ms + past_ms)]
  assert_eq(through_said(steps), want)
  // (frames drawn between or not: the same)
  assert_eq(through_said(steps, frames=16.0), want, msg="frames between")
  assert_eq(through_said(steps, frames=through_ms / 3.0), want, msg="few frames between")
}

///|
test "a cover holding through, moved past the slop just before the hold's moment: its drag, nothing handed" {
  assert_eq(
    through_said([
      Down(10.0, 10.0, 0.0),
      Move(10.0 + through_slop + 1.0, 10.0, through_ms - 1.0),
      To(through_ms + later_ms),
      Up(10.0 + through_slop + 1.0, 10.0, through_ms + past_ms),
    ]),
    ["cover press", "cover drag Down", "cover drag Up"],
  )
}

///|
test "a cover holding through let go of before the hold's moment: nothing handed to what is under it" {
  let said = through_said([Down(10.0, 10.0, 0.0), CoverGone(later_ms), To(through_ms + later_ms)])
  assert_false(said.iter().any(fn(s) { s.has_prefix("under") }), msg="\{said}")
}

///|
test "what is under a cover holding through made anew in its place before the hold's moment: neither the one found nor the new handed it" {
  let said = through_said([Down(10.0, 10.0, 0.0), UnderAnew(later_ms), To(through_ms + later_ms)])
  assert_false(said.iter().any(fn(s) { s.has_prefix("under") }), msg="\{said}")
}

///|
test "a cover holding through whose being called off lets go of what is under it: nothing handed" {
  let said = through_said([Down(10.0, 10.0, 0.0), To(through_ms + later_ms)], off_drops=true)
  assert_eq(said, ["cover press", "cover drag Off"])
}

///|
/// A hold shorter than the cover's, of what is under it.
let under_short_ms : Double = 300.0

///|
test "what is under a cover holding through held sooner than the cover hands it on: held as it is handed, at that moment, not before" {
  assert_eq(
    through_said([Down(10.0, 10.0, 0.0), To(through_ms + later_ms), Up(10.0, 10.0, through_ms + past_ms)], under_hold=under_short_ms),
    [
      "cover press",
      "cover drag Off",
      "under1 press at \{through_ms} since 0",
      "under1 held at \{through_ms}",
      "under1 drag Up",
    ],
  )
}
