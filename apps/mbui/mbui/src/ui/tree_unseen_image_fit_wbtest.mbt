// An unseen image still asks for its eventual drawing, including the part cropped by its frame.

///|
test "a hidden cropped image is decoded for its picture, not its smaller frame" {
  let src = "mem:unseen-cropped-phone"
  let t = Tester::new(
    fn(_) {  },
    tree=fn(root) {
      root.box(fn(b) {
        b.width(Is(Some(128.0)))
        .height(Is(Some(240.0)))
        .alpha(Is(0.0))
        .image(Is(Some((src, "", 8192))))
        .image_in(Is(Some(((0.0, 0.0, 128.0, 277.0), 0L))))
        |> ignore
      }) |> ignore
    },
    images=[(src, 780, 1688)],
  )
  add_image(src, b"a phone picture")
  t.draw()
  t.run_for(move_most_ms)
  assert_eq(t.image_loads(), [("bytes:15", 1024)])
}

///|
test "a hidden picture's explicit decode room takes precedence over its picture rectangle" {
  let src = "mem:unseen-judged-phone"
  let t = Tester::new(
    fn(_) {  },
    tree=fn(root) {
      root.box(fn(b) {
        b.width(Is(Some(128.0)))
        .height(Is(Some(240.0)))
        .alpha(Is(0.0))
        .image(Is(Some((src, "", 8192))))
        .image_in(Is(Some(((0.0, 0.0, 128.0, 277.0), 0L))))
        .image_for(Is((64.0, 64.0)))
        |> ignore
      }) |> ignore
    },
    images=[(src, 780, 1688)],
  )
  add_image(src, b"a phone picture")
  t.draw()
  assert_eq(t.image_loads(), [("bytes:15", 128)])
}

///|
test "the pixels for a covering picture include the cropped part" {
  let portrait = Some((780.0, 1688.0))
  let covering = image_placed_px(128.0, 240.0, FitCover, portrait, 2.0)
  assert_true(covering > 554.0 && covering < 555.0)
  assert_eq(image_placed_px(128.0, 240.0, FitFill, portrait, 2.0), 480.0)
  assert_eq(image_placed_px(128.0, 240.0, FitCover, None, 2.0), 480.0)
}
