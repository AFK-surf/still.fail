// The places of glyphs in a host's atlas (hostapi's atlas.mbt), as text.mbt asks for them.

///|
test "an atlas fills its plots a shelf at a time, then empties the one drawn from longest ago, never one this frame draws from" {
  // 1024 a side: four plots of 512, at (0, 0), (512, 0), (0, 512), (512, 512); glyphs 100 square, five to a shelf
  // (a pixel apart), five shelves to a plot
  let a = @hostapi.Atlas::new(1024)
  let gone : Array[Int] = []
  let put = fn(key : Int) { a.place(key, 100, 100, fn(k) { gone.push(k) }) }
  assert_eq(put(0), Some((0, 0, 0)))
  assert_eq(put(1), Some((0, 101, 0)))
  for k in 2..<5 {
    put(k) |> ignore
  }
  // the next shelf under the first
  assert_eq(put(5), Some((0, 0, 101)))
  for k in 6..<25 {
    put(k) |> ignore
  }
  // the first plot full: the next, a plot never filled
  assert_eq(put(25), Some((1, 512, 0)))
  // the next frames fill the rest, a plot each
  a.next_frame()
  for k in 26..<50 {
    put(k) |> ignore
  }
  a.next_frame()
  for k in 50..<75 {
    put(k) |> ignore
  }
  a.next_frame()
  for k in 75..<100 {
    put(k) |> ignore
  }
  assert_eq(gone, [])
  // all full, the first drawn from in this frame (what is on the screen): the plot drawn from longest ago, the
  // second, emptied, its glyphs gone
  a.next_frame()
  a.drawn(0)
  assert_eq(put(100), Some((1, 512, 0)))
  assert_eq(gone, Array::makei(25, fn(i) { 25 + i }))
  gone.clear()
  // filled again in this frame, the others drawn from in it too: no room while it is drawn, nothing emptied
  for k in 101..<125 {
    put(k) |> ignore
  }
  a.drawn(2)
  a.drawn(3)
  assert_eq(put(125), None)
  assert_eq(gone, [])
  // the next frame: room again, from the plot drawn from longest ago
  a.next_frame()
  a.drawn(1)
  a.drawn(3)
  assert_eq(put(125), Some((0, 0, 0)))
  assert_eq(gone, Array::makei(25, fn(i) { i }))
}

///|
test "an atlas holds no glyph larger than a plot, nor any with nothing to draw" {
  let a = @hostapi.Atlas::new(2048)
  assert_true(a.holds(@hostapi.atlas_plot, @hostapi.atlas_plot))
  assert_true(!a.holds(@hostapi.atlas_plot + 1, 10))
  assert_true(!a.holds(0, 10))
  assert_eq(a.place(0, @hostapi.atlas_plot + 1, 10, fn(_) {  }), None)
  // none at all
  assert_true(!@hostapi.Atlas::new(0).holds(10, 10))
}

///|
test "an atlas let go of: its glyphs placed from the start again" {
  let a = @hostapi.Atlas::new(1024)
  a.place(0, 100, 100, fn(_) {  }) |> ignore
  a.place(1, 100, 100, fn(_) {  }) |> ignore
  a.clear()
  assert_eq(a.place(2, 100, 100, fn(_) {  }), Some((0, 0, 0)))
}
