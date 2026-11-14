// An old view's list on Android as a phone draws it (390 by 844, 2.75 pixels a point), dragged up by a finger whose
// moves come 8 ms apart, each at its own time, then let go: flung on as a page's list of the window's tree is (view's
// scroll_let_go_test.mbt), at how fast the finger went as of its last move; resting there first, not flung.

///|
/// Long after any fling is at rest.
let old_let_go_rest_ms : Double = 20000.0

///|
/// The list dragged from 700 up a point and a half a ms for 96 ms, a move each 8 ms; then `rests` moves 8 ms apart
/// saying where it got to again (resting there); then let go there `lag` ms after its last move: where the list was let
/// go, and where it comes to rest.
fn old_let_go(lag : Double, rests? : Int = 0) -> (Double, Double) {
  let t = @ui.Tester::new(
    fn(c) {
      c.list("list", 300, 60.0, fn(i) {
        c.box(w=Fill(1.0), h=Px(60.0), fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    },
    platform=2,
    scale=2.75,
  )
  let t0 = t.time() + 16.0
  let at = fn(ms : Double, kind : Int, y : Double) {
    if t.time() < t0 + ms {
      t.advance(t0 + ms - t.time())
    }
    t.touch_at(kind, 195.0, y, t0 + ms)
  }
  at(0.0, 0, 700.0)
  for i in 1..=12 {
    at(8.0 * i.to_double(), 1, 700.0 - 12.0 * i.to_double())
  }
  let mut ms = 96.0
  for _ in 0..<rests {
    ms = ms + 8.0
    at(ms, 1, 556.0)
  }
  at(ms + lag, 2, 556.0)
  t.draw()
  let left = t.list_offset()
  t.run_for(old_let_go_rest_ms)
  (left, t.list_offset())
}

///|
test "an old view's list on Android, a phone's: a finger going steadily, let go 8 ms after its last move: flung on as far as let go at its moment; resting 48 ms first, its moves saying where it got to again: where it was let go, never back" {
  let at_once = old_let_go(0.0)
  assert_eq(old_let_go(8.0), at_once)
  assert_true(at_once.1 > at_once.0, msg="\{at_once.0} \{at_once.1}")
  let (left, rest) = old_let_go(1.0, rests=6)
  assert_eq(rest, left)
}
