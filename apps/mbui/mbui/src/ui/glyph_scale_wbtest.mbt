// A glyph kept in the atlas is drawn from a cell of its size at the frame's scale: one put there at another scale takes
// in what lies beside it, each at half its size (words in pieces, doubled, a line of other words under them).

///|
test "a frame at another scale, the host's generation where it was: every glyph drawn is put again at that scale" {
  let t = Tester::new(fn(c) { c.text("AB", wrap=false) |> ignore }, w=400.0, scale=1.0)
  t.draw()
  let placed = fn() {
    let at = []
    text_cache.glyphs.each(fn(_, g) { if g.plot >= 0 { at.push((g.u, g.v, g.sc)) } })
    at.sort()
    at
  }
  let before = placed()
  assert_true(before.length() >= 2)
  assert_true(before.iter().all(fn(g) { g.2 == 1.0 }))
  t.fake.scale = 2.0
  t.draw()
  let after = placed()
  assert_true(after.length() >= 2)
  assert_true(after.iter().all(fn(g) { g.2 == 2.0 }))
  // (none where it was: the cells at 2 would have run over the ones beside them at 1)
  assert_true(after.iter().all(fn(g) { before.iter().all(fn(b) { b.0 != g.0 || b.1 != g.1 }) }))
}
