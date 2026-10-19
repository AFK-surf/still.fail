// A host's text kept and given again under a Tester (textrec.mbt).

///|
test "kept text lays words out as the host shaped them; what it lacks is said" {
  let view = fn(c : @ui.Ctx) { c.box(dir=Row, fn() { c.text("ab", size=10.0) |> ignore }) |> ignore }
  // the fake host: half an em a letter
  let (_, _, w0, _) = @ui.Tester::new(view, w=200.0, h=100.0).rect_of("ab").unwrap()
  assert_eq(w0, 10.0)
  let kept =
    #|TEXTREC {"m":[10,400,0],"r":[9,3,13]}
    #|TEXTREC {"s":[10,400,0,"ab"],"r":[0,1,7.5,97,1,1,4.25,98]}
  let t = @ui.Tester::new(view, w=200.0, h=100.0, text=kept)
  let (_, _, w1, h1) = t.rect_of("ab").unwrap()
  assert_eq(w1, 11.75)
  assert_eq(h1, 13.0)
  // its glyphs' boxes were not kept: said, and drawn as the fake host would
  assert_true(t.text_missing().contains("glyph 97"))
  assert_true(t.text_missing().contains("glyph 98"))
  assert_eq(t.text_missing().filter(fn(m) { m.has_prefix("shape") }), [])
}

///|
test "a Tester after one that kept text has the fake host's own again" {
  let t = @ui.Tester::new(fn(c) { c.box(dir=Row, fn() { c.text("ab", size=10.0) |> ignore }) |> ignore }, w=200.0, h=100.0)
  let (_, _, w, _) = t.rect_of("ab").unwrap()
  assert_eq(w, 10.0)
  assert_eq(t.text_missing(), [])
}
