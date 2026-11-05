// A test can say the natural size of an image supplied as bytes, just as it can for an image supplied by name.

///|
test "a tester's registered picture size applies to bytes at the same source" {
  let t = Tester::new(
    fn(c) {
      c.image_bytes("mem:phone", b"a phone picture")
      c.image("mem:phone", w=Px(128.0), h=Px(240.0)) |> ignore
    },
    images=[("mem:phone", 780, 1688)],
  )
  t.run_for(move_most_ms)
  assert_eq(image_natural("mem:phone"), Some((780.0, 1688.0)))
}
