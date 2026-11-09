///|
test "a thumbnail gives up on a stalled decoder only after all bytes arrive" {
  pv_first.clear()
  let image : Ref[String] = Ref("")
  let t = @ui.Tester::new(
    fn(c) { image.val = bytes_first_frame(c, "first-frame-test", "clip.webm", b"file") },
    finish=false,
  )
  let n = pv_first.get("first-frame-test").unwrap().view.unwrap()
  let id = n.id()
  let wait = @kit.media_decode_wait_ms
  let margin = wait / 200.0
  t.draw()
  t.run_for(wait * 1.5)
  assert_eq(image.val, "", msg="a slow read is not a decoder timeout")
  assert_true(t.view_said("{\"info\":{\"view\":\{id},\"state\":2,\"at\":[-1,0,0,0,0,4,0,0,0,0]}}"))
  t.advance(wait - margin)
  t.frame_at(t.time())
  assert_eq(image.val, "")
  t.advance(margin * 2.0)
  t.frame_at(t.time())
  assert_eq(image.val, "!")
  t.draw()
  assert_true(t.views().contains("close \{id}"))
  pv_first.clear()
}
