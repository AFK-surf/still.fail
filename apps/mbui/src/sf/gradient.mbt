// A linear gradient's ground, as CSS's linear-gradient(angle, from, to) paints a box (the notifications page's preview,
// web/src/pages/Notifications.css.ts screen): mbui's renderer has no gradient fill yet, so it is a small picture of
// the gradient made here from its two colours (sRGB, as CSS mixes them), laid stretched over the box. When mbui fills
// gradients itself, this goes onto that.

///|
/// How many pixels across the picture is made (its height in the box's proportion): the colours change slowly, so few
/// are needed, each stretched.
let gradient_px : Int = 64

///|
/// A ground of the gradient from `from` to `to` at `angle` degrees (CSS's: 0 to the top, 90 to the right), for a box
/// about `w` by `h` (its proportion sets the gradient's line, as CSS's does), with corners of `radius`; as wide as its
/// parent and `h` high. Put behind what the box holds (first, in a box that lays what follows over it).
pub fn gradient(c : @ui.Ctx, w : Double, h : Double, angle : Double, from : Int64, to : Int64, radius? : Double = 0.0) -> Unit {
  let pw = gradient_px
  let ph = if w <= 0.0 { 2 } else { dmax_int(2, (h / w * pw.to_double()).round().to_int()) }
  let key = "mem:sf-gradient/\{from}/\{to}/\{angle}/\{pw}x\{ph}"
  // (made once: its key says it all, the same picture each time it is asked for)
  if !@ui.has_image(key) {
    @ui.add_image(key, @pixels.png(pw, ph, gradient_pixels(pw, ph, w, h, angle, from, to)))
  }
  c.image(key, w=Fill(1.0), h=Px(h), fit=FitFill, radius~, bg=0L, fade=false) |> ignore
}

///|
fn dmax_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// The gradient's pixels (RGBA, row by row), each where its middle falls on the box's `w` by `h`: along the line through
/// the box's middle at `angle`, as long as the box reaches that way (CSS's gradient line), `from` at its start.
fn gradient_pixels(pw : Int, ph : Int, w : Double, h : Double, angle : Double, from : Int64, to : Int64) -> FixedArray[Byte] {
  let a = angle * @math.PI / 180.0
  let (dx, dy) = (@dmath.sin(a), -@dmath.cos(a))
  let len = (w * dx).abs() + (h * dy).abs()
  let px = FixedArray::make(pw * ph * 4, b'\x00')
  for j in 0..<ph {
    for i in 0..<pw {
      let x = (i.to_double() + 0.5) / pw.to_double() * w - w / 2.0
      let y = (j.to_double() + 0.5) / ph.to_double() * h - h / 2.0
      let t = if len <= 0.0 { 0.0 } else { (x * dx + y * dy) / len + 0.5 }
      let t = if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t }
      let o = (j * pw + i) * 4
      for k in 0..<4 {
        let shift = 24 - k * 8
        let f = ((from >> shift) & 0xFFL).to_double()
        let g = ((to >> shift) & 0xFFL).to_double()
        px[o + k] = (f + (g - f) * t).round().to_int().to_byte()
      }
    }
  }
  px
}
