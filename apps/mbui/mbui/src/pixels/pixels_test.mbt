// mbui/pixels: a JPEG's bytes as T.81 has them, a picture drawn into a rect, what of it is drawn, its edge's colour.

///|
/// The JPEG's entropy-coded data: what is between its scan's header and its end.
fn scan_data(j : Bytes) -> Array[Byte] {
  let a = j.to_array()
  let mut at = 0
  while at + 1 < a.length() && !(a[at] == b'\xFF' && a[at + 1] == b'\xDA') {
    at = at + 1
  }
  let len = (a[at + 2].to_int() << 8) | a[at + 3].to_int()
  a[at + 2 + len:a.length() - 2].to_array()
}

///|
test "a JPEG of an 8 by 8 grey: no change from 0 in any component, its blocks ended at once" {
  let px = FixedArray::make(8 * 8 * 4, b'\x80')
  let j = @pixels.jpeg(8, 8, px)
  let a = j.to_array()
  // SOI ... EOI
  assert_eq((a[0], a[1]), (b'\xFF', b'\xD8'))
  assert_eq((a[a.length() - 2], a[a.length() - 1]), (b'\xFF', b'\xD9'))
  // Y: DC 0 ("00"), EOB ("1010"); Cb and Cr: DC 0 ("00"), EOB ("00"); then ones to the byte: 0010 1000 0000 0011
  assert_eq(scan_data(j), [b'\x28', b'\x03'])
}

///|
test "a JPEG's frame: its size, three components each whole" {
  let px = FixedArray::make(20 * 9 * 4, b'\xFF')
  let a = @pixels.jpeg(20, 9, px, quality=90).to_array()
  let mut at = 0
  while !(a[at] == b'\xFF' && a[at + 1] == b'\xC0') {
    at = at + 1
  }
  // its height and width, three components
  assert_eq(((a[at + 5].to_int() << 8) | a[at + 6].to_int(), (a[at + 7].to_int() << 8) | a[at + 8].to_int()), (9, 20))
  assert_eq(a[at + 9].to_int(), 3)
  assert_eq([a[at + 11], a[at + 14], a[at + 17]], [b'\x11', b'\x11', b'\x11'])
}

///|
test "a JPEG at quality 90: its tables libjpeg's (Annex K's scaled by 20%)" {
  let a = @pixels.jpeg(8, 8, FixedArray::make(256, b'\x00'), quality=90).to_array()
  let mut at = 0
  while !(a[at] == b'\xFF' && a[at + 1] == b'\xDB') {
    at = at + 1
  }
  // the luminance table's first (16 → 3) and the chrominance one's first (17 → 3)
  assert_eq(a[at + 5].to_int(), 3)
  assert_eq(a[at + 5 + 65].to_int(), 3)
}

///|
test "a picture drawn into a rect: over what is there, as large as the rect, smooth where it is made larger" {
  let c = @pixels.Canvas::new(4, 4)
  c.fill(0x0000FFFFL)
  // a 2 by 2 picture: red at the top left, clear elsewhere, drawn over the top left 2 by 2
  let src = FixedArray::make(16, b'\x00')
  src[0] = b'\xFF'
  src[3] = b'\xFF'
  c.draw(2, 2, src, (0, 0, 2, 2), (0.0, 0.0, 2.0, 2.0))
  let px = c.pixels()
  assert_eq([px[0], px[1], px[2], px[3]], [b'\xFF', b'\x00', b'\x00', b'\xFF'])
  // the clear pixel beside it: the blue under it
  assert_eq([px[4], px[5], px[6], px[7]], [b'\x00', b'\x00', b'\xFF', b'\xFF'])
  // past the rect: as it was
  assert_eq([px[8], px[9], px[10], px[11]], [b'\x00', b'\x00', b'\xFF', b'\xFF'])
  // a red pixel made four across: red through, half way between at its edge with the blue's own
  let d = @pixels.Canvas::new(8, 1)
  d.fill(0x000000FFL)
  let one = FixedArray::make(8, b'\x00')
  one[0] = b'\xFF'
  one[3] = b'\xFF'
  one[6] = b'\xFF'
  one[7] = b'\xFF'
  d.draw(2, 1, one, (0, 0, 2, 1), (0.0, 0.0, 8.0, 1.0))
  let q = d.pixels()
  assert_eq(q[0], b'\xFF')
  assert_eq(q[7 * 4 + 2], b'\xFF')
  assert_true(q[4 * 4].to_int() > 0 && q[4 * 4].to_int() < 255)
}

///|
test "a picture made smaller: each pixel the mean of what it covers" {
  // 4 by 1: black, white, black, white, made 2 by 1: each a mid grey
  let src = FixedArray::make(16, b'\xFF')
  for i in [0, 8] {
    src[i] = b'\x00'
    src[i + 1] = b'\x00'
    src[i + 2] = b'\x00'
  }
  let c = @pixels.Canvas::new(2, 1)
  c.draw(4, 1, src, (0, 0, 4, 1), (0.0, 0.0, 2.0, 1.0))
  assert_eq(c.pixels()[0], b'\x80')
  assert_eq(c.pixels()[4], b'\x80')
}

///|
test "what of a picture is drawn, and the colour of its edge" {
  let px = FixedArray::make(10 * 10 * 4, b'\x00')
  for y in 3..<6 {
    for x in 2..<8 {
      px[(y * 10 + x) * 4 + 3] = b'\xFF'
    }
  }
  assert_eq(@pixels.drawn_box(10, 10, px), (2, 3, 8, 6))
  assert_eq(@pixels.drawn_box(10, 10, FixedArray::make(400, b'\x00')), (0, 0, 10, 10))
  let c = @pixels.Canvas::new(40, 40)
  c.fill(0x336699FFL)
  assert_eq(@pixels.edge_colour(40, 40, c.pixels()), "#336699")
}
