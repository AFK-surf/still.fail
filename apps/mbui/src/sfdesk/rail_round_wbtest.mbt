// The rail's grounds' corners (rail_round_node) follow whether the frame is on the tape (wide.tape) as it changes: a
// node made off it is as round as one made on it once the frame goes on it, nothing else told (in a window 26 round:
// off the tape its corner follows the window's, on it it is a circle).

///|
test "a rail ground made off the tape is as round as one made on it once the frame goes on the tape" {
  wide.tape.set(false)
  let kept : Ref[@view.View?] = { val: None }
  let fresh : Ref[@view.View?] = { val: None }
  let t = @ui.Tester::new(fn(_c) {  }, tree=fn(root) {
    root.box(fn(v) {
      rail_round_node(v, fn() { rail_at_tape(0L) })
      kept.val = Some(v)
    })
    |> ignore
    root.show(fn() { wide.tape.get() }, fn(v) {
      v.box(fn(n) {
        rail_round_node(n, fn() { rail_at_tape(0L) })
        fresh.val = Some(n)
      })
      |> ignore
    })
    |> ignore
  }, w=720.0, h=840.0, platform=0, window_corner=26.0)
  t.draw()
  let off = kept.val.unwrap().corners_said()
  wide.tape.set(true)
  t.draw()
  let on = fresh.val.unwrap().corners_said()
  // (the two differ, or this holds nothing)
  assert_true(on != off, msg="off the tape \{Repr(off)}, on it \{Repr(on)}")
  assert_eq(kept.val.unwrap().corners_said(), on)
  wide.tape.set(false)
}
