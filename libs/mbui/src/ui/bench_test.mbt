// A bench of the app's own (Ctx::bench_frames): every frame drawn only where the host runs its bench mode.

///|
test "a bench's frames are asked for only in the host's bench mode: under a Tester, none" {
  let t = @ui.Tester::new(fn(c) {
    c.bench_frames(true)
    c.text("bench", wrap=false) |> ignore
  })
  t.draw()
  // asked each frame, yet no frame owed: a Tester is no bench
  t.assert_idle()
}
