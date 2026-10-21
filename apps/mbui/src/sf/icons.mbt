// Icons, as still.fail draws them (web/ui icons.tsx from design/icons): 24
// grid line art, 1.75 strokes, in one colour. Each name, size and colour is
// rasterised once at the screen's pixels.

///|
let made : Map[String, Bool] = {}

///|
/// Every Tester starts as the app does (mbui's on_reset): the images made here gone with its own, nothing waited on or
/// copied, the theme the first frame's. (markdown.mbt's `parsed` stays: what a text parses to is the text's alone.)
fn init {
  @ui.on_reset(fn() {
    made.clear()
    copied_at.clear()
    dark_set.val = None
    current.val = { dark: false, narrow: false, p: wide_light, t: wide_type }
  })
}

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
/// The spinner's line: 2 wide (Waiting.kt Spinner: Stroke(2.dp)).
let spin_stroke : Double = 2.0

///|
/// The spinner (styles/spinner.css.ts, Waiting.kt Spinner): a ring of line_strong, a quarter of it in the accent,
/// turning in 0.8s; 14, or 12 in a line of small text. `sweep` (of a turn) and `period` for other rings that turn (a
/// chat's mark at work: three quarters, 1.2s). Its lines drawn as they are every frame (mbui's Ctx::lines), only where
/// the arc starts going round with the clock: nothing to make, nothing to wait for.
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
  let pi = 3.141592653589793
  // the line's middle 1 in from the edge; the arc from a quarter before the top (the web's: a border whose top is
  // the arc), turned by the clock
  let mid = size / 2.0
  let r = mid - spin_stroke / 2.0
  let from = -0.75 * pi + c.cycle(period) * 2.0 * pi
  c.lines(
    [
      @ui.line(@ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi), width=spin_stroke, color=ring),
      @ui.line(@ui.arc(mid, mid, r, from~, sweep=sweep * 2.0 * pi), width=spin_stroke, color=arc),
    ],
    w=Px(size),
    h=Px(size),
  )
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
        pts.push(mid + r * @dmath.cos(a))
        pts.push(mid + r * @dmath.sin(a))
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
