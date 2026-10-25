// A linear gradient's ground, as CSS's linear-gradient(angle, from, to) paints a box (the notifications page's preview,
// web/src/pages/Notifications.css.ts screen): mbui's renderer has no gradient fill yet, so it is a small picture of
// the gradient made here from its two colours (sRGB, as CSS mixes them), laid stretched over the box. When mbui fills
// gradients itself, this goes onto that.

///|
/// The pictures made, by what they are made of (their key says it all: the same picture each time it is asked for).
// kept across runs: a cache by content; what is in it never changes for a key
let gradients_made : Map[String, Bool] = {}

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
  if !gradients_made.contains(key) {
    gradients_made[key] = true
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

///|
/// A soft light on a ground (`glow_ground`): where its middle is, as shares of the box's width and height, how far it
/// reaches as a share of its width, its colour (its alpha how strong it is at its middle).
pub(all) struct Glow {
  x : Double
  y : Double
  r : Double
  color : Int64
}

///|
/// How many pixels across a glow's picture is made (its height in `aspect`'s proportion): lights fade slowly, so few
/// are needed, each stretched.
let glow_px : Int = 96

///|
/// A ground of `ground` with soft `lights` over it (a picture to share's: the web's radial-gradient()s over a colour),
/// filling the box it is in (a box placed over the whole of another: left, top, right, bottom 0), its picture made in
/// the box's proportion `aspect` (width over height) and stretched over it, round by `radius`.
pub fn glow_ground(c : @ui.Ctx, ground : Int64, lights : Array[Glow], aspect : Double, radius? : Double = 0.0) -> Unit {
  let pw = glow_px
  let ph = dmax_int(2, (pw.to_double() / (if aspect <= 0.0 { 1.0 } else { aspect })).round().to_int())
  let parts = lights.map(fn(g) { "\{g.x},\{g.y},\{g.r},\{g.color}" }).join(";")
  let key = "mem:sf-glow/\{ground}/\{parts}/\{pw}x\{ph}"
  if !gradients_made.contains(key) {
    gradients_made[key] = true
    @ui.add_image(key, @pixels.png(pw, ph, glow_pixels(pw, ph, ground, lights)))
  }
  c.image(key, w=Fill(1.0), h=Fill(1.0), fit=FitFill, radius~, bg=0L, fade=false) |> ignore
}

///|
/// The glow's pixels (RGBA, row by row, opaque): each light laid over the ground in turn, its strength falling from its
/// middle to nothing at its reach as (1 - d²/r²)², distances in the width's units.
fn glow_pixels(pw : Int, ph : Int, ground : Int64, lights : Array[Glow]) -> FixedArray[Byte] {
  let px = FixedArray::make(pw * ph * 4, b'\x00')
  let chan = fn(c : Int64, k : Int) { ((c >> (24 - k * 8)) & 0xFFL).to_double() }
  let w = pw.to_double()
  for j in 0..<ph {
    for i in 0..<pw {
      let u = (i.to_double() + 0.5) / w
      let v = (j.to_double() + 0.5) / w
      let rgb = [chan(ground, 0), chan(ground, 1), chan(ground, 2)]
      for g in lights {
        let dx = u - g.x
        let dy = v - g.y * ph.to_double() / w
        let q = (dx * dx + dy * dy) / (g.r * g.r)
        if q >= 1.0 {
          continue
        }
        let a = chan(g.color, 3) / 255.0 * (1.0 - q) * (1.0 - q)
        for k in 0..<3 {
          rgb[k] = rgb[k] + (chan(g.color, k) - rgb[k]) * a
        }
      }
      let o = (j * pw + i) * 4
      for k in 0..<3 {
        px[o + k] = rgb[k].round().to_int().to_byte()
      }
      px[o + 3] = b'\xFF'
    }
  }
  px
}
