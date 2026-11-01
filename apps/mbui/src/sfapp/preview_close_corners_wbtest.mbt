// A picture's preview returns to its thumbnail with the shape the thumbnail actually has in its container.

///|
test "a picture returning to a rounded card keeps all four thumbnail corners through the handoff" {
  let scale = 3.25
  for corners in [(40.0, 40.0, 40.0, 40.0), (40.0, 10.0, 30.0, 20.0)] {
    new_run()
    let a = flight_photo()
    @sfbase.sent_pictures[@sfbase.sent_key("ws1/st1", a.path)] = "sent-key"
    let src = fixture("chat")
    let t = @ui.Tester::new(fn(c) {
      let radius = @ui.Radius::Corners(corners.0, corners.1, corners.2, corners.3)
      c.box(style=@ui.style(w=Fixed(300.0), h=Fixed(225.0), radius~, clip=true), fn() { chat_file(c, src, a) })
      |> ignore
      preview(c, src)
    }, w=390.0, h=844.0, scale~, images=[("sent-key", 1200, 900), ("mem:preview/ws1/st1/s-c1/uploads/fx/photo.jpg", 1200, 900)])
    t.draw()
    t.run_for(@ui.image_fade_ms)
    let pictures = fn() { t.drawn_instances().filter(fn(p) { p[5] == 4.0 && p[2] > 40.0 && p[11] > 0.5 }) }
    let before = pictures()
    assert_eq(before.length(), 1, msg="thumbnail")
    t.tap(120.0, 100.0)
    let v = viewer.get().unwrap()
    t.run_for(@ui.move_most_ms)
    t.back()
    let end = v.fly.end()
    // The host may draw for a vsync just after the flight's end while its logic is still just before it. The flight
    // must have the same coverage as the thumbnail, as must the thumbnail on the following frame.
    t.frame_shown_at(end - 0.01, end + 0.01)
    let landing = pictures()
    assert_eq(landing.length(), 1, msg="landing")
    t.frame_at(end + @ui.frame_period_default)
    let after = pictures()
    assert_eq(after.length(), 1, msg="landed")
    let mut bad = 0
    for origin in [(0.0, 0.0), (260.0, 0.0), (260.0, 185.0), (0.0, 185.0)] {
      for ix in 0..<130 {
        for iy in 0..<130 {
          let x = origin.0 + (ix.to_double() + 0.5) / scale
          let y = origin.1 + (iy.to_double() + 0.5) / scale
          let want = corner_cover(before[0], x, y, scale)
          if (corner_cover(landing[0], x, y, scale) - want).abs() > 0.5 ||
            (corner_cover(after[0], x, y, scale) - want).abs() > 0.5 {
            bad += 1
          }
        }
      }
    }
    assert_eq(bad, 0, msg="\{corners}: pixels changing at a corner")
  }
}
