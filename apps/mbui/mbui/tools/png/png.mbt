// A PNG's pixels, as the checks of pictures read them: an 8-bit RGB or RGBA picture, its rows unfiltered.

///|
pub struct Picture {
  w : Int
  h : Int
  /// bytes a pixel: 3 RGB, 4 RGBA
  bpp : Int
  rows : Array[Bytes]
}

///|
/// The pixel at (x, y): its red, green and blue
pub fn Picture::rgb(self : Picture, x : Int, y : Int) -> (Int, Int, Int) {
  let r = self.rows[y]
  let i = x * self.bpp
  (r[i].to_int(), r[i + 1].to_int(), r[i + 2].to_int())
}

///|
fn be32(d : Bytes, i : Int) -> Int {
  (d[i].to_int() << 24) | (d[i + 1].to_int() << 16) | (d[i + 2].to_int() << 8) | d[i + 3].to_int()
}

///|
/// The PNG at `path`, or why not
pub fn read(path : String) -> Result[Picture, String] {
  let d = match @sys.read_bytes(path) {
    Some(d) => d
    None => return Err("\{path}: cannot be read")
  }
  let mut i = 8
  let mut w = 0
  let mut h = 0
  let mut depth = 0
  let mut ct = 0
  let idat = @buffer.new()
  while i + 8 <= d.length() {
    let n = be32(d, i)
    let t = d[i + 4:i + 8].to_bytes()
    if t == b"IHDR" {
      w = be32(d, i + 8)
      h = be32(d, i + 12)
      depth = d[i + 16].to_int()
      ct = d[i + 17].to_int()
    } else if t == b"IDAT" {
      idat.write_bytesview(d[i + 8:i + 8 + n])
    }
    i += 12 + n
  }
  if depth != 8 || (ct != 2 && ct != 6) {
    return Err("\{path}: not an 8-bit RGB(A) PNG")
  }
  let bpp = if ct == 6 { 4 } else { 3 }
  // (zlib's stream: its 2 bytes of head, then deflate's)
  let raw = match inflate(idat.to_bytes(), start=2) {
    Some(r) => r
    None => return Err("\{path}: its pixels do not inflate")
  }
  let stride = w * bpp
  if raw.length() < h * (stride + 1) {
    return Err("\{path}: fewer pixels than its size")
  }
  let rows = []
  let mut prev = FixedArray::make(stride, b'\x00')
  for y in 0..<h {
    let at = y * (stride + 1)
    let f = raw[at].to_int()
    let line = FixedArray::make(stride, b'\x00')
    for x in 0..<stride {
      let v = raw[at + 1 + x].to_int()
      let a = if x >= bpp { line[x - bpp].to_int() } else { 0 }
      let b = prev[x].to_int()
      let c = if x >= bpp { prev[x - bpp].to_int() } else { 0 }
      let o = match f {
        1 => v + a
        2 => v + b
        3 => v + (a + b) / 2
        4 => {
          let p = a + b - c
          let pa = (p - a).abs()
          let pb = (p - b).abs()
          let pc = (p - c).abs()
          v + (if pa <= pb && pa <= pc { a } else if pb <= pc { b } else { c })
        }
        _ => v
      }
      line[x] = (o & 255).to_byte()
    }
    rows.push(Bytes::from_fixedarray(line))
    prev = line
  }
  Ok({ w, h, bpp, rows })
}
