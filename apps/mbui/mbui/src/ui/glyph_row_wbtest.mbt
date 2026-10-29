// A line's glyphs on one pixel row (scene.mbt on_glyph_row): each picture's offset is whole pixels from the baseline,
// and a baseline half way between two rows goes the same way for all of them.

///|
test "a line's glyphs share a pixel row when its baseline falls half way between two" {
  let sc = 1.5
  // 30.5 pixels down at 150%
  let base = 20.0 + 1.0 / 3.0
  let rows = []
  for py in -20..<-8 {
    let oy = py.to_double() / sc
    rows.push((on_glyph_row(base, oy, sc) * sc - py.to_double()).round())
  }
  for r in rows {
    assert_eq(r, rows[0])
  }
}
