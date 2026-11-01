// A node of the window's tree's picture (View::image), its source and size the same and nothing else moving: drawn
// as the host says a decode of it is done, by the frame asked for then (a file of its own: run alone, nothing before it
// in the same run).

///|
test "a node's picture, its source and size the same, nothing else moving: the host saying it decoded asks for a frame by itself, and that frame, the one owed, draws it" {
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)], finish=false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.offset(Is((100.0, 100.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some(("pic", "", 4096)))) |> ignore
    })
    |> ignore
  })
  t.draw()
  let asked = t.pending().filter(fn(p) { p.0 == 1 })
  assert_eq(asked.length(), 1, msg="its decode asked for, one")
  assert_eq(pictures_sized(60.0, 40.0).length(), 0, msg="none drawn yet")
  // (at rest: what was owed drawn, nothing asked for since)
  t.run_for(frame_period_default)
  assert_true(!t.fake.wants, msg="at rest before the host says anything")
  // (the host says it decoded, as its word comes: nothing asked of it here but that word)
  match t.fake.images.get(asked[0].1) {
    Some(im) => im.state = 1
    None => fail("no decode \{asked[0].1}")
  }
  on_outside(1, asked[0].1, 1)
  assert_true(t.fake.wants, msg="a frame asked for by what draws the node, as the host's word came")
  // (the frame owed: the picture drawn in it, no fade to wait for)
  t.draw_owed(1)
  assert_eq(pictures_sized(60.0, 40.0).length(), 1, msg="drawn in the frame owed")
}
