// What is kept shaped (text.mbt shape): past the most strings, what was asked for longest ago goes, not all of it.

///|
test "past the most strings kept shaped, those asked for longest ago are let go, what this frame asks for kept" {
  let t = Tester::new(fn(c) { c.text("on the screen", wrap=false) |> ignore })
  ignore(t)
  // a frame that asks for one string, and as many others as are kept
  text_frame()
  let kept = shape("kept", 14.0, 400)
  let old = shape("old 0", 14.0, 400)
  for i in 1..<shapes_most {
    shape("old \{i}", 14.0, 400) |> ignore
  }
  // the next asks for the one again, and something new: the others go, the one asked for stays shaped as it was
  text_frame()
  assert_true(physical_equal(shape("kept", 14.0, 400), kept))
  shape("new", 14.0, 400) |> ignore
  assert_true(text_cache.shaped < shapes_most / 2)
  assert_true(physical_equal(shape("kept", 14.0, 400), kept))
  assert_true(!physical_equal(shape("old 0", 14.0, 400), old))
}
