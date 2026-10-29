// The side panel beside the page (panel.mbt side_beside): what it puts past its left edge.

///|
test "the side panel at rest cuts nothing past its left edge: its edge's handle, half over the page, shows whole; sliding, it is cut to its column" {
  side_slide_reset()
  let open = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        side_beside(c, "test", open.val, 400.0, fn() {  }, fn() {
          c.box(style=@ui.style(w=Full, h=Full), fn() {
            c.box(left=-20.0, top=100.0, fn() { c.text("past its edge", size=13.0) |> ignore }) |> ignore
          })
          |> ignore
        })
      })
    },
    w=1400.0,
    h=800.0,
    platform=2,
  )
  t.draw()
  let (x, _, w, _) = t.shown_of("past its edge").unwrap()
  assert_eq(x, 1000.0 - 20.0)
  assert_true(w > 20.0, msg="\{w}")
  // closing: cut to the column as it narrows
  side_changing("test", ["a"], "a", false)
  open.val = false
  t.draw()
  t.run_for(@ui.move_most_ms / 2.0)
  match t.shown_of("past its edge") {
    Some((x, _, _, _)) => assert_true(x > 1000.0, msg="\{x}")
    None => ()
  }
  side_slide_reset()
}
