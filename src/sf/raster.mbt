// Line art drawn here, not by the host: still.fail's icons (24 grid strokes
// and fills, icon_data.mbt) and the spinner's ring, rasterised to RGBA at
// the pixels they show at and handed to the host as a PNG (stored, not
// compressed: small, and decoded everywhere).

///|
/// Shapes in a `unit`-wide square: strokes (width, points, closed) and fills
/// (subpaths, filled by the nonzero rule).
priv struct Art {
  unit : Double
  segs : Array[Double] // x0 y0 x1 y1 half-width, per segment
  fills : Array[Array[Array[Double]]] // fills, each its subpaths (x y …)
}

///|
fn Art::new(unit : Double) -> Art {
  { unit, segs: [], fills: [] }
}

///|
fn Art::stroke(self : Art, pts : Array[Double], width : Double, closed : Bool) -> Unit {
  let n = pts.length() / 2
  if n == 1 {
    // a dot: a zero-length segment, round
    self.segs.append([pts[0], pts[1], pts[0], pts[1], width / 2.0])
    return
  }
  for k in 0..<(n - 1) {
    self.segs.append([
      pts[2 * k],
      pts[2 * k + 1],
      pts[2 * k + 2],
      pts[2 * k + 3],
      width / 2.0,
    ])
  }
  if closed {
    self.segs.append([pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1], width / 2.0])
  }
}

///|
/// Parts as icon_data.mbt has them.
fn Art::parts(self : Art, data : Array[Double]) -> Unit {
  let mut i = 0
  while i + 2 < data.length() {
    let kind = data[i].to_int()
    let w = data[i + 1]
    let n = data[i + 2].to_int()
    let pts = data[i + 3:i + 3 + 2 * n].to_array()
    i = i + 3 + 2 * n
    if kind == 2 {
      // the first subpath of a fill says how many it has
      if w > 0.0 || self.fills.length() == 0 {
        self.fills.push([pts])
      } else {
        self.fills[self.fills.length() - 1].push(pts)
      }
    } else {
      self.stroke(pts, w, kind == 1)
    }
  }
}

///|
fn seg_dist(px : Double, py : Double, s : Array[Double], k : Int) -> Double {
  let ax = s[k]
  let ay = s[k + 1]
  let dx = s[k + 2] - ax
  let dy = s[k + 3] - ay
  let l2 = dx * dx + dy * dy
  let t = if l2 <= 0.0 {
    0.0
  } else {
    let v = ((px - ax) * dx + (py - ay) * dy) / l2
    if v < 0.0 {
      0.0
    } else if v > 1.0 {
      1.0
    } else {
      v
    }
  }
  let qx = ax + t * dx - px
  let qy = ay + t * dy - py
  (qx * qx + qy * qy).sqrt()
}

///|
fn winding(px : Double, py : Double, subs : Array[Array[Double]]) -> Int {
  let mut w = 0
  for pts in subs {
    let n = pts.length() / 2
    for k in 0..<n {
      let j = (k + 1) % n
      let x0 = pts[2 * k]
      let y0 = pts[2 * k + 1]
      let x1 = pts[2 * j]
      let y1 = pts[2 * j + 1]
      if y0 <= py {
        if y1 > py && (x1 - x0) * (py - y0) - (px - x0) * (y1 - y0) > 0.0 {
          w = w + 1
        }
      } else if y1 <= py && (x1 - x0) * (py - y0) - (px - x0) * (y1 - y0) < 0.0 {
        w = w - 1
      }
    }
  }
  w
}

///|
/// The art at `px` pixels square: its coverage, 0 to 1, per pixel.
fn Art::cover(self : Art, px : Int) -> FixedArray[Double] {
  let out = FixedArray::make(px * px, 0.0)
  let k = self.unit / px.to_double() // units a pixel
  let nseg = self.segs.length() / 5
  for y in 0..<px {
    for x in 0..<px {
      let ux = (x.to_double() + 0.5) * k
      let uy = (y.to_double() + 0.5) * k
      let mut c = 0.0
      for s in 0..<nseg {
        let d = seg_dist(ux, uy, self.segs, s * 5)
        // how far inside the stroke's edge, in pixels: half a pixel either
        // side is the ramp
        let v = (self.segs[s * 5 + 4] - d) / k + 0.5
        if v > c {
          c = if v > 1.0 { 1.0 } else { v }
          if c >= 1.0 {
            break
          }
        }
      }
      if c < 1.0 && self.fills.length() > 0 {
        // 4×4 samples
        let mut inside = 0
        for sy in 0..<4 {
          for sx in 0..<4 {
            let fx = (x.to_double() + (sx.to_double() + 0.5) / 4.0) * k
            let fy = (y.to_double() + (sy.to_double() + 0.5) / 4.0) * k
            for f in self.fills {
              if winding(fx, fy, f) != 0 {
                inside = inside + 1
                break
              }
            }
          }
        }
        let fc = inside.to_double() / 16.0
        if fc > c {
          c = fc
        }
      }
      out[y * px + x] = c
    }
  }
  out
}

// ---------------------------------------------------------------------------
// PNG

///|
let crc_table : FixedArray[UInt] = {
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
priv struct Out {
  buf : Array[Byte]
}

///|
fn Out::byte(self : Out, v : Int) -> Unit {
  self.buf.push((v & 0xFF).to_byte())
}

///|
fn Out::u32(self : Out, v : UInt) -> Unit {
  self.byte((v >> 24).reinterpret_as_int())
  self.byte((v >> 16).reinterpret_as_int())
  self.byte((v >> 8).reinterpret_as_int())
  self.byte(v.reinterpret_as_int())
}

///|
fn Out::chunk(self : Out, kind : String, data : Array[Byte]) -> Unit {
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
    c = crc_table[((c ^ self.buf[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^
      (c >> 8)
  }
  self.u32(c ^ 0xFFFFFFFFU)
}

///|
/// RGBA pixels (`w` × `h`, straight alpha) as a PNG.
fn png(w : Int, h : Int, rgba : FixedArray[Byte]) -> Bytes {
  let o = { buf: [] }
  for b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    o.byte(b)
  }
  let ihdr = { buf: [] }
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
  let z = { buf: [] }
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

///|
/// The coverage in `color` (0xRRGGBBAA) as a PNG `px` square.
fn tinted_png(cover : FixedArray[Double], px : Int, color : Int64) -> Bytes {
  let rgba = FixedArray::make(px * px * 4, b'\x00')
  let r = ((color >> 24) & 0xFFL).to_int()
  let g = ((color >> 16) & 0xFFL).to_int()
  let b = ((color >> 8) & 0xFFL).to_int()
  let a = (color & 0xFFL).to_double()
  for i in 0..<(px * px) {
    let c = cover[i]
    if c > 0.0 {
      rgba[i * 4] = r.to_byte()
      rgba[i * 4 + 1] = g.to_byte()
      rgba[i * 4 + 2] = b.to_byte()
      rgba[i * 4 + 3] = (c * a).round().to_int().to_byte()
    }
  }
  png(px, px, rgba)
}
