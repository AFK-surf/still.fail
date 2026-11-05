// The host's glyphs' generation asked once a frame (atlas_now), however many of the frame's parts read it: what words
// are measured by, the scene's key, the frame's terms.

///|
test "the host asked its glyphs' generation once a frame, a frame of the window's tree and of the old frame alike" {
  let shift = @signals.signal(0.0)
  let t = Tester::new(fn(c) { c.text("旧的字") |> ignore }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(80.0))).height(Is(Some(20.0))).offset(By(fn() { (shift.get(), 0.0) })) |> ignore
      b.words(Is("字")) |> ignore
    })
    |> ignore
    old(root, fn(c) { c.text("旧的字") |> ignore }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  let asked = []
  for i in 1..=3 {
    let was = atlas_asked.val
    shift.set(i.to_double() * 10.0)
    t.draw()
    asked.push(atlas_asked.val - was)
  }
  assert_eq(asked, [1, 1, 1])
}
