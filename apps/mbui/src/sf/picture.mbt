// Pictures as still.fail's Android app has them (drawable_data.mbt: its
// vector drawables, the station glyphs): paths filled and stroked, in order,
// rasterised here at the pixels they show at (once each size and tint) and
// handed to the host as a PNG, as the icons are.

///|
/// One path of a picture: its fill and stroke (0xRRGGBBAA, 0: none), the
/// stroke's width, the fill's rule, and where its groups put it (scaled,
/// then moved).
priv struct Layer {
  d : String
  fill : Int64
  stroke : Int64
  width : Double
  even_odd : Bool
  sx : Double
  sy : Double
  tx : Double
  ty : Double
}

///|
/// A picture: its viewport and its paths.
priv struct Drawable {
  w : Double
  h : Double
  layers : Array[Layer]
}

///|
/// How much of each pixel a filled path covers: 4 rows of samples a pixel,
/// the spans between the edges' crossings counted across exactly.
fn fill_cover(
  cover : FixedArray[Double],
  pw : Int,
  ph : Int,
  subs : Array[Array[Double]],
  even_odd : Bool,
) -> Unit {
  let mut y0 = 1.0e9
  let mut y1 = -1.0e9
  for pts in subs {
    let mut k = 1
    while k < pts.length() {
      if pts[k] < y0 {
        y0 = pts[k]
      }
      if pts[k] > y1 {
        y1 = pts[k]
      }
      k += 2
    }
  }
  let r0 = imax(y0.floor().to_int(), 0)
  let r1 = imin(y1.ceil().to_int(), ph - 1)
  let xs : Array[Double] = []
  let ws : Array[Int] = []
  for row in r0..=r1 {
    for sub in 0..<4 {
      let sy = row.to_double() + (sub.to_double() + 0.5) / 4.0
      xs.clear()
      ws.clear()
      for pts in subs {
        let n = pts.length() / 2
        for k in 0..<n {
          let j = (k + 1) % n
          let ax = pts[2 * k]
          let ay = pts[2 * k + 1]
          let bx = pts[2 * j]
          let by = pts[2 * j + 1]
          if (ay <= sy && by > sy) || (by <= sy && ay > sy) {
            xs.push(ax + (sy - ay) / (by - ay) * (bx - ax))
            ws.push(if by > ay { 1 } else { -1 })
          }
        }
      }
      if xs.length() < 2 {
        continue
      }
      // the crossings in order across (few: insertion)
      for a in 1..<xs.length() {
        let x = xs[a]
        let w = ws[a]
        let mut b = a - 1
        while b >= 0 && xs[b] > x {
          xs[b + 1] = xs[b]
          ws[b + 1] = ws[b]
          b -= 1
        }
        xs[b + 1] = x
        ws[b + 1] = w
      }
      let mut wind = 0
      for a in 0..<(xs.length() - 1) {
        wind += ws[a]
        let inside = if even_odd { wind % 2 != 0 } else { wind != 0 }
        if inside {
          span(cover, pw, row, xs[a], xs[a + 1], 0.25)
        }
      }
    }
  }
}

///|
/// Coverage `k` added across [xa, xb) of pixel row `row`: the pixels it
/// covers part of, by that part.
fn span(
  cover : FixedArray[Double],
  pw : Int,
  row : Int,
  xa : Double,
  xb : Double,
  k : Double,
) -> Unit {
  let a = if xa < 0.0 { 0.0 } else { xa }
  let b = if xb > pw.to_double() { pw.to_double() } else { xb }
  if b <= a {
    return
  }
  let ia = a.floor().to_int()
  let ib = imin(b.ceil().to_int() - 1, pw - 1)
  let base = row * pw
  if ia == ib {
    cover[base + ia] = cover[base + ia] + (b - a) * k
    return
  }
  cover[base + ia] = cover[base + ia] + ((ia + 1).to_double() - a) * k
  for x in (ia + 1)..<ib {
    cover[base + x] = cover[base + x] + k
  }
  cover[base + ib] = cover[base + ib] + (b - ib.to_double()) * k
}

///|
/// How much of each pixel a stroke `hw` wide either side of its line covers
/// (round ends and joins), as the most any of its segments does.
fn stroke_cover(
  cover : FixedArray[Double],
  pw : Int,
  ph : Int,
  pts : Array[Double],
  closed : Bool,
  hw : Double,
) -> Unit {
  let n = pts.length() / 2
  let seg = fn(ax : Double, ay : Double, bx : Double, by : Double) {
    let x0 = imax((dmin(ax, bx) - hw - 1.0).floor().to_int(), 0)
    let x1 = imin((dmax(ax, bx) + hw + 1.0).ceil().to_int(), pw - 1)
    let y0 = imax((dmin(ay, by) - hw - 1.0).floor().to_int(), 0)
    let y1 = imin((dmax(ay, by) + hw + 1.0).ceil().to_int(), ph - 1)
    let s = [ax, ay, bx, by]
    for y in y0..=y1 {
      for x in x0..=x1 {
        let d = seg_dist(x.to_double() + 0.5, y.to_double() + 0.5, s, 0)
        let v = hw - d + 0.5
        if v > 0.0 {
          let v = if v > 1.0 { 1.0 } else { v }
          if v > cover[y * pw + x] {
            cover[y * pw + x] = v
          }
        }
      }
    }
  }
  if n == 1 {
    seg(pts[0], pts[1], pts[0], pts[1])
    return
  }
  for k in 0..<(n - 1) {
    seg(pts[2 * k], pts[2 * k + 1], pts[2 * k + 2], pts[2 * k + 3])
  }
  if closed {
    seg(pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1])
  }
}

///|
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
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
/// `color` with `tint`'s red, green and blue (its alpha times both).
fn tinted(color : Int64, tint : Int64?) -> Int64 {
  match tint {
    None => color
    Some(t) => {
      let a = (color & 0xFFL).to_double() * (t & 0xFFL).to_double() / 255.0
      (t & 0xFFFFFF00L) | a.round().to_int64()
    }
  }
}

///|
/// The picture `pw` × `ph` pixels as straight RGBA, every colour in `tint`'s
/// when it is given.
fn raster(d : Drawable, pw : Int, ph : Int, tint : Int64?) -> FixedArray[Byte] {
  let out = FixedArray::make(pw * ph * 4, 0.0)
  let cover = FixedArray::make(pw * ph, 0.0)
  let kx = pw.to_double() / d.w
  let ky = ph.to_double() / d.h
  for l in d.layers {
    let scale = dmax(kx * l.sx, ky * l.sy)
    let subs = path_subpaths(l.d, scale).map(fn(sub) {
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
      fill_cover(cover, pw, ph, subs.map(fn(s) { s.0 }), l.even_odd)
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

///|
/// `d` drawn `w` wide (its height as its viewport's), under `key`.
fn draw_drawable(
  c : @ui.Ctx,
  key : String,
  d : Drawable,
  w : Double,
  tint : Int64?,
  held? : String,
) -> Int {
  let h = w * d.h / d.w
  let pw = px_of(c, w)
  let ph = imax((pw.to_double() * d.h / d.w).round().to_int(), 1)
  let tk = match tint {
    Some(t) => t.to_string()
    None => "-"
  }
  let k = "mem:sf/pic/\{key}/\{pw}x\{ph}/\{tk}"
  if !made.contains(k) {
    made[k] = true
    @ui.add_image(k, png(pw, ph, raster(d, pw, ph, tint)))
  }
  // a picture of one state after another (`held`: what it is, the stations' glyph breathing): the last one ready
  // shown while the next is decoded, never a frame of nothing between them
  let shown = match held {
    Some(what) => {
      let px = imax(pw, ph).to_double()
      if c.image_ready(k, px) {
        held_shown[what] = k
        k
      } else {
        held_shown.get(what).unwrap_or(k)
      }
    }
    None => k
  }
  c.image(shown, w=Px(w), h=Px(h), fit=FitFill, bg=0L, fade=false)
}

///|
/// The picture `name` drawn `px` pixels wide (as tall as it is for that), in its own colours or all in `tint`: its
/// width, height and pixels (RGBA, straight, rows from the top), to make another picture with; None when there is no
/// such picture.
pub fn drawable_pixels(name : String, px : Int, tint? : Int64) -> (Int, Int, FixedArray[Byte])? {
  match drawables.get(name) {
    Some(d) => {
      let ph = imax((px.to_double() * d.h / d.w).round().to_int(), 1)
      Some((px, ph, raster(d, px, ph, tint)))
    }
    None => None
  }
}

///|
/// Whether the app has the picture `name` (its drawable's name: maker_openai,
/// illus_sign_in…).
pub fn has_drawable(name : String) -> Bool {
  drawables.contains(name)
}

///|
/// The picture `name` drawn `w` wide (as tall as it is for that), in its own
/// colours or all in `tint`.
pub fn drawable(c : @ui.Ctx, name : String, w : Double, tint? : Int64) -> Int {
  match drawables.get(name) {
    Some(d) => draw_drawable(c, name, d, w, tint)
    None => c.box(w=Px(w), h=Px(w), fn() {  })
  }
}

///|
/// Marks drawn in one colour, the page's ink (Parts.kt MONO); the others in
/// their own.
let mono_makers : Array[String] = [
  "anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter",
  "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface",
  "nvidia", "baseten", "dsh",
]

///|
/// The mark of the company that made a model (Parts.kt MakerIcon): the core's
/// `maker` id when there is a mark for it, else its runtime's maker's
/// (codex: OpenAI's, dsh its own, else Anthropic's).
pub fn maker_mark(
  c : @ui.Ctx,
  maker : String,
  runtime : String,
  size : Double,
) -> Int {
  let known = maker != "" &&
    drawables.contains("maker_" + maker.replace_all(old="-", new="_"))
  let id = if known {
    maker
  } else {
    match runtime {
      "codex" => "openai"
      "dsh" => "dsh"
      _ => "anthropic"
    }
  }
  let tint = if mono_makers.contains(id) { Some(theme().p.text) } else { None }
  drawable(c, "maker_" + id.replace_all(old="-", new="_"), size, tint?=tint)
}

///|
/// Slack's mark (a chat that came from Slack).
pub fn slack_mark(c : @ui.Ctx, size : Double) -> Int {
  drawable(c, "slack", size)
}

///|
/// Feishu's mark (a Feishu connect, SlackMark's "feishu").
pub fn feishu_mark(c : @ui.Ctx, size : Double) -> Int {
  drawable(c, "feishu", size)
}

///|
/// The station glyphs' colours a station may give its glyph (glyph:<name>:<colour>), light and dark.
pub fn glyph_color(name : String, dark : Bool) -> Int64? {
  let light = match name {
    "red" => 0xBC4945FFL
    "orange" => 0xB75400FFL
    "amber" => 0xA16700FFL
    "green" => 0x0E8C41FFL
    "teal" => 0x008D90FFL
    "blue" => 0x2D74CAFFL
    "purple" => 0x835CBEFFL
    "pink" => 0xB24981FFL
    _ => return None
  }
  if !dark {
    return Some(light)
  }
  Some(
    match name {
      "red" => 0xFB9890FFL
      "orange" => 0xF5A06FFFL
      "amber" => 0xE0AE57FFL
      "green" => 0x7CCD8EFFL
      "teal" => 0x3BCFCFFFL
      "blue" => 0x82BAFFFFL
      "purple" => 0xC3A5F9FFL
      _ => 0xF197C2FFL
    },
  )
}

///|
/// Whether a station has anything to be shown by (`station_mark` draws
/// nothing for it otherwise).
pub fn has_station_mark(emoji : String, icon : String) -> Bool {
  emoji != "" || icon != ""
}

///|
/// A station where it is named (Parts.kt StationMark): its `icon` first, a
/// glyph (glyph:<name>, glyph:<name>:<colour>, in that colour, else `tint`)
/// or a picture put up (its address, or a data URL); else its emoji.
pub fn station_mark(
  c : @ui.Ctx,
  emoji : String,
  icon : String,
  size : Double,
  tint : Int64,
  none? : String,
) -> Unit {
  if icon.has_prefix("glyph:") {
    let rest = icon.view(start_offset=6).to_owned()
    let (name, colour) = match rest.find(":") {
      Some(i) =>
        (
          rest.view(end_offset=i).to_owned(),
          rest.view(start_offset=i + 1).to_owned(),
        )
      None => (rest, "")
    }
    match station_glyphs.get(name) {
      Some((_, lines, dots)) => {
        let layers : Array[Layer] = []
        for d in lines {
          layers.push({
            d,
            fill: 0L,
            stroke: 0x000000FFL,
            width: 1.75,
            even_odd: false,
            sx: 1.0,
            sy: 1.0,
            tx: 0.0,
            ty: 0.0,
          })
        }
        for d in dots {
          layers.push({
            d,
            fill: 0x000000FFL,
            stroke: 0L,
            width: 0.0,
            even_odd: false,
            sx: 1.0,
            sy: 1.0,
            tx: 0.0,
            ty: 0.0,
          })
        }
        let color = glyph_color(colour, theme().dark).unwrap_or(tint)
        draw_drawable(c, "glyph/" + name, { w: 24.0, h: 24.0, layers }, size, Some(color))
        |> ignore
        return
      }
      None => ()
    }
  }
  // a picture still.fail cloud keeps (cloud/src/icons.ts), by its address
  if icon.has_prefix("https://") || icon.has_prefix("http://") {
    c.image(icon, w=Px(size), h=Px(size), fit=FitCover, radius=size * 0.24, bg=0L)
    |> ignore
    return
  }
  if icon.has_prefix("data:image/") {
    match icon.find("base64,") {
      Some(i) => {
        let key = "mem:sf/station/\{icon.length()}/\{@ui.stable_hash(icon)}"
        if !made.contains(key) {
          made[key] = true
          @ui.add_image(key, base64(icon.view(start_offset=i + 7).to_owned()))
        }
        c.image(key, w=Px(size), h=Px(size), radius=size * 0.24, bg=0L) |> ignore
        return
      }
      None => ()
    }
  }
  if emoji != "" {
    c.text(emoji, size=size * 0.9, wrap=false, line=size) |> ignore
    return
  }
  // none of its own: `none`'s icon, if given (Parts.kt StationMark's `none`)
  match none {
    Some(n) => icon_named(c, n, size, tint) |> ignore
    None => ()
  }
}

///|
/// Base64's bytes (a data URL's).
fn base64(s : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for i in 0..<s.length() {
    let c = unit_at(s, i)
    let v = if c >= 65 && c <= 90 {
      c - 65
    } else if c >= 97 && c <= 122 {
      c - 97 + 26
    } else if c >= 48 && c <= 57 {
      c - 48 + 52
    } else if c == 43 || c == 45 {
      62
    } else if c == 47 || c == 95 {
      63
    } else {
      -1
    }
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.push(((acc >> bits) & 0xFF).to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
/// Icon `name` (`icon`, where a parameter of that name hides it).
fn icon_named(c : @ui.Ctx, name : String, size : Double, color : Int64) -> Int {
  icon(c, name, size~, color~)
}

///|
/// Line art on a `vw` × `vh` grid, its paths stroked `width` wide with round ends and joins, nothing filled (a link's
/// card's mark, ScreenLinks.kt tile): drawn `w` wide (as tall as its grid is for that) in `tint`, kept by `key` for
/// each size and tint.
pub fn line_art(
  c : @ui.Ctx,
  key : String,
  paths : Array[String],
  vw : Double,
  vh : Double,
  width : Double,
  w : Double,
  tint : Int64,
) -> Int {
  let layers : Array[Layer] = []
  for d in paths {
    layers.push({ d, fill: 0L, stroke: 0x000000FFL, width, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 })
  }
  draw_drawable(c, "art/" + key, { w: vw, h: vh, layers }, w, Some(tint))
}

///|
/// A popover's arrow, pointing up at what it is from (StationUpdate.kt: 14 across, 7 up, in the popover's colour; a
/// pixel more under it, into the popover).
// kept across runs: a value (no field of it changes)
let popover_arrow_shape : Drawable = {
  w: 14.0,
  h: 8.0,
  layers: [
    {
      d: "M 0 8 L 7 0 L 14 8 Z",
      fill: 0x000000FFL,
      stroke: 0x00000000L,
      width: 0.0,
      even_odd: false,
      sx: 1.0,
      sy: 1.0,
      tx: 0.0,
      ty: 0.0,
    },
  ],
}

///|
/// The arrow of a popover (14 by 8) in `tint`.
pub fn popover_arrow(c : @ui.Ctx, tint : Int64) -> Int {
  draw_drawable(c, "popover-arrow", popover_arrow_shape, popover_arrow_shape.w, Some(tint))
}
