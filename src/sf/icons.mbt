// Icons, as still.fail draws them (web/ui icons.tsx from design/icons): 24
// grid line art, 1.75 strokes, in one colour. Each name, size and colour is
// rasterised once at the screen's pixels.

///|
let made : Map[String, Bool] = {}

///|
fn px_of(c : @ui.Ctx, size : Double) -> Int {
  let p = (size * c.scale).ceil().to_int()
  if p < 1 {
    1
  } else {
    p
  }
}

///|
/// Whether `name` is one of the icons.
pub fn has_icon(name : String) -> Bool {
  icon_data.contains(name)
}

///|
/// Icon `name` (design/icons: "chevron-left", "list", "search"…) `size`
/// square in `color`.
pub fn icon(c : @ui.Ctx, name : String, size? : Double = 16.0, color? : Int64) -> Int {
  let color = color.unwrap_or(theme().p.text)
  let px = px_of(c, size)
  let key = "mem:sf/icon/\{name}/\{px}/\{color}"
  if !made.contains(key) {
    made[key] = true
    let art = Art::new(24.0)
    match icon_data.get(name) {
      Some(d) => art.parts(d)
      None => ()
    }
    @ui.add_image(key, tinted_png(art.cover(px), px, color))
  }
  c.image(key, w=Px(size), h=Px(size), fit=FitFill, bg=0L, fade=false)
}

///|
/// The spinner's frames a turn.
let spin_frames = 24

///|
/// The spinner (styles/spinner.css.ts): a ring of line_strong, a quarter of
/// it in the accent, turning in 0.8s; 14, or 12 in a line of small text.
/// `sweep` (of a turn) and `period` for other rings that turn (a chat's mark
/// at work: three quarters, 1.2s).
pub fn spinner(
  c : @ui.Ctx,
  size? : Double = 14.0,
  ring? : Int64,
  arc? : Int64,
  sweep? : Double = 0.25,
  period? : Double = 800.0,
) -> Int {
  let t = theme()
  let ring = ring.unwrap_or(t.p.line_strong)
  let arc = arc.unwrap_or(t.p.accent)
  let frame = if c.stable() {
    0
  } else {
    c.request_frame()
    let turns = c.now() / period
    ((turns - turns.floor()) * spin_frames.to_double()).to_int() % spin_frames
  }
  let px = px_of(c, size)
  let key = "mem:sf/spin/\{px}/\{ring}/\{arc}/\{frame}" +
    (if sweep != 0.25 { "/\{sweep}" } else { "" })
  if !made.contains(key) {
    made[key] = true
    // a border 2 wide inside the box: its middle 1 in from the edge
    let unit = size
    let r = size / 2.0 - 1.0
    let mid = size / 2.0
    let circle = fn(from : Double, to : Double, n : Int) -> Array[Double] {
      let pts = []
      for k in 0..=n {
        let a = from + (to - from) * k.to_double() / n.to_double()
        pts.push(mid + r * @math.cos(a))
        pts.push(mid + r * @math.sin(a))
      }
      pts
    }
    let pi = 3.141592653589793
    let turn = frame.to_double() / spin_frames.to_double() * 2.0 * pi
    let whole = Art::new(unit)
    whole.stroke(circle(0.0, 2.0 * pi, 48), 2.0, true)
    let top = Art::new(unit)
    let from = -0.75 * pi + turn
    top.stroke(
      circle(from, from + sweep * 2.0 * pi, (48.0 * sweep).ceil().to_int()),
      2.0,
      false,
    )
    let a = whole.cover(px)
    let b = top.cover(px)
    // the arc over the ring, as one picture
    let rgba = FixedArray::make(px * px * 4, b'\x00')
    for i in 0..<(px * px) {
      let ca = a[i] * (ring & 0xFFL).to_double() / 255.0
      let cb = b[i] * (arc & 0xFFL).to_double() / 255.0
      let oa = cb + ca * (1.0 - cb)
      if oa > 0.0 {
        for ch in 0..<3 {
          let sh = 24 - ch * 8
          let x = ((ring >> sh) & 0xFFL).to_double()
          let y = ((arc >> sh) & 0xFFL).to_double()
          rgba[i * 4 + ch] = ((y * cb + x * ca * (1.0 - cb)) / oa)
            .round()
            .to_int()
            .to_byte()
        }
        rgba[i * 4 + 3] = (oa * 255.0).round().to_int().to_byte()
      }
    }
    @ui.add_image(key, png(px, px, rgba))
  }
  c.image(key, w=Px(size), h=Px(size), fit=FitFill, bg=0L, fade=false)
}

///|
/// A ring that says how far (PreviewLoad.kt's): `size` square, a track of `color` at 18% and `part` of a turn of it
/// from the top, clockwise, 2 wide, still.
pub fn progress_ring(c : @ui.Ctx, size : Double, part : Double, color : Int64) -> Int {
  let px = px_of(c, size)
  let share = if part < 0.0 { 0.0 } else if part > 1.0 { 1.0 } else { part }
  let k = (share * 100.0).round().to_int()
  let key = "mem:sf/ring/\{px}/\{color}/\{k}"
  if !made.contains(key) {
    made[key] = true
    let r = size / 2.0 - 2.0
    let mid = size / 2.0
    let pi = 3.141592653589793
    let circle = fn(from : Double, to : Double, n : Int) -> Array[Double] {
      let pts = []
      for i in 0..=n {
        let a = from + (to - from) * i.to_double() / n.to_double()
        pts.push(mid + r * @math.cos(a))
        pts.push(mid + r * @math.sin(a))
      }
      pts
    }
    let whole = Art::new(size)
    whole.stroke(circle(0.0, 2.0 * pi, 48), 2.0, true)
    let a = whole.cover(px)
    let b = if k > 0 {
      let arc = Art::new(size)
      let from = -0.5 * pi
      arc.stroke(circle(from, from + k.to_double() / 100.0 * 2.0 * pi, (48.0 * k.to_double() / 100.0).ceil().to_int()), 2.0, false)
      arc.cover(px)
    } else {
      FixedArray::make(px * px, 0.0)
    }
    let rgba = FixedArray::make(px * px * 4, b'\x00')
    let alpha = (color & 0xFFL).to_double() / 255.0
    for i in 0..<(px * px) {
      let cover = b[i] + a[i] * 0.18 * (1.0 - b[i])
      if cover > 0.0 {
        rgba[i * 4] = ((color >> 24) & 0xFFL).to_int().to_byte()
        rgba[i * 4 + 1] = ((color >> 16) & 0xFFL).to_int().to_byte()
        rgba[i * 4 + 2] = ((color >> 8) & 0xFFL).to_int().to_byte()
        rgba[i * 4 + 3] = (cover * alpha * 255.0).round().to_int().to_byte()
      }
    }
    @ui.add_image(key, png(px, px, rgba))
  }
  c.image(key, w=Px(size), h=Px(size), fit=FitFill, bg=0L, fade=false)
}
