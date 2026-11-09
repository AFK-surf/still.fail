// A picture made of paths (an SVG's, an Android vector drawable's): its viewport and its paths in order, each filled
// and stroked in its colours, where the groups it is in put it. Drawn by the GPU as shapes (@ui.vector_shapes), or
// here on the CPU into straight RGBA (Vector::rgba: a picture to hand on, as an app's icon), every colour in a tint's
// where one is given.

///|
/// One path of a picture: its data (`d`, svg_path's), its fill and stroke (0xRRGGBBAA, 0: none), the stroke's width,
/// the fill's rule, and where its groups put it (scaled by `sx`, `sy`, then moved by `tx`, `ty`).
pub(all) struct VectorPath {
  d : String
  fill : Int64
  stroke : Int64
  width : Double
  even_odd : Bool
  sx : Double
  sy : Double
  tx : Double
  ty : Double
} derive(Eq, Show, Debug)

///|
/// A picture: its viewport (`w` × `h`) and its paths, drawn in order.
pub(all) struct Vector {
  w : Double
  h : Double
  layers : Array[VectorPath]
} derive(Eq, Show, Debug)

///|
/// The outlines of `l` in the viewport's units times `k`, cut for drawing at `scale` pixels a unit of that.
pub fn VectorPath::outlines(self : VectorPath, k : Double, scale : Double) -> Array[(Array[Double], Bool)] {
  let l = self
  svg_path(l.d, cover_dmax(k * l.sx, k * l.sy) * scale).map(fn(sub) {
    let (pts, closed) = sub
    let moved = Array::make(pts.length(), 0.0)
    let mut j = 0
    while j + 1 < pts.length() {
      moved[j] = (pts[j] * l.sx + l.tx) * k
      moved[j + 1] = (pts[j + 1] * l.sy + l.ty) * k
      j += 2
    }
    (moved, closed)
  })
}

///|
/// `color` with `tint`'s red, green and blue (its alpha times both).
pub fn tinted(color : Int64, tint : Int64?) -> Int64 {
  match tint {
    None => color
    Some(t) => {
      let a = (color & 0xFFL).to_double() * (t & 0xFFL).to_double() / 255.0
      (t & 0xFFFFFF00L) | a.round().to_int64()
    }
  }
}

///|
/// `color` over the premultiplied `out` where `cover` says, then `cover`
/// cleared.
fn composite(
  out : FixedArray[Double],
  cover : FixedArray[Double],
  color : Int64,
) -> Unit {
  let r = ((color >> 24) & 0xFFL).to_double() / 255.0
  let g = ((color >> 16) & 0xFFL).to_double() / 255.0
  let b = ((color >> 8) & 0xFFL).to_double() / 255.0
  let a = (color & 0xFFL).to_double() / 255.0
  for i in 0..<cover.length() {
    let c = cover[i]
    if c > 0.0 {
      let sa = (if c > 1.0 { 1.0 } else { c }) * a
      let k = 1.0 - sa
      out[i * 4] = r * sa + out[i * 4] * k
      out[i * 4 + 1] = g * sa + out[i * 4 + 1] * k
      out[i * 4 + 2] = b * sa + out[i * 4 + 2] * k
      out[i * 4 + 3] = sa + out[i * 4 + 3] * k
      cover[i] = 0.0
    }
  }
}

///|
/// The picture drawn `pw` × `ph` pixels: straight RGBA, rows from the top, every colour in `tint`'s when it is given.
pub fn Vector::rgba(self : Vector, pw : Int, ph : Int, tint? : Int64) -> FixedArray[Byte] {
  let d = self
  let out = FixedArray::make(pw * ph * 4, 0.0)
  let cover = FixedArray::make(pw * ph, 0.0)
  let kx = pw.to_double() / d.w
  let ky = ph.to_double() / d.h
  for l in d.layers {
    let scale = cover_dmax(kx * l.sx, ky * l.sy)
    let subs = svg_path(l.d, scale).map(fn(sub) {
      let (pts, closed) = sub
      let moved = Array::make(pts.length(), 0.0)
      let mut k = 0
      while k + 1 < pts.length() {
        moved[k] = (pts[k] * l.sx + l.tx) * kx
        moved[k + 1] = (pts[k + 1] * l.sy + l.ty) * ky
        k += 2
      }
      (moved, closed)
    })
    if l.fill != 0L {
      fill_cover(cover, pw, ph, subs.map(fn(s) { s.0 }), even_odd=l.even_odd)
      composite(out, cover, tinted(l.fill, tint))
    }
    if l.stroke != 0L && l.width > 0.0 {
      let hw = l.width * l.sx * kx / 2.0
      for s in subs {
        stroke_cover(cover, pw, ph, s.0, s.1, hw)
      }
      composite(out, cover, tinted(l.stroke, tint))
    }
  }
  let rgba = FixedArray::make(pw * ph * 4, b'\x00')
  for i in 0..<(pw * ph) {
    let a = out[i * 4 + 3]
    if a > 0.0 {
      for ch in 0..<3 {
        let v = out[i * 4 + ch] / a * 255.0
        rgba[i * 4 + ch] = (if v > 255.0 { 255.0 } else { v })
          .round()
          .to_int()
          .to_byte()
      }
      rgba[i * 4 + 3] = ((if a > 1.0 { 1.0 } else { a }) * 255.0)
        .round()
        .to_int()
        .to_byte()
    }
  }
  rgba
}

