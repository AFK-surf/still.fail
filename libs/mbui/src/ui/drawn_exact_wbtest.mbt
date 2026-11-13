// What is drawn off where it is laid out is drawn off by whole pixels of the host's (View::drawn_off), or, where it
// says `exact`, by as far as is said: a thin line following a clock goes a pixel in many frames, and by whole pixels
// it is seen to step.

///|
let exact_ink : Int64 = 0xFF0000FFL

///|
/// A red box 40 by 20 at the window's top left, drawn off by `off`, at two pixels a point.
fn exact_tester(off : @signals.Signal[(Double, Double)], exact : Bool) -> Tester {
  Tester::new(fn(_c) {  }, w=200.0, h=100.0, scale=2.0, tree=fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(40.0))).height(Is(Some(20.0))).ground(Is(exact_ink)).drawn_off(By(fn() { off.get() }), exact~)
      |> ignore
    })
    |> ignore
  })
}

///|
/// Where the red box is drawn (its left, its top).
fn exact_at(t : Tester) -> Array[(Double, Double)] {
  t.drawn_rects().filter(fn(r) { r.4 == exact_ink }).map(fn(r) { (r.0, r.1) })
}

///|
test "drawn off by whole pixels: a part of one goes to the nearest" {
  let off = @signals.signal((10.3, 4.2), same=fn(a, b) { a == b })
  let t = exact_tester(off, false)
  t.draw()
  // (two pixels a point: 20.6 pixels across is 21, 8.4 down is 8)
  assert_eq(exact_at(t), [(10.5, 4.0)])
}

///|
test "drawn off exactly: by as far as said, parts of a pixel too" {
  let off = @signals.signal((10.3, 4.2), same=fn(a, b) { a == b })
  let t = exact_tester(off, true)
  t.draw()
  assert_eq(exact_at(t), [(10.3, 4.2)])
}

///|
test "drawn off exactly, a clock's every step shows: by whole pixels four of five are the same place" {
  // (a tenth of a point a step, two pixels a point: a fifth of a pixel)
  let steps = [0.0, 0.1, 0.2, 0.3, 0.4]
  let seen = fn(exact : Bool) {
    let off = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
    let t = exact_tester(off, exact)
    t.draw()
    let places : Array[Double] = []
    for x in steps {
      off.set((x, 0.0))
      t.frame()
      // (the one red box: none or more than one is told as a place no step is at)
      let at = exact_at(t)
      let x = if at.length() == 1 { at[0].0 } else { -1.0 }
      if !places.contains(x) {
        places.push(x)
      }
    }
    places
  }
  assert_eq(seen(false), [0.0, 0.5])
  assert_eq(seen(true), steps)
}
