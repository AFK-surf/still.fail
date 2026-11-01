// Shaping a run of text into positioned glyphs. For now the font's character map and advances, mirrored
// characters in right-to-left runs, and the `kern` table's pairs; HarfBuzz's shaping (harfrust) replaces this.

///|
priv struct Shaped {
  glyph : Int
  /// the UTF-8 byte offset of its character in the run
  cluster : Int
  x_advance : Int
  x_offset : Int
  y_offset : Int
}

///|
fn shape_run(face : @font.Face, chunk : TextChunk, a : Int, b : Int, rtl : Bool, kerning : Bool, small_caps : Bool) -> Array[Shaped] {
  ignore(small_caps)
  let base = chunk.bytes[a]
  let out : Array[Shaped] = []
  for i in a..<b {
    let c = chunk.chars[i].to_int()
    let c = if rtl { @text.mirror(c) } else { c }
    let g = face.glyph_index(c)
    out.push({ glyph: g, cluster: chunk.bytes[i] - base, x_advance: face.advance(g), x_offset: 0, y_offset: 0 })
  }
  if kerning {
    for i in 0..<(out.length() - 1) {
      let k = face.kerning(out[i].glyph, out[i + 1].glyph)
      if k != 0 {
        out[i] = { ..out[i], x_advance: out[i].x_advance + k }
      }
    }
  }
  if rtl {
    out.rev_in_place()
  }
  out
}
