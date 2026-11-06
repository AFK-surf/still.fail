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

///|
/// What a reaction to whether the drawing is past 45 is told, a frame sampled for 50 with the host at 0, then an event
/// at 40 asking where a node is drawn now or not asking, and then the same asked in no event.
fn told_past_45(asks : Bool) -> Array[String] {
  let told : Array[String] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0))).offset(By(fn() { (v.drawn_at(), 0.0) })) |> ignore
      v.reacts(fn() { v.drawn_past(45.0) }, fn(past) { told.push(past.to_string()) })
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.event(40.0, fn() { if asks { page.val.unwrap().drawn_now() |> ignore } })
  told.push("event done")
  if asks {
    page.val.unwrap().drawn_now() |> ignore
  }
  told
}

///|
test "drawn_now, in an event or in none, tells nothing to what reacts to the drawing's moment" {
  assert_eq(told_past_45(true), told_past_45(false))
}

///|
/// The width of a node as wide as whether the drawing is past 45 says, drawn as an event at 40 reads it after a frame
/// the host showed at 0 and sampled for `drawn_for`; then as the next frame, sampled for 50, draws it.
fn width_past_45(drawn_for : Double) -> (Double?, Double?) {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(if v.drawn_past(45.0) { 40.0 } else { 20.0 }) })).height(Is(Some(40.0))) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let read : Ref[Double?] = Ref(None)
  tree.event(40.0, fn() { read.val = page.val.unwrap().drawn_now().map(fn(d) { d.rect.2 }) })
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  (read.val, tree.drawn_of(page.val.unwrap().id()).map(fn(d) { d.w }))
}

///|
test "drawn_now reads what is drawn by the drawing's moment as of the event's moment, and the next frame draws its own" {
  assert_eq(width_past_45(0.0), (Some(20.0), Some(40.0)))
  assert_eq(width_past_45(50.0), width_past_45(0.0))
}
