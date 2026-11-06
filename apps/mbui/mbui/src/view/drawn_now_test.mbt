///|
/// Where a node moved by the clock alone is drawn as an event at `at` reads it, after a frame the host showed at 0 and
/// sampled for `drawn_for` (a predicted frame: Tree::at ahead of the frame's `now`).
fn drawn_in_event_after(drawn_for : Double, at : Double) -> Double? {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0))).offset(By(fn() { (v.drawn_at(), 0.0) })) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let read : Ref[Double?] = Ref(None)
  tree.event(at, fn() { read.val = page.val.unwrap().drawn_now().map(fn(d) { d.rect.0 }) })
  read.val
}

///|
test "drawn_now in an event reads where a node moved by the clock is at the event's moment, whichever frame was drawn before" {
  // (the host at 0 both times, its frame sampled ahead of the event, for 50 ms, or at 0: the event at 40 reads the same)
  let ahead = drawn_in_event_after(50.0, 40.0)
  let behind = drawn_in_event_after(0.0, 40.0)
  assert_eq(behind, Some(40.0))
  assert_eq(ahead, behind)
}
