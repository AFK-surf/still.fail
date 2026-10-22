// Pixels made here written as a PNG (a picture to hand to the host, as @ui.add_image takes it, or to a clipboard): its
// rows in stored deflate blocks, nothing compressed (what is made here is small; every decoder reads it).

///|
// kept across runs: a table, never written
let png_crc_table : FixedArray[UInt] = {
  let t = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c = n.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    t[n] = c
  }
  t
}

///|
priv struct PngOut {
  buf : Array[Byte]
}

///|
fn PngOut::byte(self : PngOut, v : Int) -> Unit {
  self.buf.push((v & 0xFF).to_byte())
}

///|
fn PngOut::u32(self : PngOut, v : UInt) -> Unit {
  self.byte((v >> 24).reinterpret_as_int())
  self.byte((v >> 16).reinterpret_as_int())
  self.byte((v >> 8).reinterpret_as_int())
  self.byte(v.reinterpret_as_int())
}

///|
fn PngOut::chunk(self : PngOut, kind : String, data : Array[Byte]) -> Unit {
  self.u32(data.length().reinterpret_as_uint())
  let start = self.buf.length()
  for ch in kind {
    self.byte(ch.to_int())
  }
  for b in data {
    self.buf.push(b)
  }
  let mut c = 0xFFFFFFFFU
  for i in start..<self.buf.length() {
    c = png_crc_table[((c ^ self.buf[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^
      (c >> 8)
  }
  self.u32(c ^ 0xFFFFFFFFU)
}

///|
/// RGBA pixels (`w` × `h`, straight alpha, rows from the top) as a PNG (stored, not compressed: small pictures made
/// here, decoded anywhere), to hand to @ui.add_image.
pub fn png(w : Int, h : Int, rgba : FixedArray[Byte]) -> Bytes {
  let o : PngOut = { buf: [] }
  for b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    o.byte(b)
  }
  let ihdr : PngOut = { buf: [] }
  ihdr.u32(w.reinterpret_as_uint())
  ihdr.u32(h.reinterpret_as_uint())
  for b in [8, 6, 0, 0, 0] {
    ihdr.byte(b)
  }
  o.chunk("IHDR", ihdr.buf)
  // the rows, each after its filter byte (none), in stored deflate blocks
  let raw : Array[Byte] = []
  for y in 0..<h {
    raw.push(b'\x00')
    for x in 0..<(w * 4) {
      raw.push(rgba[y * w * 4 + x])
    }
  }
  let z : PngOut = { buf: [] }
  z.byte(0x78)
  z.byte(0x01)
  let mut at = 0
  while at < raw.length() || at == 0 {
    let n = if raw.length() - at > 65535 { 65535 } else { raw.length() - at }
    z.byte(if at + n >= raw.length() { 1 } else { 0 })
    z.byte(n & 0xFF)
    z.byte(n >> 8)
    z.byte(n.lnot() & 0xFF)
    z.byte((n.lnot() >> 8) & 0xFF)
    for i in at..<(at + n) {
      z.buf.push(raw[i])
    }
    at = at + n
    if n == 0 {
      break
    }
  }
  let mut a = 1U
  let mut b = 0U
  for v in raw {
    a = (a + v.to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  z.u32((b << 16) | a)
  o.chunk("IDAT", z.buf)
  o.chunk("IEND", [])
  Bytes::from_array(o.buf)
}

