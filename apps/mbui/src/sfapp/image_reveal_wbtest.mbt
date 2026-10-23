// A message's image coming in at a desktop's width (messages.mbt image_reveal), as the web's msgImageReveal.

///|
test "a message's image as the web's: what it waits on until decoded; then brushed in from its top and sharpened over 1100 ms" {
  reset()
  let t = @ui.Tester::new(
    fn(c) {
      wide_on.val = true
      image_reveal(c, "pic", 300.0, 200.0, FitCover, "")
    },
    w=400.0,
    h=300.0,
    platform=0,
    images=[("pic", 600, 400)],
  )
  t.frame()
  // decoded by the next frame: its way in starts then
  t.frame()
  let began = t.time()
  match reveals.get("pic") {
    Some(Some(a)) => assert_true(a.moving(), msg="on its way in")
    _ => fail("no way in for an image not decoded as it was first shown")
  }
  // half way: frosted over (its blur going), part of it still waiting under the edge
  t.run_for(reveal_ms / 2.0 - (t.time() - began))
  assert_true(t.drawn_glass().length() > 0, msg="blurred on its way")
  // in: as it is, nothing over it
  t.run_for(began + reveal_ms + 1.0 - t.time())
  assert_eq(t.drawn_glass().length(), 0)
  match reveals.get("pic") {
    Some(Some(a)) => assert_false(a.moving())
    _ => fail("its way in forgotten")
  }
}

///|
test "a message's image already decoded as it is first shown comes as it is" {
  reset()
  let shown = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      wide_on.val = true
      // (decoded first, drawn once it is)
      if shown.val {
        image_reveal(c, "pic", 300.0, 200.0, FitCover, "")
      } else {
        c.image("pic", w=Px(300.0), h=Px(200.0), fade=false) |> ignore
      }
    },
    w=400.0,
    h=300.0,
    platform=0,
    images=[("pic", 600, 400)],
  )
  t.frame()
  t.frame()
  shown.val = true
  t.frame()
  assert_true(reveals.get("pic") is Some(None), msg="no way in")
  assert_eq(t.drawn_glass().length(), 0)
}
