// A way at rest told to go where it already stands, still: no setting out (no start, nothing said to move), no frame
// asked for it, nothing that reads it worked out again.

///|
test "a way at rest told to go where it stands, still: nothing set out, no frame asked, no binding worked out again" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  let way = Way::new(0.0)
  let node : Ref[@view.View?] = Ref(None)
  let worked = Ref(0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      node.val = Some(b)
      b
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .scale(
        By(fn() {
          worked.val += 1
          1.0 - 0.1 * way.shown_on(b)
        }),
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let worked_before = worked.val
  let said_before = ways_said()
  let t0 = t.time() + 5.0
  tree.event(t0, fn() { way.go(0.0, lift_spring, at=t0) })
  let idle = t.idle_said()
  assert_eq(
    (worked.val - worked_before, ways_said() - said_before, way.starts_at(), idle),
    (0, 0, -1.0, None),
  )
  // (one that goes still goes: told back to where it stands while it is on its way, it turns)
  tree.event(t0 + 10.0, fn() { way.go(1.0, lift_spring, at=t0 + 10.0) })
  tree.event(t0 + 50.0, fn() { way.go(0.0, lift_spring, at=t0 + 50.0) })
  assert_eq(way.starts_at(), t0 + 50.0)
}
