// What run_for declares is the moment it ends at, to the bit: from where the clock was, the length added once, at
// every rate of frames on the way (MBUI_TEST_FPS) and on none. So a moment the app works out as a start and a length
// (a mark and how long it holds: Ctx::within, a typeahead's second) is the test's moment too: neither a frame of the
// display's a few last bits past it (it came out so on main, 2016.6666666666667 for 1016.6666666666666 + 1000, and a
// test of a menu's typeahead passed by that alone) nor one short of it.

///|
/// Lengths a test runs for: whole frames of 60 a second and parts of one, a second, a rate's frame (1000 over 7), a
/// length of no grid's.
let run_end_lengths : Array[Double] = [
  1000.0,
  1000.0 / 60.0,
  2.5 * (1000.0 / 60.0),
  50.0,
  1000.0 / 7.0,
  1000.0 / 24.0 * 5.0,
  333.3,
  0.7,
]

///|
/// Each length run from each of a few starts (a Tester's first frame, then where the lengths before left it, a frame
/// on the grid or between two): where the clock came to otherwise than the start and the length added.
fn run_end_apart(nodes : Bool) -> Array[String] {
  let t = if nodes {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    set_view_app(fn(root) { root.box(fn(b) { b.words(Is("x")) |> ignore }) |> ignore })
    t.draw()
    t
  } else {
    Tester::new(fn(c) { c.text("x", wrap=false) |> ignore }, w=200.0, h=200.0)
  }
  t.draw()
  let out = []
  for _ in 0..<3 {
    for d in run_end_lengths {
      let start = t.time()
      t.run_for(d)
      let end = start + d
      if t.time().reinterpret_as_int64() != end.reinterpret_as_int64() {
        out.push("from \{start} for \{d}: at \{t.time()}, not \{end}")
      }
    }
  }
  out
}

///|
test "run_for ends at its start and length added, to the bit, from any start, at any rate" {
  assert_eq(run_end_apart(false), [])
  assert_eq(run_end_apart(true), [])
}
