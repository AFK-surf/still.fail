// Icons, as still.fail draws them (web/ui icons.tsx from design/icons): 24
// grid line art, 1.75 strokes, in one colour. Drawn by the GPU as shapes
// (mbui's Ctx::shapes), at whatever size and colour, nothing made first.

///|
let made : Map[String, Bool] = {}

///|
/// The shapes of each icon, picture and ring drawn, by what it is, its size and its colour: what is drawn is the same
/// shapes again, not worked out each frame.
let shapes_made : Map[String, Array[@ui.Shape]] = {}

///|
/// Every Tester starts as the app does (mbui's on_reset): the images made here gone with its own, nothing waited on or
/// copied, the theme the first frame's.
fn init {
  @ui.on_reset(fn() {
    made.clear()
    shapes_made.clear()
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
  let key = "icon/\{name}/\{size}/\{color}"
  let shapes = match shapes_made.get(key) {
    Some(s) => s
    None => {
      let s = match icon_data.get(name) {
        Some(d) => icon_shapes(d, size / 24.0, color)
        None => []
      }
      shapes_made[key] = s
      s
    }
  }
  c.shapes(shapes, w=Px(size), h=Px(size), name="sf/" + key)
}

///|
/// An icon's parts as icon_data.mbt has them (0 a line, 1 a closed one, 2 a fill's outline: one with a width the
/// first of a fill), `k` points a unit, in `color`: its strokes of a width one shape (their pieces' nearest the one
/// that covers a pixel, as one stroke), each fill one.
fn icon_shapes(data : Array[Double], k : Double, color : Int64) -> Array[@ui.Shape] {
  let strokes : Array[(Double, Array[(Array[Double], Bool)])] = []
  let fills : Array[Array[(Array[Double], Bool)]] = []
  let mut i = 0
  while i + 2 < data.length() {
    let kind = data[i].to_int()
    let w = data[i + 1]
    let n = data[i + 2].to_int()
    let pts = data[i + 3:i + 3 + 2 * n].to_array().map(fn(v) { v * k })
    i = i + 3 + 2 * n
    if kind == 2 {
      if w > 0.0 || fills.length() == 0 {
        fills.push([(pts, true)])
      } else {
        fills[fills.length() - 1].push((pts, true))
      }
    } else {
      match strokes.search_by(fn(s) { s.0 == w }) {
        Some(j) => strokes[j].1.push((pts, kind == 1))
        None => strokes.push((w, [(pts, kind == 1)]))
      }
    }
  }
  let out : Array[@ui.Shape] = []
  for f in fills {
    out.push(@ui.shape_of(f, fill=color))
  }
  for s in strokes {
    out.push(@ui.shape_of(s.1, stroke=color, width=s.0 * k))
  }
  out
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
/// What is at work steps round (Spokes.kt, the web's spokes.ts): eight, the brightest a step further every 100 ms,
/// the others fading behind it. It steps, it does not turn: a frame for each step, none between.
pub let spoke_step_ms : Double = 100.0

///|
/// The spokes' strength from the brightest back (Spokes.kt SPOKE_ALPHA).
// kept across runs: a table, never written
let spoke_alpha : Array[Double] = [1.0, 0.75, 0.55, 0.42, 0.32, 0.25, 0.2, 0.2]

///|
/// Which of the eight leads now: one clock for every mark (the frames'), so the marks on a page step together; with
/// motion reduced, held at the first.
fn spoke_step(c : @ui.Ctx) -> Int {
  if @ui.reduced_motion() {
    0
  } else {
    c.every(spoke_step_ms) % 8
  }
}

///|
/// The eight spokes in a box `size` across (Spokes.kt drawSpokes, the web's 24-unit drawing): each from 4.8 to 9.6
/// out, 2.9 thick with round ends, the first straight up and the rest clockwise, in a box `box` across about its
/// middle (`size` by default).
pub fn spokes(c : @ui.Ctx, size : Double, color : Int64, box? : Double) -> Int {
  let box = box.unwrap_or(size)
  let step = spoke_step(c)
  let u = size / 24.0
  let mid = box / 2.0
  let pi = 3.141592653589793
  let lines = []
  for i in 0..<8 {
    let a = i.to_double() * pi / 4.0
    let dx = @dmath.sin(a) * u
    let dy = -@dmath.cos(a) * u
    lines.push(
      @ui.line(
        [(mid + dx * 4.8, mid + dy * 4.8), (mid + dx * 9.6, mid + dy * 9.6)],
        width=2.9 * u,
        color=alpha(color, spoke_alpha[(step - i + 8) % 8]),
      ),
    )
  }
  c.lines(lines, w=Px(box), h=Px(box))
}

///|
/// The same steps as a ring of eight arcs round an avatar (Spokes.kt drawSegments, the web's `segments`): in a box
/// `size` across, a circle `stroke` thick on its edge, each arc 31° of its 45° with round ends (shortened by their
/// ends' reach, so the gaps stay 14°), the first straight up. Each in `color` at its strength over `ground` (what is
/// under it), mixed: an arc is drawn as pieces whose round ends lie over each other, which see-through ink shows as
/// beads along it.
pub fn segments(c : @ui.Ctx, size : Double, stroke : Double, color : Int64, ground : Int64) -> Int {
  let step = spoke_step(c)
  let r = size / 2.0 - stroke / 2.0
  let mid = size / 2.0
  let pi = 3.141592653589793
  let deg = pi / 180.0
  let cap = stroke / 2.0 / r / deg
  let lines = []
  for i in 0..<8 {
    let from = (i.to_double() * 45.0 - 90.0 - 15.5 + cap) * deg
    lines.push(
      @ui.line(
        @ui.arc(mid, mid, r, from~, sweep=(31.0 - 2.0 * cap) * deg),
        width=stroke,
        color=mix(color, spoke_alpha[(step - i + 8) % 8], ground),
      ),
    )
  }
  c.lines(lines, w=Px(size), h=Px(size))
}

///|
/// A ring that says how far (PreviewLoad.kt's): `size` square, a track of `color` at 18% and `part` of a turn of it
/// from the top, clockwise, 2 wide, still.
pub fn progress_ring(c : @ui.Ctx, size : Double, part : Double, color : Int64) -> Int {
  let share = if part < 0.0 { 0.0 } else if part > 1.0 { 1.0 } else { part }
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
  let track = (color & 0xFFFFFF00L) | ((color & 0xFFL).to_double() * 0.18).round().to_int64()
  let shapes = [@ui.shape_of([(circle(0.0, 2.0 * pi, 48), true)], stroke=track, width=2.0)]
  if share > 0.0 {
    let from = -0.5 * pi
    shapes.push(
      @ui.shape_of([(circle(from, from + share * 2.0 * pi, (48.0 * share).ceil().to_int()), false)], stroke=color, width=2.0),
    )
  }
  c.shapes(shapes, w=Px(size), h=Px(size))
}
