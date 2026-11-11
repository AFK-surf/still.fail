// What a still pointer is over is worked out at an input, in a change and at the end of a way that may move something
// under it, never on a frame as something goes: told at those moments alone, the same at every rate.

///|
/// How long the box's hover fades in or out.
let hand_hover_ms : Double = 150.0

///|
/// How long the box takes to be moved off.
let hand_moved_ms : Double = 300.0

///|
/// A box that takes presses, 40 tall at the top, moved down by `way` as it goes, its hover a way of its own (fading in
/// as the pointer comes over it, out as it leaves); what it is told of the pointer being over it kept with the moment
/// each was told at.
fn hand_box(way : Way, told : Array[(Bool, Double)]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  let hover = Way::new(0.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() {  })
      .moved_by(fn(_w, _h, at) { (0.0, way.value_at(at)) }, fn(_w, _h) {
        // (followed as it is said again)
        way.said()
        way.end()
      })
      .alpha(By(fn() { 0.5 + 0.5 * hover.shown_on(b) }))
      |> ignore
      b.reacts(fn() { b.pointed() }, fn(on) {
        told.push((on, b.cause_at()))
        hover.go(if on { 1.0 } else { 0.0 }, tween(hand_hover_ms, ease=Out), at=b.cause_at())
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a box moved from under a still pointer: still pointed at as it goes, not at its way's end, told then alone" {
  let way = Way::new(0.0)
  let told : Array[(Bool, Double)] = []
  let t = hand_box(way, told)
  t.move_to(50.0, 20.0)
  t.draw()
  let t0 = t.time() + 10.0
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { way.go(120.0, tween(hand_moved_ms, ease=Out), at=t0) })
  t.run_for(hand_moved_ms / 2.0)
  let midway = told.copy()
  t.run_for(hand_moved_ms)
  assert_eq((midway.map(fn(x) { x.0 }), told.map(fn(x) { x.0 }), told[told.length() - 1].1), (
    [false, true],
    [false, true, false],
    way.end(),
  ))
}

///|
test "a pointer resting on a box that takes presses, nothing else going: told it is over it once, its hover's way and all" {
  let way = Way::new(0.0)
  let told : Array[(Bool, Double)] = []
  let t = hand_box(way, told)
  t.move_to(50.0, 20.0)
  t.run_for(hand_hover_ms + hand_moved_ms * 2.0)
  assert_eq(told.map(fn(x) { x.0 }), [false, true])
}

///|
/// When the box's way ends, in the test of a way's end said again as it is done.
let hand_end_at : Double = 500.0

///|
test "a way's end said again as the timeline does it, its logic not yet there: past, not said again (no loop at it)" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  let grew : Array[Int] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.height(Is(Some(40.0))) |> ignore
      let tree = b.tree
      let end = t.time() + hand_end_at
      tree.hand_at_end(end)
      b.at_moment(end, fn() {
        let before = tree.due_count()
        tree.hand_at_end(end)
        grew.push(tree.due_count() - before)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(hand_end_at * 2.0)
  assert_eq(grew, [0])
}

///|
/// How long the box's slow fade takes, set off as it is moved: far longer than the move.
let hand_fade_ms : Double = 2000.0

///|
test "a box moved from under a still pointer as a long fade of its look goes on: told at the move's end, not the fade's" {
  let way = Way::new(0.0)
  let fade = Way::new(1.0)
  let told : Array[(Bool, Double)] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() {  })
      .moved_by(fn(_w, _h, at) { (0.0, way.value_at(at)) }, fn(_w, _h) {
        way.said()
        way.end()
      })
      // (how it looks alone: what a point lands on is none the other for it)
      .alpha(By(fn() { fade.shown_on(b) }))
      |> ignore
      b.reacts(fn() { b.pointed() }, fn(on) { told.push((on, b.cause_at())) }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(50.0, 20.0)
  t.draw()
  let t0 = t.time() + 10.0
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() {
    way.go(120.0, tween(hand_moved_ms, ease=Out), at=t0)
    fade.go(0.2, tween(hand_fade_ms, ease=Out), at=t0)
  })
  t.run_for(hand_moved_ms * 2.0)
  assert_eq((told.map(fn(x) { x.0 }), told[told.length() - 1].1), ([false, true, false], way.end()))
}
