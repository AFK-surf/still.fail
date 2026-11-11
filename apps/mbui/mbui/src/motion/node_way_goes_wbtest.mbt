// Whether a way goes, read by a binding (NodeWay::goes, View::goes_now: the clock not followed): worked out again as
// it is set off and at its declared end, a frame drawn there or none, and not on the frames between.

///|
test "a binding reading whether a way goes: worked out again at its declared end, no frame drawn between; not on the frames while it goes" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  let way = NodeWay::new(0.0)
  let node : Ref[@view.View?] = Ref(None)
  let worked = Ref(0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      node.val = Some(b)
      b
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .ground(
        By(fn() {
          worked.val += 1
          if way.goes(b) {
            0xFF0000FFL
          } else {
            0x00FF00FFL
          }
        }),
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let b = node.val.unwrap()
  let ground = fn() {
    match t.drawn_rects().filter(fn(r) { r.4 == 0xFF0000FFL || r.4 == 0x00FF00FFL }).get(0) {
      Some(r) => r.4
      None => -1L
    }
  }
  let before = ground()
  let t0 = t.time()
  tree.event(t0, fn() { way.go(b, 1.0, tween(200.0, ease=Out)) })
  t.frame_at(t0 + 16.0)
  let going = ground()
  let worked_going = worked.val
  for at in [40.0, 100.0, 150.0] {
    t.frame_at(t0 + at)
  }
  let worked_between = worked.val - worked_going
  // (one frame past its end: none drawn at it)
  t.frame_at(t0 + 400.0)
  assert_eq((before, going, worked_between, ground()), (0x00FF00FFL, 0xFF0000FFL, 0, 0x00FF00FFL))
}
