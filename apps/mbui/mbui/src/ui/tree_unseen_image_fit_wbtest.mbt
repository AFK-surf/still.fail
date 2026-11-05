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
