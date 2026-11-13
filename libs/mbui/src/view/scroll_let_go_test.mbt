// A page's list on Android as a phone draws it (390 by 844, 2.75 pixels a point), dragged up by a finger whose moves
// come 8 ms apart (a touch screen read at 120 Hz, each move at its own time), then let go: flung on at how fast the
// finger went as of its last move, the lift's own place (the last place said again) no move of it; not at all where it
// stood still longer than tracker_gap_ms first, nor at a speed its own way over its last moves does not bear out
// (track.mbt).

///|
/// When the finger goes down on a test's clock, how far apart its moves come, and a moment long after any fling is at
/// rest.
let let_go_down_at : Double = 1000.0

///|
let let_go_step_ms : Double = 8.0

///|
let let_go_rest_at : Double = 30000.0

///|
/// The list dragged from 700 by a finger `along(τ)` points up `τ` ms after it went down, a move each let_go_step_ms
/// for 96 ms; then the moves `after`, each `dt` ms after the one before, `back` points below where it got to (0: that
/// place said again, a finger resting there); then let go where the last move was, `lag` ms after it: where the list
/// was let go, and where it comes to rest. `across`: a row of cells 60 wide instead, dragged left from 350 so.
fn let_go_list(
  along : (Double) -> Double,
  lag : Double,
  after? : Array[(Double, Double)] = [],
  across? : Bool = false,
) -> (Double, Double) {
  let scroll = if across { @view.Scroll::across() } else { @view.Scroll::list() }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o
      .width(Is(Some(390.0)))
      .height(Is(Some(844.0)))
      .scrolls(scroll, fn(held) {
        held.row(Is(across)) |> ignore
        for _ in 0..<300 {
          held.box(fn(r) {
            r
            .width(Is(Some(if across { 60.0 } else { 390.0 })))
            .height(Is(Some(if across { 844.0 } else { 60.0 })))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (@view.ListFeel::Android, 2.75) })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let from = if across { 350.0 } else { 700.0 }
  // (where the finger is, `p` along the way it goes)
  let x = fn(p : Double) { if across { p } else { 195.0 } }
  let y = fn(p : Double) { if across { 400.0 } else { p } }
  let id = (if across {
      tree.claimer_of(tree.claimers_at(from, 400.0), -20.0, 0.0)
    } else {
      tree.claimer_of(tree.claimers_at(195.0, from), 0.0, -20.0)
    }).unwrap()
  tree.drag_at(id, Down, x(from), y(from), let_go_down_at) |> ignore
  let mut t = let_go_down_at
  for i in 1..=12 {
    t = let_go_down_at + let_go_step_ms * i.to_double()
    let p = from - along(t - let_go_down_at)
    tree.drag_at(id, Moved, x(p), y(p), t) |> ignore
  }
  let got = from - along(t - let_go_down_at)
  let mut p = got
  for m in after {
    let (dt, back) = m
    t = t + dt
    p = got + back
    tree.drag_at(id, Moved, x(p), y(p), t) |> ignore
  }
  tree.drag_at(id, Up, x(p), y(p), t + lag) |> ignore
  let left = scroll.at(tree)
  tree.advance(let_go_rest_at)
  (left, scroll.at(tree))
}

///|
/// A finger slowing as it goes: 2 points a ms as it sets out, a tenth of one by its last move.
fn let_go_slowing(tau : Double) -> Double {
  2.0 * tau - 1.9 / 192.0 * tau * tau
}

///|
/// A finger going steadily, a point and a half a ms.
fn let_go_steady(tau : Double) -> Double {
  1.5 * tau
}

///|
/// `n` moves let_go_step_ms apart saying where the finger got to again: resting there.
fn let_go_resting(n : Int) -> Array[(Double, Double)] {
  Array::make(n, (let_go_step_ms, 0.0))
}

///|
test "a page's list on Android, a phone's: a finger slowing to its last move, let go there 16, 24 or 32 ms after it: flung on as far as let go at that move's moment, the way it went, never back" {
  let (left, at_once) = let_go_list(let_go_slowing, 0.0)
  let later = [16.0, 24.0, 32.0].map(fn(lag) { let_go_list(let_go_slowing, lag) })
  assert_eq(later, [(left, at_once), (left, at_once), (left, at_once)])
  assert_true(at_once > left, msg="\{left} \{at_once}")
}

///|
test "a page's list on Android, a phone's: a finger going steadily, let go 8 or 40 ms after its last move: flung on as far as let go at its moment; 60 ms after (it stood still first): where it was let go" {
  let at_once = let_go_list(let_go_steady, 0.0)
  assert_eq([let_go_list(let_go_steady, 8.0), let_go_list(let_go_steady, 40.0)], [at_once, at_once])
  let (left, rest) = let_go_list(let_go_steady, 60.0)
  assert_eq(rest, left)
  assert_true(at_once.1 > at_once.0, msg="\{at_once.0} \{at_once.1}")
}

///|
test "a page's list on Android, a phone's: a finger resting where it got to, its moves saying that place again, then let go: on less far the longer it rested, the way it went; rested 40 or 48 ms, or slowing as it came, or wavering a little as it rests, where it was let go, never back" {
  let rested = [1, 2, 3].map(fn(r) { let_go_list(let_go_steady, 1.0, after=let_go_resting(r)) })
  let (left, _) = rested[0]
  assert_true(
    rested[0].1 > rested[1].1 && rested[1].1 > rested[2].1 && rested[2].1 > left,
    msg="\{left} \{rested[0].1} \{rested[1].1} \{rested[2].1}",
  )
  for r in [5, 6] {
    let (l, rest) = let_go_list(let_go_steady, 1.0, after=let_go_resting(r))
    assert_eq(rest, l, msg="resting \{r * 8}")
  }
  for r in [1, 2, 3, 4, 6] {
    let (l, rest) = let_go_list(let_go_slowing, 1.0, after=let_go_resting(r))
    assert_eq(rest, l, msg="slowing, resting \{r * 8}")
  }
  // (a third of a point either way and back as it rests: the last of it a tenth back)
  let wavering = [-0.3, 0.3, -0.2, 0.1, -0.3, 0.3, -0.2, 0.1].map(fn(b) { (let_go_step_ms, b) })
  let (l, rest) = let_go_list(let_go_steady, 1.0, after=wavering)
  assert_eq(rest, l)
}

///|
/// A finger going up a point and a half a ms, turned back `ago` ms before its last move, down a point a ms since.
fn let_go_turned(ago : Double) -> (Double) -> Double {
  let k = 96.0 - ago
  fn(tau) { if tau <= k { 1.5 * tau } else { 1.5 * k - (tau - k) } }
}

///|
test "a page's list on Android, a phone's: a finger turned back over its last 40 ms, let go: flung back, the way it went last; turned back over its last 16 only: where it was let go, not flung the first way; a third of a point back as a fling is let go: flung on" {
  let (left, rest) = let_go_list(let_go_turned(40.0), 0.0)
  assert_true(rest < left, msg="\{left} \{rest}")
  let (left, rest) = let_go_list(let_go_turned(16.0), 0.0)
  assert_eq(rest, left)
  let (left, rest) = let_go_list(let_go_steady, 1.0, after=[(1.0, 0.3)])
  assert_true(rest > left, msg="\{left} \{rest}")
}

///|
test "a row of cells, a phone's, dragged across: let go 8 ms after a steady last move, flung on as far as let go at its moment; resting there 48 ms first, or slowing as it came, its moves saying its place again, or turned back over its last 16 ms: where it was let go; turned back over its last 40: flung back" {
  let at_once = let_go_list(let_go_steady, 0.0, across=true)
  assert_eq(let_go_list(let_go_steady, 8.0, across=true), at_once)
  assert_true(at_once.1 > at_once.0, msg="\{at_once.0} \{at_once.1}")
  let (left, rest) = let_go_list(let_go_steady, 1.0, after=let_go_resting(6), across=true)
  assert_eq(rest, left)
  let (left, rest) = let_go_list(let_go_slowing, 1.0, after=let_go_resting(2), across=true)
  assert_eq(rest, left)
  let (left, rest) = let_go_list(let_go_turned(16.0), 0.0, across=true)
  assert_eq(rest, left)
  let (left, rest) = let_go_list(let_go_turned(40.0), 0.0, across=true)
  assert_true(rest < left, msg="\{left} \{rest}")
}
