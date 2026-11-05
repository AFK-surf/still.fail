// An old view come into the window's tree while another stands where it was (view_host.mbt old_places_tell): each is a
// part of its own, so the frame builds the one come alone, the other kept as it was built; drawn as building it whole
// draws it (Tester's own check).

///|
test "an old view come while the other stands where it was: the frame builds it alone, the other kept" {
  let shown = @signals.signal(false)
  let t = island_gone_tester(shown)
  assert_true(!t.drawn_text().contains("goes words"))
  shown.set(true)
  t.clock_frame()
  assert_true(t.drawn_text().contains("goes words"))
  assert_true(t.drawn_text().contains("stays words"))
  let (_, built) = t.rows_as_nodes()
  assert_eq(built, 1, msg="built: \{t.built_why()}")
}

///|
test "an old view laid out taller while the other stands where it was: the frame builds it alone, the other kept" {
  let tall = @signals.signal(100.0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      old(b, fn(c) {
        c.box(w=Px(400.0), h=Px(100.0), fn() { c.text("stays words", wrap=false) |> ignore }) |> ignore
      })
      .width(Is(Some(400.0)))
      .height(Is(Some(100.0)))
      |> ignore
      old(b, fn(c) {
        c.box(style=style(w=Full, h=Full), fn() { c.text("grows words", wrap=false) |> ignore }) |> ignore
      })
      .width(Is(Some(400.0)))
      .height(By(fn() { Some(tall.get()) }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.clock_frame()
  t.clock_frame()
  tall.set(150.0)
  t.clock_frame()
  assert_true(t.drawn_text().contains("grows words"))
  let (_, built) = t.rows_as_nodes()
  assert_eq(built, 1, msg="built: \{t.built_why()}")
}
