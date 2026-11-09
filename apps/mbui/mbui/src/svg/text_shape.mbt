// Shaping a run of text into positioned glyphs, with mbui/shape (HarfBuzz's shaping as harfrust does it), as
// usvg's text layout shapes each bidi run.

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
fn shape_run(font : @shape.ShapeFont, chunk : TextChunk, a : Int, b : Int, rtl : Bool, kerning : Bool, small_caps : Bool) -> Array[Shaped] {
  let base = chunk.bytes[a]
  let buffer = @shape.Buffer::new()
  for i in a..<b {
    buffer.push(chunk.chars[i].to_int(), chunk.bytes[i] - base)
  }
  buffer.set_direction(if rtl { RightToLeft } else { LeftToRight })
  let features = []
  if small_caps {
    features.push(@shape.Feature::new("smcp", 1))
  }
  if !kerning {
    features.push(@shape.Feature::new("kern", 0))
  }
  @shape.shape(font, buffer, features)
  let infos = buffer.glyph_infos()
  let positions = buffer.glyph_positions()
  Array::makei(infos.length(), fn(i) {
    {
      glyph: infos[i].glyph_id,
      cluster: infos[i].cluster,
      x_advance: positions[i].x_advance,
      x_offset: positions[i].x_offset,
      y_offset: positions[i].y_offset,
    }
  })
}
