// A picture made from others, pixel by pixel (an app's icon: a colour, a picture drawn over it as large as fits),
// worked out here in the same numbers on every host: RGBA, premultiplied, rows from the top. A picture is drawn into
// a rect of it smoothly: each pixel the mean of samples spread over what it covers of the picture (as many across as
// the picture has pixels to one of the canvas's, up to 8), each sample between the four pixels nearest it.

///|
/// A picture being made.
pub struct Canvas {
  w : Int
  h : Int
  /// RGBA, premultiplied, rows from the top
  px : FixedArray[Byte]
}

///|
/// `w` × `h`, clear.
pub fn Canvas::new(w : Int, h : Int) -> Canvas {
  { w, h, px: FixedArray::make(w * h * 4, b'\x00') }
}

///|
/// Its pixels (RGBA, premultiplied, rows from the top).
pub fn Canvas::pixels(self : Canvas) -> FixedArray[Byte] {
  self.px
}

///|
/// All of it `color` (0xRRGGBBAA).
pub fn Canvas::fill(self : Canvas, color : Int64) -> Unit {
  let a = (color & 0xFFL).to_int()
  let ch = fn(shift : Int) { (((color >> shift) & 0xFFL).to_int() * a + 127) / 255 }
  let (r, g, b) = (ch(24), ch(16), ch(8))
  for i in 0..<(self.w * self.h) {
    self.px[i * 4] = r.to_byte()
    self.px[i * 4 + 1] = g.to_byte()
    self.px[i * 4 + 2] = b.to_byte()
    self.px[i * 4 + 3] = a.to_byte()
  }
}

///|
/// The part `from` (x0, y0, x1, y1, in its pixels) of the picture `src` (`sw` × `sh`, RGBA, rows from the top;
/// premultiplied unless said) drawn over what is here into the rect `to` (x0, y0, x1, y1, in this one's pixels).
pub fn Canvas::draw(
  self : Canvas,
  sw : Int,
  sh : Int,
  src : FixedArray[Byte],
  from : (Int, Int, Int, Int),
  to : (Double, Double, Double, Double),
  premultiplied? : Bool = true,
) -> Unit {
  let (fx0, fy0, fx1, fy1) = from
  let (tx0, ty0, tx1, ty1) = to
  if fx1 <= fx0 || fy1 <= fy0 || tx1 <= tx0 || ty1 <= ty0 {
    return
  }
  // source pixels to one of these, across and down
  let kx = (fx1 - fx0).to_double() / (tx1 - tx0)
  let ky = (fy1 - fy0).to_double() / (ty1 - ty0)
  let nx = clamp_int(kx.ceil().to_int(), 1, 8)
  let ny = clamp_int(ky.ceil().to_int(), 1, 8)
  // a channel of the source's pixel (x, y), kept inside `from`, premultiplied
  let at = fn(x : Int, y : Int, c : Int) -> Double {
    let x = clamp_int(x, fx0, fx1 - 1)
    let y = clamp_int(y, fy0, fy1 - 1)
    let i = (y * sw + x) * 4
    let v = src[i + c].to_int().to_double()
    if premultiplied || c == 3 {
      v
    } else {
      v * src[i + 3].to_int().to_double() / 255.0
    }
  }
  let px0 = clamp_int(tx0.floor().to_int(), 0, self.w)
  let px1 = clamp_int(tx1.ceil().to_int(), 0, self.w)
  let py0 = clamp_int(ty0.floor().to_int(), 0, self.h)
  let py1 = clamp_int(ty1.ceil().to_int(), 0, self.h)
  let sum = FixedArray::make(4, 0.0)
  for py in py0..<py1 {
    for px in px0..<px1 {
      // how much of this pixel the rect covers (its edges cut across)
      let cover = overlap(px.to_double(), tx0, tx1) * overlap(py.to_double(), ty0, ty1)
      if cover <= 0.0 {
        continue
      }
      for c in 0..<4 {
        sum[c] = 0.0
      }
      for j in 0..<ny {
        for i in 0..<nx {
          // the sample, in the source's pixels (their middles at .5)
          let dx = px.to_double() + (i.to_double() + 0.5) / nx.to_double()
          let dy = py.to_double() + (j.to_double() + 0.5) / ny.to_double()
          let sx = fx0.to_double() + (dx - tx0) * kx - 0.5
          let sy = fy0.to_double() + (dy - ty0) * ky - 0.5
          let x0 = sx.floor().to_int()
          let y0 = sy.floor().to_int()
          let ax = sx - x0.to_double()
          let ay = sy - y0.to_double()
          for c in 0..<4 {
            let top = at(x0, y0, c) * (1.0 - ax) + at(x0 + 1, y0, c) * ax
            let bottom = at(x0, y0 + 1, c) * (1.0 - ax) + at(x0 + 1, y0 + 1, c) * ax
            sum[c] = sum[c] + top * (1.0 - ay) + bottom * ay
          }
        }
      }
      let n = (nx * ny).to_double()
      let o = (py * self.w + px) * 4
      let a = sum[3] / n / 255.0 * cover
      for c in 0..<4 {
        let s = sum[c] / n * cover
        let d = self.px[o + c].to_int().to_double()
        self.px[o + c] = clamp_int((s + d * (1.0 - a)).round().to_int(), 0, 255).to_byte()
      }
    }
  }
}

///|
/// How much of the pixel from `p` to `p` + 1 lies between `a` and `b`.
fn overlap(p : Double, a : Double, b : Double) -> Double {
  let lo = if a > p { a } else { p }
  let hi = if b < p + 1.0 { b } else { p + 1.0 }
  if hi > lo {
    hi - lo
  } else {
    0.0
  }
}

///|
fn clamp_int(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Where the picture `px` (`w` × `h`, RGBA) has anything drawn (more than 16 of 255 opaque): x0, y0, x1, y1 in its
/// pixels; all of it when nothing is.
pub fn drawn_box(w : Int, h : Int, px : FixedArray[Byte]) -> (Int, Int, Int, Int) {
  let mut x0 = w
  let mut y0 = h
  let mut x1 = -1
  let mut y1 = -1
  for y in 0..<h {
    for x in 0..<w {
      if px[(y * w + x) * 4 + 3].to_int() > 16 {
        if x < x0 {
          x0 = x
        }
        if x > x1 {
          x1 = x
        }
        if y < y0 {
          y0 = y
        }
        if y > y1 {
          y1 = y
        }
      }
    }
  }
  if x1 < 0 {
    (0, 0, w, h)
  } else {
    (x0, y0, x1 + 1, y1 + 1)
  }
}

///|
/// The colour a picture sits on best (still.fail's Android app, SlackApp.kt edgeColour): the mean of its edge, made 32
/// by 32 first, as #RRGGBB.
pub fn edge_colour(w : Int, h : Int, px : FixedArray[Byte]) -> String {
  let small = Canvas::new(32, 32)
  small.draw(w, h, px, (0, 0, w, h), (0.0, 0.0, 32.0, 32.0))
  let sum = [0, 0, 0]
  let mut n = 0
  for i in 0..<32 {
    for p in [(i, 0), (i, 31), (0, i), (31, i)] {
      let o = (p.1 * 32 + p.0) * 4
      for c in 0..<3 {
        sum[c] = sum[c] + small.px[o + c].to_int()
      }
      n = n + 1
    }
  }
  let hex = "0123456789ABCDEF"
  let sb = StringBuilder()
  sb.write_char('#')
  for c in 0..<3 {
    let v = sum[c] / n
    sb.write_char(hex[v >> 4].unsafe_to_char())
    sb.write_char(hex[v & 15].unsafe_to_char())
  }
  sb.to_string()
}
