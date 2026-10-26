// mbui/pixels' PNG written a few rows at a time: what it deflated inflated again (mbui/zip) and unfiltered is the
// pixels it was given, its check right, the codes it made whole and none too long.

///|
fn be32(a : Array[Byte], at : Int) -> Int {
  (a[at].to_int() << 24) | (a[at + 1].to_int() << 16) | (a[at + 2].to_int() << 8) | a[at + 3].to_int()
}

///|
/// A PNG's size and its pixels as RGB: its IDATs' bytes inflated, its Adler-32 checked, each row unfiltered.
fn png_rgb(png : Bytes) -> (Int, Int, Array[Int]) {
  let a = png.to_array()
  let w = be32(a, 16)
  let h = be32(a, 20)
  let z : Array[Byte] = []
  let mut at = 8
  while at < a.length() {
    let len = be32(a, at)
    if a[at + 4] == b'I' && a[at + 5] == b'D' && a[at + 6] == b'A' && a[at + 7] == b'T' {
      for i in 0..<len {
        z.push(a[at + 8 + i])
      }
    }
    at = at + 12 + len
  }
  let raw = @zip.inflate(Bytes::from_array(z), start=2).unwrap().to_array()
  let mut s1 = 1
  let mut s2 = 0
  for v in raw {
    s1 = (s1 + v.to_int()) % 65521
    s2 = (s2 + s1) % 65521
  }
  if be32(z, z.length() - 4) != ((s2 << 16) | s1) {
    abort("its Adler-32 is not what was deflated")
  }
  let n = w * 3
  if raw.length() != h * (n + 1) {
    abort("not as many rows as its height")
  }
  let out : Array[Int] = Array::make(w * h * 3, 0)
  for y in 0..<h {
    let f = raw[y * (n + 1)].to_int()
    for i in 0..<n {
      let x = raw[y * (n + 1) + 1 + i].to_int()
      let a = if i >= 3 { out[y * n + i - 3] } else { 0 }
      let b = if y > 0 { out[(y - 1) * n + i] } else { 0 }
      let c = if i >= 3 && y > 0 { out[(y - 1) * n + i - 3] } else { 0 }
      let p = match f {
        0 => 0
        1 => a
        2 => b
        3 => (a + b) / 2
        _ => paeth(a, b, c)
      }
      out[y * n + i] = (x + p) & 0xFF
    }
  }
  (w, h, out)
}

///|
/// A picture `w` × `h` of `pixel(x, y)`'s colour (0xRRGGBB), written `step` rows at a time.
fn written(w : Int, h : Int, step : Int, pixel : (Int, Int) -> Int) -> (Bytes, Array[Int]) {
  let p = PngRows::new(w, h)
  let want : Array[Int] = []
  let mut y = 0
  while y < h {
    let k = if h - y < step { h - y } else { step }
    let band = FixedArray::make(w * k * 4, b'\xFF')
    for r in 0..<k {
      for x in 0..<w {
        let c = pixel(x, y + r)
        band[(r * w + x) * 4] = ((c >> 16) & 0xFF).to_byte()
        band[(r * w + x) * 4 + 1] = ((c >> 8) & 0xFF).to_byte()
        band[(r * w + x) * 4 + 2] = (c & 0xFF).to_byte()
        want.push((c >> 16) & 0xFF)
        want.push((c >> 8) & 0xFF)
        want.push(c & 0xFF)
      }
    }
    p.add(band, k)
    y = y + k
  }
  (p.end(), want)
}

///|
test "a PNG of noise, written a few rows at a time over many blocks, is its pixels again" {
  let mut seed = 12345
  let noise : Array[Int] = []
  for _ in 0..<(211 * 197) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    noise.push(seed >> 7)
  }
  let (png, want) = written(211, 197, 7, fn(x, y) { noise[y * 211 + x] & 0xFFFFFF })
  let (w, h, got) = png_rgb(png)
  assert_eq((w, h), (211, 197))
  assert_true(got == want)
}

///|
test "a PNG of what a screen shows (its ground, a few lines of marks on it) is a small part of its pixels" {
  let pixel = fn(x : Int, y : Int) {
    if y % 40 < 14 && x % 9 < 6 && x > 20 && x < 300 {
      // marks of a word's grey, a little different each line
      0x202020 + (y / 40) * 0x010101 + (x % 3) * 0x101010
    } else {
      0xF7F5F2
    }
  }
  let (png, want) = written(360, 2000, 501, pixel)
  let (_, _, got) = png_rgb(png)
  assert_true(got == want)
  // (360 × 2000 × 3 is 2 160 000 bytes)
  assert_true(png.length() < 40000, msg="\{png.length()} bytes")
}

///|
test "a PNG of one colour, one row, and of rows given past its height" {
  let (one, want) = written(5, 1, 1, fn(_, _) { 0x112233 })
  assert_true(png_rgb(one).2 == want)
  let p = PngRows::new(2, 2)
  p.add(FixedArray::make(2 * 3 * 4, b'\x40'), 3)
  assert_eq(p.rows(), 2)
  assert_true(png_rgb(p.end()).2 == Array::make(12, 0x40))
}

///|
test "Huffman lengths: none longer than said, the code whole (Kraft's sum one)" {
  // counts doubling: a tree 24 deep unless held to 15, and to 7
  let f = FixedArray::make(30, 0)
  for i in 0..<24 {
    f[i] = 1 << i
  }
  for most in [15, 7] {
    let l = huff_lengths(f, most)
    let mut kraft = 0
    for i in 0..<30 {
      if f[i] > 0 {
        assert_true(l[i] >= 1 && l[i] <= most)
        kraft = kraft + (1 << (most - l[i]))
      } else {
        assert_eq(l[i], 0)
      }
    }
    assert_eq(kraft, 1 << most)
  }
}
