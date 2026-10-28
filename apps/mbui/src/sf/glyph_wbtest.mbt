///|
/// How many times a glyph of `g` is built over `ms` after it is first drawn (its frames as a host draws them), its
/// frames drawn the while.
fn glyph_builds(g : GlyphCounts, ms : Double) -> Int {
  let builds = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.box(fn() { station_glyph(c, g, 28.0, 0x24272BFFL, 0xDC5929FFL) |> ignore }) |> ignore
  })
  t.draw()
  // (a breath: each step's frame, of the look alone, drawn as the frame built whole draws it)
  t.run_for(glyph_breath_period)
  t.check_looks(false)
  let was = builds.val
  t.run_for(ms)
  builds.val - was
}

///|
test "a station's link on its way: its arc breathes as a look by the clock, built no more than a glyph standing still" {
  let breathing : GlyphCounts = { online: 1, dim: 1, failing: 0, working: 0, asleep: false, connecting: 1 }
  let still : GlyphCounts = { online: 1, dim: 1, failing: 0, working: 0, asleep: false, connecting: 0 }
  // (a breath and a half: every step of it on the resident clock drawn)
  assert_eq(glyph_builds(breathing, glyph_breath_period * 1.5), glyph_builds(still, glyph_breath_period * 1.5))
}
