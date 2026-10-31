// A finger handed on for a move (View::gesture's `held_first`): a cover a finger drags only once held, over a node that
// takes a drag (or nothing that takes one); moved past the slop before the hold, the finger the node's under it from
// where it went down, the cover's press called off once.

///|
/// A finger's raw step on the window: down, moved, let go at (x, 100), at its moment (the tree brought there first, as
/// a host brings it before it hands an event on); or the tree brought to a moment.
priv enum Hand {
  Put(Double, Double)
  Shift(Double, Double)
  Lift(Double, Double)
  Until(Double)
}

///|
/// What the cover (dragged only once held, `held_first` saying so of every press) and what is under it (a node taking
/// a drag, `under`; or nothing) are told, in order, as `steps` go; frames each `frames` between (none: 0).
fn moved_said(steps : Array[Hand], under? : Bool = true, held_first? : Bool = true, frames? : Double = 0.0) -> Array[
  String,
] {
  let said : Array[String] = []
  let t = @view.Tree::new(
    fn(top) {
      top
      .box(fn(root) {
        root.width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
        if under {
          root.box(fn(u) {
            u
            .over(Is(true))
            .gesture(
              through_slop,
              press=fn(d) { said.push("under press at \{d.wx},\{d.wy} since \{d.since}") },
              hold=(through_ms, fn(_) { said.push("under held") }),
              tap=fn(_) { said.push("under tap") },
              drag=fn(d) { said.push("under drag \{d.kind} at \{d.wx} from \{d.ox}") },
            )
            |> ignore
          })
          |> ignore
        }
        root.box(fn(c) {
          c
          .over(Is(true))
          .gesture(
            through_slop,
            press=fn(_) { said.push("cover press") },
            tap=fn(_) { said.push("cover tap") },
            hold=(through_ms, fn(_) { said.push("cover held") }),
            drag=fn(d) { said.push("cover drag \{d.kind}") },
            held_first=fn(_) { held_first },
          )
          |> ignore
        })
        |> ignore
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
    t.bring_to(at)
  }
  for s in steps {
    match s {
      Put(x, at) => {
        go(at)
        match t.target_at(x, 100.0) {
          Dragged(id) => t.drag_at(id, Down, x, 100.0, at) |> ignore
          _ => abort("no cover")
        }
      }
      Shift(x, at) => {
        go(at)
        match t.holder() {
          Some(h) => t.drag_at(h, Moved, x, 100.0, at) |> ignore
          None => ()
        }
      }
      Lift(x, at) => {
        go(at)
        match t.holder() {
          Some(h) => t.drag_at(h, Up, x, 100.0, at) |> ignore
          None => ()
        }
      }
      Until(at) => go(at)
    }
  }
  go(through_ms * 2.0)
  said
}

///|
test "a cover dragged only once held, moved past the slop at once: called off once, the finger the node's under it from where it went down, frames or none" {
  let steps = [Put(100.0, 0.0), Shift(140.0, 10.0), Shift(160.0, 11.0), Lift(160.0, 12.0)]
  let want = [
    "cover press", "cover drag Off", "under press at 100,100 since 0", "under drag Down at 140 from 100", "under drag Moved at 160 from 100",
    "under drag Up at 160 from 100",
  ]
  assert_eq(moved_said(steps), want)
  assert_eq(moved_said(steps, frames=2.0), want)
}

///|
test "a cover dragged only once held, moved past the slop at once and let go with no other move: the node under it dragged and let go, no tap of either" {
  assert_eq(moved_said([Put(100.0, 0.0), Shift(140.0, 10.0), Lift(140.0, 10.0)]), [
    "cover press", "cover drag Off", "under press at 100,100 since 0", "under drag Down at 140 from 100", "under drag Up at 140 from 100",
  ])
}

///|
test "a cover dragged only once held, moved past the slop at once over nothing taking it: called off once, nothing more of it" {
  assert_eq(moved_said([Put(100.0, 0.0), Shift(140.0, 10.0), Shift(160.0, 11.0), Lift(160.0, 12.0)], under=false), [
    "cover press", "cover drag Off",
  ])
}

///|
test "a cover dragged only once held, let go far from where it went down with no move told, before the hold: called off, no drag, no tap of anything's" {
  assert_eq(moved_said([Put(100.0, 0.0), Lift(140.0, 12.0)]), ["cover press", "cover drag Off"])
  assert_eq(moved_said([Put(100.0, 0.0), Lift(140.0, 12.0)], under=false), ["cover press", "cover drag Off"])
}

///|
test "a cover dragged only once held, moved within the slop and let go: its tap" {
  assert_eq(moved_said([Put(100.0, 0.0), Shift(102.0, 10.0), Lift(102.0, 12.0)]), ["cover press", "cover tap"])
}

///|
test "a cover dragged only once held, held first: its hold, then its drag, as ever; one that drags at once (held_first no) as ever too" {
  assert_eq(moved_said([Put(100.0, 0.0), Until(through_ms + 10.0), Shift(140.0, through_ms + 20.0), Lift(140.0, through_ms + 30.0)]), [
    "cover press", "cover held", "cover drag Down", "cover drag Up",
  ])
  assert_eq(moved_said([Put(100.0, 0.0), Shift(140.0, 10.0), Lift(140.0, 12.0)], held_first=false), [
    "cover press", "cover drag Down", "cover drag Up",
  ])
  assert_eq(moved_said([Put(100.0, 0.0), Lift(140.0, 12.0)], held_first=false), ["cover press", "cover drag Up"])
}
