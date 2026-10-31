// A message's image coming in at a desktop's width (sfdesk/message_files.mbt image_reveal), as the web's
// msgImageReveal.

///|
/// How long a message's image takes to come in on the desktop (Chat.css.ts msgImageReveal: 1100 ms).
let reveal_ms : Double = 1100.0

///|
test "a message's image as the web's: what it waits on until decoded; then brushed in from its top and sharpened over 1100 ms" {
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sfpages.image_reveal(c, "pic", 300.0, 200.0, FitCover, "") },
    w=400.0,
    h=300.0,
    platform=0,
    images=[("pic", 600, 400)],
  )
  t.frame()
  // decoded by the next frame: its way in starts then
  t.frame()
  let began = t.time()
  // half way: frosted over (its blur going), part of it still waiting under the edge
  t.run_for(reveal_ms / 2.0 - (t.time() - began))
  assert_true(t.drawn_glass().length() > 0, msg="blurred on its way")
  // in: as it is, nothing over it
  t.run_for(began + reveal_ms + 1.0 - t.time())
  assert_eq(t.drawn_glass().length(), 0)
}

///|
test "a message's image already decoded as it is first shown comes as it is" {
  new_run()
  let shown = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      // (decoded first, drawn once it is)
      if shown.val {
        @sfpages.image_reveal(c, "pic", 300.0, 200.0, FitCover, "")
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
  assert_eq(t.drawn_glass().length(), 0)
  t.run_for(reveal_ms / 2.0)
  assert_eq(t.drawn_glass().length(), 0)
}

///|
test "a message's image the device had comes as it is once decoded, not brushed in as one waited for from its station" {
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sfpages.image_reveal(c, "pic", 300.0, 200.0, FitCover, "", held=true) },
    w=400.0,
    h=300.0,
    platform=0,
    images=[("pic", 600, 400)],
  )
  t.frame()
  // decoded by the next frame: as it is from then
  t.frame()
  assert_eq(t.drawn_glass().length(), 0)
  t.run_for(reveal_ms / 2.0)
  assert_eq(t.drawn_glass().length(), 0)
}
