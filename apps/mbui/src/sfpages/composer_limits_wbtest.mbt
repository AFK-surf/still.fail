///|
test "a composer's captured limits resolve the same geometry at each pane width" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  for platform in [0, 2] {
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform~)
    t.draw()
    let corners = FixedArray::make(4, 28.0)
    corners[2] = 32.0
    for radii in [None, Some(corners)] {
      let limits = composer_limits(radii)
      for width in [100.0, 390.0, 700.0, 804.0, 828.0, 1000.0, 1500.0] {
        assert_true(limits.in_width(width) == composer_geometry(width, radii), msg="platform \{platform}, pane \{width}")
      }
    }
  }
}
