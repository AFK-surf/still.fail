// A node's words on a halo (View::words_halo): the cover of their glyphs blurred, in its colour, drawn once under them
// and past them by as far as the blur reaches; blurred once for what they are, not again as they are drawn again, nor
// for another colour; blurred anew for other words; none where it says none.

///|
/// Words `text` on halo `halo` (its blur, its colour), in black, at the window's top left.
fn halo_words(text : @signals.Signal[String], halo : @signals.Signal[(Double, Int64)]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .words(By(fn() { text.get() }), look={ ..@view.words_plain, size: 13.0, line: 18.0, wrap: false })
      .words_halo(By(fn() { halo.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The glyph-kind instances (kind 1) drawn in the last frame, in order: x, y, w, h and colour RRGGBBAA.
fn halo_glyph_insts(t : Tester) -> Array[(Double, Double, Double, Double, Int64)] {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  t
  .drawn_instances()
  .filter(fn(i) { i[5] == 1.0 })
  .map(fn(i) { (i[0], i[1], i[2], i[3], (ch(i[8]) << 24) | (ch(i[9]) << 16) | (ch(i[10]) << 8) | ch(i[11])) })
}

///|
test "words on a halo: one instance in its colour under their glyphs, past them by three of its blur; blurred once, not again as it is drawn again" {
  let text = @signals.signal("Visual Studio Code", same=fn(a, b) { a == b })
  let halo = @signals.signal((6.0, 0xFF0000FFL), same=fn(a, b) { a == b })
  let t = halo_words(text, halo)
  let gs = halo_glyph_insts(t)
  let words = gs[1:].to_owned()
  let x0 = words.fold(init=1.0e9, fn(m, g) { dmin(m, g.0) })
  let x1 = words.fold(init=-1.0e9, fn(m, g) { dmax(m, g.0 + g.2) })
  let (hx, hy, hw, hh, hc) = gs[0]
  assert_eq(
    (
      hc,
      words.iter().all(fn(g) { g.4 == 0x000000FFL }),
      words.length(),
      (x0 - hx - 18.0).abs() < 1.0,
      hx + hw - x1 > 17.5 && hx + hw - x1 < 21.0,
      hh > 36.0,
      hy < 0.0,
      t.halos_made(),
    ),
    (0xFF0000FFL, true, 16, true, true, true, true, (1, 1)),
    msg="halo \{Repr(gs[0])}, glyphs from \{x0} to \{x1}",
  )
  t.draw()
  t.draw()
  assert_eq((halo_glyph_insts(t).length(), t.halos_made()), (17, (1, 1)))
}

///|
test "a halo in another colour drawn as blurred before; other words blurred anew; none said, none drawn" {
  let text = @signals.signal("Visual Studio Code", same=fn(a, b) { a == b })
  let halo = @signals.signal((6.0, 0xFF0000FFL), same=fn(a, b) { a == b })
  let t = halo_words(text, halo)
  let red = halo_glyph_insts(t)[0]
  halo.set((6.0, 0x00FF0080L))
  t.draw()
  let green = halo_glyph_insts(t)[0]
  let after_colour = t.halos_made()
  text.set("Code")
  t.draw()
  let shorter = halo_glyph_insts(t)
  let after_words = t.halos_made()
  halo.set((0.0, 0x00FF0080L))
  t.draw()
  let none = halo_glyph_insts(t)
  assert_eq(
    (
      (green.0, green.1, green.2, green.3) == (red.0, red.1, red.2, red.3),
      green.4,
      after_colour,
      shorter.length(),
      shorter[0].2 < red.2,
      after_words,
      none.length(),
      none.iter().all(fn(g) { g.4 == 0x000000FFL }),
    ),
    (true, 0x00FF0080L, (1, 1), 5, true, (2, 2), 4, true),
  )
}
