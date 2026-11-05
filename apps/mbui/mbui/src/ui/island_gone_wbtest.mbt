// An old view in the window's tree let go while another stays where it was (view_host.mbt old_places_tell): each is a
// part of its own, so nothing is built for it; the frame is painted alone, the tree no longer holding the one let go,
// and drawn as building it whole draws it (Tester's own check, and island_frame's).

///|
/// A window 400 by 200 whose tree holds an old view 400 by 100 at its top, and under it, while `shown` says so, another
/// as big: each words and a box.
fn island_gone_tester(shown : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        c.box(w=Px(400.0), h=Px(100.0), fn() { c.text("stays words", wrap=false) |> ignore }) |> ignore
      })
      .width(Is(Some(400.0)))
      .height(Is(Some(100.0)))
      |> ignore
      b.pick(fn() { shown.get() }, fn(slot, on) {
        if on {
          old(slot, fn(c) {
            c.box(w=Px(400.0), h=Px(100.0), fn() { c.text("goes words", wrap=false) |> ignore }) |> ignore
          })
          .width(Is(Some(400.0)))
          .height(Is(Some(100.0)))
          |> ignore
        }
      })
    })
    |> ignore
  })
  t.draw()
  // (laid out the same twice: what comes after it may be painted alone)
  t.clock_frame()
  t.clock_frame()
  t
}

///|
test "an old view let go while the other stays where it was: nothing built, the frame painted alone without it, drawn as built whole" {
  let shown = @signals.signal(true)
  let t = island_gone_tester(shown)
  assert_true(t.drawn_text().contains("goes words"))
  let before = t.frame_hash()
  let (alone, drawn, whole) = island_frame(t, fn() { shown.set(false) })
  assert_true(alone, msg="built: \{t.built_why()}")
  assert_eq(drawn, whole)
  assert_true(drawn != before)
  assert_true(!t.drawn_text().contains("goes words"))
  assert_true(t.drawn_text().contains("stays words"))
}
