///|
test "wheel kept: a pinch over a box that zooms by it is the app's, over a list or a box that only pans the page's" {
  let zoomed : Array[Double] = []
  let view = fn(c : @ui.Ctx) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let picture = c.id("picture")
      @ui.capture(c, picture, zooms=true)
      let (_, dy, mods) = @ui.wheel_of(c, picture)
      if dy != 0.0 && (mods & @ui.wheel_mod_pinch) != 0 {
        zoomed.push(dy)
      }
      c.box(id=picture, w=Fill(1.0), h=Px(100.0), fn() {  }) |> ignore
      let screen = c.id("screen")
      @ui.capture(c, screen)
      ignore(@ui.wheel_of(c, screen))
      c.box(id=screen, w=Fill(1.0), h=Px(100.0), fn() {  }) |> ignore
      c.capped("tall", 200.0, fn() { c.box(w=Fill(1.0), h=Px(1000.0), fn() {  }) |> ignore }) |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(view, w=300.0, h=400.0)
  let pinch = @ui.wheel_mod_ctrl | @ui.wheel_mod_pinch
  t.wheel_with(100.0, 50.0, 0.0, -4.0, pinch)
  assert_true(t.wheel_kept())
  assert_eq(zoomed, [-4.0])
  t.wheel_with(100.0, 150.0, 0.0, -4.0, pinch)
  assert_false(t.wheel_kept())
  t.wheel_with(100.0, 300.0, 0.0, -4.0, pinch)
  assert_false(t.wheel_kept())
  // (a wheel with nothing held is not a zoom's: nothing to leave to a page)
  t.wheel_with(100.0, 50.0, 0.0, -4.0, 0)
  assert_false(t.wheel_kept())
}
