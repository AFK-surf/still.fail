// A page's list at rest with a row's edge exactly where it shows ends, and the wheel going back and forth over that
// edge by a point: the row past it made once as it first meets where the list shows and put by as it leaves, taken
// back as it comes again; at rest on the edge nothing made, taken or let go.

///|
/// A list 320 tall of 200 keys, rows 40 tall each (so the 9th's top is exactly at its foot at its top), each block of
/// one kind, reused, in a window 300 by 400: the Tester, and what its blocks did (made, given a key, let go), counted.
priv struct EdgeCase {
  t : Tester
  made : Ref[Int]
  given : Ref[Int]
  gone : Ref[Int]
}

///|
fn edge_case() -> EdgeCase {
  let made = Ref(0)
  let given = Ref(0)
  let gone = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(320.0))) |> ignore
      o.scrolls_window(
        @view.Scroll::list(),
        fn() { Array::makei(200, fn(i) { i }) },
        est=40.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) {
          made.val = made.val + 1
          b.owns(fn() { gone.val = gone.val + 1 }) |> ignore
          let shown = Ref(-1)
          b.box(fn(l) {
            l
            .height(Is(Some(40.0)))
            .words(By(fn() {
              let k = key()
              if shown.val != k {
                shown.val = k
                given.val = given.val + 1
              }
              "row \{k}"
            }))
            |> ignore
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  { t, made, given, gone }
}

///|
/// The rows drawn whole or in part where the list shows (its 320), top down.
fn edge_shown(c : EdgeCase) -> Array[String] {
  let ws = c.t.words().filter(fn(w) { w.0.has_prefix("row ") && w.2 + w.4 > 0.0 && w.2 < 320.0 })
  ws.sort_by(fn(a, b) { a.2.compare(b.2) })
  ws.map(fn(w) { w.0 })
}

///|
fn edge_counts(c : EdgeCase) -> (Int, Int, Int) {
  (c.made.val, c.given.val, c.gone.val)
}

///|
/// How long it is left at rest on the edge, and how far apart the wheel's turns over it come.
let edge_rest_ms : Double = 1000.0

///|
let edge_turn_ms : Double = 100.0

///|
test "a page's list at rest with a row's edge exactly at its foot, the wheel a point past it and back twenty times: the row past it made once, taken back each time it comes, nothing made or let go at rest on the edge" {
  let c = edge_case()
  let t0 = c.t.origin
  // (at rest on the edge: rows 0 to 7 shown, the 9th's top at the foot, not shown)
  c.t.run_for(edge_rest_ms)
  let at_rest = edge_shown(c)
  let first = edge_counts(c)
  c.t.run_for(edge_rest_ms)
  let still = edge_counts(c)
  // (a point down and back up, twenty times, each turn at its own moment)
  let from = c.t.time() - t0
  for i in 0..<20 {
    c.t.input_at(t0 + from + edge_turn_ms * (2 * i + 1).to_double())
    c.t.wheel(150.0, 100.0, 1.0)
    c.t.input_at(t0 + from + edge_turn_ms * (2 * i + 2).to_double())
    c.t.wheel(150.0, 100.0, -1.0)
  }
  c.t.run_for(edge_rest_ms)
  let after = edge_counts(c)
  assert_eq(at_rest, ["row 0", "row 1", "row 2", "row 3", "row 4", "row 5", "row 6", "row 7"])
  assert_eq(still, first, msg="at rest on the edge")
  assert_eq(edge_shown(c), at_rest)
  // (the 9th row's block made once, then put by and taken back each time it comes: no block let go)
  assert_eq(after.0 - first.0, 1, msg="blocks made over the back and forth: \{after.0 - first.0}")
  assert_eq(after.2 - first.2, 0, msg="blocks let go over the back and forth: \{after.2 - first.2}")
}

///|
test "a page's list at rest with a row's edge exactly at its top, the wheel a point over it and back twenty times: nothing let go, nothing made or taken at rest on the edge" {
  let c = edge_case()
  let t0 = c.t.origin
  // (down by exactly two rows: the 2nd row's foot at its top)
  c.t.input_at(t0 + edge_rest_ms)
  c.t.wheel(150.0, 100.0, 80.0)
  c.t.run_for(edge_rest_ms)
  let at_rest = edge_shown(c)
  let first = edge_counts(c)
  c.t.run_for(edge_rest_ms)
  let still = edge_counts(c)
  let from = c.t.time() - t0
  for i in 0..<20 {
    c.t.input_at(t0 + from + edge_turn_ms * (2 * i + 1).to_double())
    c.t.wheel(150.0, 100.0, -1.0)
    c.t.input_at(t0 + from + edge_turn_ms * (2 * i + 2).to_double())
    c.t.wheel(150.0, 100.0, 1.0)
  }
  c.t.run_for(edge_rest_ms)
  let after = edge_counts(c)
  assert_eq(at_rest, ["row 2", "row 3", "row 4", "row 5", "row 6", "row 7", "row 8", "row 9"])
  assert_eq(still, first, msg="at rest on the edge")
  assert_eq(edge_shown(c), at_rest)
  assert_eq(after.2 - first.2, 0, msg="blocks let go over the back and forth: \{after.2 - first.2}")
}
