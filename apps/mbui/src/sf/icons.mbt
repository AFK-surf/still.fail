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
/// An icon or a picture as drawn: its shapes and the name its node says.
struct DrawnShapes {
  shapes : Array[@ui.Shape]
  name : String
}

///|
/// The icons drawn, by name, size and colour (`icon`): found by those, its name said once, not written out in words
/// (a size and a colour in figures) for each icon on every frame.
let icons_made : Map[(String, Double, Int64), DrawnShapes] = {}

///|
/// The pictures drawn, by key, width, scale and tint (picture.mbt draw_drawable), as icons_made.
let pictures_made : Map[(String, Double, Double, Int64?), DrawnShapes] = {}

///|
/// Every Tester starts as the app does (mbui's on_reset): the images made here gone with its own, nothing waited on or
/// copied, the theme the first frame's.
fn init {
  @ui.on_reset(fn() {
    made.clear()
    shapes_made.clear()
    icons_made.clear()
    pictures_made.clear()
    tiles_made.clear()
    copied_at.clear()
    dark_set.set(None)
    current.val = {
      dark: false,
      touch: false,
      p: light_palette,
      t: wide_type,
      rows: wide_rows,
      control_h: wide_control_h,
      bars: bars_drawn,
      round: wide_round,
      items: wide_items,
      chat_list: mouse_chat_list,
    }
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
/// An icon's shapes as its data has them (icon_data: a 24 grid's strokes), for a host to draw it in its own controls
/// (@hostapi.nav_bar's tabs and items); "" for none of that name.
pub fn icon_path(name : String) -> String {
  icon_data.get(name).unwrap_or("")
}

///|
/// Whether `name` is one of the icons.
pub fn has_icon(name : String) -> Bool {
  icon_data.contains(name)
}

///|
/// Icon `name` (design/icons: "chevron-left", "list", "search"…) `size`
/// square in `color`.
pub fn icon(c : @ui.Ctx, name : String, size? : Double = 16.0, color? : Int64, by_ink? : Bool = false) -> Int {
  let color = color.unwrap_or(theme().p.text)
  let drawn = match icons_made.get((name, size, color)) {
    Some(d) => d
    None => {
      let shapes = match icon_numbers(name) {
        Some(d) => icon_shapes(d, size / 24.0, color)
        None => []
      }
      let d = { shapes, name: "sf/icon/\{name}/\{size}/\{color}" }
      icons_made[(name, size, color)] = d
      d
    }
  }
  // (`by_ink`: laid out by where it draws, its grid's room either side taking none: at a button's end, Ctx::shapes)
  c.shapes(drawn.shapes, w=Px(size), h=Px(size), name=drawn.name, by_ink~)
}

///|
/// How big the play mark is in its disc: its triangle (15 of play-mark's 24) two fifths of the disc across.
let play_mark_share : Double = 0.64

///|
/// A video's play mark over its picture (the web's msgVideoPlay): a disc `side` across of `shade`, the solid triangle
/// in it white, its weight (where the triangle balances, not its box) in the disc's middle: play-mark draws it so.
pub fn play_mark(c : @ui.Ctx, side : Double, shade : @ui.Color) -> Int {
  c.box(style=@ui.style(w=Fixed(side), h=Fixed(side), radius=Full, bg=shade, align=ACenter, justify=JCenter), fn() {
    icon(c, "play-mark", size=side * play_mark_share, color=white) |> ignore
  })
}

///|
/// A video's capsule over its picture, in its foot's start corner concentric with its `corner` (a message's file's: the
/// chat's media tiles' and a message's video's; a quote's picture's): a small play mark and how long it is (`duration`, none where that is
/// not known) on the video's shade. `coming`: how far the core has brought it here, a ring of that share and the share
/// in words in their place, the one going out before the other comes in (words never over words) as the capsule
/// changes its width with them over dur_ms. `key` names
/// its motion. Nothing else over the picture: what it shows is the picture (the user, 2026-11-01: a band with its name
/// and a play mark in its middle left little of a wide one to see).
pub fn video_capsule(
  c : @ui.Ctx,
  key : String,
  duration : Double,
  coming? : Double? = None,
  corner? : Double = message_file_corner,
) -> Unit {
  let part = match coming {
    Some(p) => {
      video_capsule_last[key] = p
      p
    }
    None => video_capsule_last.get(key).unwrap_or(0.0)
  }
  let k = @motion.animate(c, key, if coming is Some(_) { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out))
  let length = if duration > 0.0 { clock(duration) } else { "" }
  let share = "\{(dmin(1.0, dmax(0.0, part)) * 100.0).floor().to_int()}%"
  let gap = @ui.Space::px(S1)
  let end = @ui.Space::px(S1_5)
  let length_w = c.fitting_width(
    if length != "" { c.words_across(length, video_capsule_words) } else { 0.0 },
    if length != "" { [video_capsule_mark, gap, end, end] } else { [video_capsule_mark, end, end] },
  )
  let share_w = c.fitting_width(c.words_across(share, video_capsule_words), [video_capsule_ring, gap, end, end])
  // The wider label needs all of its room until it has faded out, and before it fades in. The capsule can change
  // width during the other half, while the shorter label is showing, without cutting either label on the way.
  let width_way = if length_w >= share_w { dmax(0.0, 2.0 * k - 1.0) } else { dmin(1.0, 2.0 * k) }
  let across = length_w + (share_w - length_w) * @ui.Ease::Move.at(width_way)
  c.layer(fn() {
    let foot = if corner == message_file_corner {
      video_capsule_foot
    } else {
      video_capsule_foot.then(@ui.style(p=room_of(capsule_fit(corner, video_capsule_h, video_capsule_alone_in))))
    }
    c.box(style=foot, fn() {
      c.box(style=video_capsule_box.then(@ui.style(w=Fixed(across))), fn() {
        if k < 0.5 {
          let l = c.box(style=video_capsule_row, fn() {
            icon(c, "play", size=video_capsule_mark, color=white) |> ignore
            if length != "" {
              c.text(length, style=video_capsule_words) |> ignore
            }
          })
          c.look(l, @ui.look(alpha=1.0 - 2.0 * k))
        }
        if k > 0.5 {
          c.layer(fn() {
            c.box(style=video_capsule_over, fn() {
              let r = c.box(style=video_capsule_row, fn() {
                progress_ring(c, video_capsule_ring, part, white) |> ignore
                c.text(share, style=video_capsule_words) |> ignore
              })
              c.look(r, @ui.look(alpha=2.0 * k - 1.0))
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far each video's capsule last said it had come: what it fades out with once it is here.
let video_capsule_last : Map[String, Double] = {}

///|
/// The capsule's height, its play mark's and its ring's.
pub let video_capsule_h : Double = 18.0

///|
let video_capsule_mark : Double = 10.0

///|
let video_capsule_ring : Double = 14.0

///|
/// How far the capsule is from the picture's sides and foot where its corner is too square to lead it (a quote's
/// picture's, quote_picture_corner).
let video_capsule_alone_in : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let video_capsule_foot : @ui.Style = @ui.style(
  w=Full,
  h=Full,
  justify=JEnd,
  align=AStart,
  p=room_of(capsule_in(message_file_corner, video_capsule_h)),
)

///|
// kept across runs: a value (no field of it changes)
let video_capsule_box : @ui.Style = @ui.style(
  row=true,
  h=Fixed(video_capsule_h),
  px=S1_5,
  radius=Full,
  bg=video_shade,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let video_capsule_over : @ui.Style = @ui.css("w=Full h=Full px=S1_5 align=AStart justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let video_capsule_row : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let video_capsule_words : @ui.TextStyle = @ui.text_style(size=Caption, color=white_ink, wrap=false)

///|
/// Of icon `name`, only its parts `parts` (their places among what it is drawn of, from 0: a line, a closed line, a
/// fill with its holes), as `icon` draws it whole: what of it moves drawn apart from what stays (ChatMark.css.ts
/// leadSlot's copies, each showing one part of the icon).
pub fn icon_parts(c : @ui.Ctx, name : String, parts : Array[Int], size? : Double = 16.0, color? : Int64) -> Int {
  let color = color.unwrap_or(theme().p.text)
  let key = "icon/\{name}/\{parts}/\{size}/\{color}"
  let shapes = match shapes_made.get(key) {
    Some(s) => s
    None => {
      let s = match icon_numbers(name) {
        Some(d) => icon_shapes(icon_data_parts(d, parts), size / 24.0, color)
        None => []
      }
      shapes_made[key] = s
      s
    }
  }
  c.shapes(shapes, w=Px(size), h=Px(size), name="sf/" + key)
}

///|
/// Icon `name` with its lines drawn as `trace` gives them (each line's place among them, from 0, and its points in the
/// 24 grid: the lines to draw for it, none for nothing), as `icon` draws it whole: a mark drawn on or drawn back along
/// its strokes (sync_key's tick). Its lines only: built each frame it is asked for, for what moves.
fn icon_traced(
  c : @ui.Ctx,
  name : String,
  trace : (Int, Array[Double]) -> Array[Array[Double]],
  size? : Double = 16.0,
  color? : Int64,
) -> Int {
  let color = color.unwrap_or(theme().p.text)
  let data : Array[Double] = []
  match icon_numbers(name) {
    Some(d) => {
      let mut i = 0
      let mut line = 0
      while i + 2 < d.length() {
        let w = d[i + 1]
        let n = d[i + 2].to_int()
        let end = i + 3 + 2 * n
        if d[i].to_int() != 2 {
          for pts in trace(line, d[i + 3:end].to_array()) {
            if pts.length() >= 4 {
              data.push(0.0)
              data.push(w)
              data.push((pts.length() / 2).to_double())
              for v in pts {
                data.push(v)
              }
            }
          }
          line = line + 1
        }
        i = end
      }
    }
    None => ()
  }
  c.shapes(icon_shapes(data, size / 24.0, color), w=Px(size), h=Px(size), name="sf/icon/\{name}/\{size}/\{color}")
}

///|
/// The first `part` (0 to 1) of the line through `pts` (x y each) by its length: none where that is nothing.
fn stroke_from_start(pts : Array[Double], part : Double) -> Array[Double] {
  let n = pts.length() / 2
  let mut whole = 0.0
  for j in 1..<n {
    whole = whole + segment_length(pts, j)
  }
  let mut left = whole * part
  if left <= 0.0 || n < 2 {
    return []
  }
  let out = [pts[0], pts[1]]
  for j in 1..<n {
    let l = segment_length(pts, j)
    if l >= left {
      let f = if l > 0.0 { left / l } else { 1.0 }
      out.push(pts[2 * j - 2] + (pts[2 * j] - pts[2 * j - 2]) * f)
      out.push(pts[2 * j - 1] + (pts[2 * j + 1] - pts[2 * j - 1]) * f)
      return out
    }
    out.push(pts[2 * j])
    out.push(pts[2 * j + 1])
    left = left - l
  }
  out
}

///|
/// How long the `j`th piece of the line through `pts` is (from point j - 1 to j).
fn segment_length(pts : Array[Double], j : Int) -> Double {
  let dx = pts[2 * j] - pts[2 * j - 2]
  let dy = pts[2 * j + 1] - pts[2 * j - 1]
  (dx * dx + dy * dy).sqrt()
}

///|
/// The entries of an icon's data that are its parts `parts` (a fill's holes, of no width, with the fill they cut).
fn icon_data_parts(data : Array[Double], parts : Array[Int]) -> Array[Double] {
  let out : Array[Double] = []
  let mut i = 0
  let mut part = -1
  while i + 2 < data.length() {
    let kind = data[i].to_int()
    let w = data[i + 1]
    let n = data[i + 2].to_int()
    let end = i + 3 + 2 * n
    if !(kind == 2 && w <= 0.0 && part >= 0) {
      part = part + 1
    }
    if parts.contains(part) {
      for k in i..<end {
        out.push(data[k])
      }
    }
    i = end
  }
  out
}

///|
/// Icon `name`'s numbers, read from icon_data.mbt's text the first time it is asked for (as an array literal each, they
/// were the design system's start-up code: 670 KB of C compiled on every build, 2026-10-24).
fn icon_numbers(name : String) -> Array[Double]? {
  match icon_read.get(name) {
    Some(d) => Some(d)
    None =>
      match icon_data.get(name) {
        Some(text) => {
          let d = read_numbers(text)
          icon_read[name] = d
          Some(d)
        }
        None => None
      }
  }
}

///|
let icon_read : Map[String, Array[Double]] = {}

///|
/// The numbers in `text`, each a space from the next, as icons.py writes them ("-12", "0.562"): its digits read as one
/// whole number then divided by the point's power of ten, one rounding, so the same as the literal would be.
fn read_numbers(text : String) -> Array[Double] {
  let out : Array[Double] = []
  let mut m = 0L
  let mut neg = false
  let mut point = false
  let mut div = 1.0
  let mut digits = false
  for c in text + " " {
    if c == ' ' {
      if digits {
        let v = m.to_double() / div
        out.push(if neg { -v } else { v })
      }
      m = 0L
      neg = false
      point = false
      div = 1.0
      digits = false
    } else if c == '-' {
      neg = true
    } else if c == '.' {
      point = true
    } else {
      m = m * 10L + (c.to_int() - '0'.to_int()).to_int64()
      digits = true
      if point {
        div = div * 10.0
      }
    }
  }
  out
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
/// What is at work steps round (Spokes.kt, the web's spokes.ts): eight, the brightest a step further every 100 ms,
/// the others fading behind it. It steps, it does not turn: a frame for each step, none between, on the clock every
/// resident decoration steps on (@ui.cycle_step_ms).
pub let spoke_step_ms : Double = @ui.cycle_step_ms

///|
/// The eight drawn as at the first step, turned an eighth of a turn each step (the brightest a step further: they are
/// alike but for how strong each is), worked out as each frame is drawn, never built anew for it (Ctx::cycle_look);
/// with motion reduced, held at the first.
fn spoke_turn(c : @ui.Ctx, node : Int) -> Unit {
  c.cycle_look(node, 8.0 * spoke_step_ms, fn(f) { @ui.look(rot=f * 2.0 * 3.141592653589793) }, resident=true, held=true)
}

///|
/// The spokes' strength from the brightest back (Spokes.kt SPOKE_ALPHA).
// kept across runs: a table, never written
let spoke_alpha : Array[Double] = [1.0, 0.75, 0.55, 0.42, 0.32, 0.25, 0.2, 0.2]

///|
/// The eight spokes in a box `size` across (Spokes.kt drawSpokes, the web's 24-unit drawing): each from 4.8 to 9.6
/// out, 2.9 thick with round ends, the first straight up and the rest clockwise, in a box `box` across about its
/// middle (`size` by default).
pub fn spokes(c : @ui.Ctx, size : Double, color : Int64, box? : Double) -> Int {
  let box = box.unwrap_or(size)
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
        color=alpha(color, spoke_alpha[(8 - i) % 8]),
      ),
    )
  }
  let node = c.lines(lines, w=Px(box), h=Px(box))
  spoke_turn(c, node)
  node
}

///|
/// The same steps as a ring of eight arcs round an avatar (Spokes.kt drawSegments, the web's `segments`): in a box
/// `size` across, a circle `stroke` thick on its edge, each arc 31° of its 45° with round ends (shortened by their
/// ends' reach, so the gaps stay 14°), the first straight up. Each in `color` at its strength over `ground` (what is
/// under it), mixed: an arc is drawn as pieces whose round ends lie over each other, which see-through ink shows as
/// beads along it.
pub fn segments(c : @ui.Ctx, size : Double, stroke : Double, color : Int64, ground : Int64) -> Int {
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
        color=mix(color, spoke_alpha[(8 - i) % 8], ground),
      ),
    )
  }
  let node = c.lines(lines, w=Px(size), h=Px(size))
  spoke_turn(c, node)
  node
}

///|
/// A ring that says how far (PreviewLoad.kt's): `size` square, a track of `color` at 18% and `part` of a turn of it
/// from the top, clockwise, on the icon family's 24-unit grid (radius 8.5, stroke 1.75).
pub fn progress_ring(c : @ui.Ctx, size : Double, part : Double, color : Int64) -> Int {
  c.shapes(ring_shapes(size, part, color), w=Px(size), h=Px(size))
}

///|
/// What progress_ring draws, `size` across: its track and as much of its ring as `part` says, in `color` (a node's
/// shapes: tool_ring_node).
pub fn ring_shapes(size : Double, part : Double, color : Int64) -> Array[@ui.Shape] {
  let share = if part < 0.0 { 0.0 } else if part > 1.0 { 1.0 } else { part }
  let r = 8.5 * size / 24.0
  let width = 1.75 * size / 24.0
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
  let shapes = [@ui.shape_of([(circle(0.0, 2.0 * pi, 48), true)], stroke=track, width~)]
  if share > 0.0 {
    let from = -0.5 * pi
    shapes.push(
      @ui.shape_of([(circle(from, from + share * 2.0 * pi, (48.0 * share).ceil().to_int()), false)], stroke=color, width~),
    )
  }
  shapes
}
