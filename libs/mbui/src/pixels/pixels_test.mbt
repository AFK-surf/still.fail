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
  a[at + 2 + len:a.length() - 2].to_owned()
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

///|
test "a ThumbHash drawn back as the reference does, and its proportions" {
  // the size, the first two pixels and the one at (11, 16), as the npm package thumbhash's thumbHashToRGBA gives them
  // for 1QcSHQRnh493V4dIh4eXh1h4kJUI
  let hash = b"\xd5\x07\x12\x1d\x04\x67\x87\x8f\x77\x57\x87\x48\x87\x87\x97\x87\x58\x78\x90\x95\x08"
  guard @pixels.thumbhash(hash) is Some((w, h, rgba)) else { fail("no picture") }
  let first = []
  for i in 0..<8 {
    first.push(rgba[i].to_int())
  }
  let mid = []
  for i in 0..<4 {
    mid.push(rgba[(w * 16 + 11) * 4 + i].to_int())
  }
  inspect(
    "\{w}x\{h} [\{first.map(fn(x) { x.to_string() }).join(", ")}] [\{mid.map(fn(x) { x.to_string() }).join(", ")}]",
    content="23x32 [64, 77, 113, 255, 66, 79, 114, 255] [140, 109, 88, 255]",
  )
  // thumbHashToApproximateAspectRatio: 5 / 7
  assert_eq(@pixels.thumbhash_ratio(hash), Some(5.0 / 7.0))
  assert_eq(@pixels.thumbhash(b"\x01\x02"), None)
}

///|
/// An APP1 EXIF note saying `orientation`, its TIFF in Intel's byte order (`le`) or Motorola's.
fn exif_note(orientation : Int, le : Bool) -> Array[Byte] {
  let u16 = fn(n : Int) -> Array[Byte] {
    if le {
      [(n & 255).to_byte(), (n >> 8).to_byte()]
    } else {
      [(n >> 8).to_byte(), (n & 255).to_byte()]
    }
  }
  let u32 = fn(n : Int) -> Array[Byte] {
    if le {
      u16(n & 0xFFFF) + u16(n >> 16)
    } else {
      u16(n >> 16) + u16(n & 0xFFFF)
    }
  }
  let order : Array[Byte] = if le { [b'I', b'I'] } else { [b'M', b'M'] }
  // its first directory: an image width, then the orientation (SHORT, one), no next
  let tiff = order + u16(42) + u32(8) + u16(2) + u16(0x0100) + u16(3) + u32(1) + u16(20) + u16(0) +
    u16(0x0112) + u16(3) + u32(1) + u16(orientation) + u16(0) + u32(0)
  let body : Array[Byte] = [b'E', b'x', b'i', b'f', b'\x00', b'\x00'] + tiff
  let len = body.length() + 2
  [b'\xFF', b'\xE1', (len >> 8).to_byte(), (len & 255).to_byte()] + body
}

///|
test "a JPEG's size as it is shown: its frame's, turned a quarter where its EXIF says" {
  let a = @pixels.jpeg(20, 9, FixedArray::make(20 * 9 * 4, b'\xFF')).to_array()
  let noted = fn(note : Array[Byte]) { Bytes::from_array(a[0:2].to_owned() + note + a[2:].to_owned()) }
  assert_eq(@pixels.image_size(Bytes::from_array(a)), Some((20, 9)))
  assert_eq(@pixels.image_size(noted(exif_note(6, true))), Some((9, 20)))
  assert_eq(@pixels.image_size(noted(exif_note(8, false))), Some((9, 20)))
  assert_eq(@pixels.image_size(noted(exif_note(3, true))), Some((20, 9)))
  assert_eq(@pixels.image_size(noted(exif_note(1, false))), Some((20, 9)))
}

///|
fn isobmff_box(tag : String, body : Array[Byte], full? : Int = -1) -> Array[Byte] {
  let head = if full >= 0 {
    [(full >> 24).to_byte(), ((full >> 16) & 255).to_byte(), ((full >> 8) & 255).to_byte(), (full & 255).to_byte()]
  } else {
    []
  }
  let n = 8 + head.length() + body.length()
  let b32 = fn(v : Int) -> Array[Byte] {
    [(v >> 24).to_byte(), ((v >> 16) & 255).to_byte(), ((v >> 8) & 255).to_byte(), (v & 255).to_byte()]
  }
  let t = tag.to_array().map(fn(c) { c.to_int().to_byte() })
  b32(n) + t + head + body
}

///|
fn heic_sample(brand : String, w : Int, h : Int, rot? : Int = -1, thumb? : (Int, Int)) -> Bytes {
  let b32 = fn(v : Int) -> Array[Byte] {
    [(v >> 24).to_byte(), ((v >> 16) & 255).to_byte(), ((v >> 8) & 255).to_byte(), (v & 255).to_byte()]
  }
  let b16 = fn(v : Int) -> Array[Byte] { [((v >> 8) & 255).to_byte(), (v & 255).to_byte()] }
  let tag = fn(s : String) -> Array[Byte] { s.to_array().map(fn(c) { c.to_int().to_byte() }) }
  let ftyp = isobmff_box("ftyp", tag(brand) + b32(0) + tag("mif1") + tag(brand))
  let mut props : Array[Byte] = []
  let mut main_idx = 1
  match thumb {
    Some((tw, th)) => {
      // thumbnail property #1 comes before primary image property #2
      props = props + isobmff_box("ispe", b32(tw) + b32(th), full=0)
      main_idx = 2
    }
    None => ()
  }
  props = props + isobmff_box("ispe", b32(w) + b32(h), full=0)
  let assoc = if rot >= 0 {
    props = props + isobmff_box("irot", [(rot & 3).to_byte()])
    [main_idx.to_byte(), (0x80 | (main_idx + 1)).to_byte()]
  } else {
    [main_idx.to_byte()]
  }
  let ipco = isobmff_box("ipco", props)
  // primary item id = 2 (after thumbnail item 1), ipma v0 flags 0: entry_count=1, item_id=2, assoc_count, indices
  let ipma = isobmff_box("ipma", b32(1) + b16(2) + [assoc.length().to_byte()] + assoc, full=0)
  let pitm = isobmff_box("pitm", b16(2), full=0)
  let iprp = isobmff_box("iprp", ipco + ipma)
  let meta = isobmff_box("meta", pitm + iprp, full=0)
  Bytes::from_array(ftyp + meta)
}

///|
test "a HEIC or AVIF picture's size as it is shown: its primary item's ispe, turned a quarter where its irot says" {
  assert_eq(@pixels.image_size(heic_sample("heic", 4032, 3024)), Some((4032, 3024)))
  assert_eq(@pixels.image_size(heic_sample("heic", 4032, 3024, rot=1)), Some((3024, 4032)))
  assert_eq(@pixels.image_size(heic_sample("heic", 4032, 3024, rot=2)), Some((4032, 3024)))
  assert_eq(@pixels.image_size(heic_sample("heic", 4032, 3024, rot=3, thumb=(512, 384))), Some((3024, 4032)))
  assert_eq(@pixels.image_size(heic_sample("avif", 1920, 1080)), Some((1920, 1080)))
}
