// The stations at a glance (still.fail's Android app, shared/ui/StationGlyph.kt, as the web's StationGlyph.tsx): a
// circle cut into one equal arc per station with the bottom slot left open, still.fail's robot in the middle. Online
// arcs are ink and the rest a faint track; past six stations the arcs join into one bar filled to the share online. A
// station whose link is on its way follows the online ones, its arc breathing. A station failing drops out of the ring
// into the open slot as a red dot (two at most). The robot blinks one eye while one station works and both while more
// do; with the device itself offline it sleeps and the whole fades. Drawn as a picture (picture.mbt), one each state.

///|
/// What the glyph draws (the core's `glyph` of the chats' list): stations online, those not (`connecting` of them on
/// their way), failing, working; asleep while the core reaches nothing at all.
pub(all) struct GlyphCounts {
  online : Int
  dim : Int
  failing : Int
  working : Int
  asleep : Bool
  connecting : Int
} derive(Eq)

// All in the web's 24-unit box.

///|
let glyph_r : Double = 9.7

///|
let glyph_track : Double = 0.18

///|
/// An arc of the ring, from and to in degrees clockwise from 12 o'clock: lit (ink), the track, or on its way.
priv struct GlyphArc {
  from : Double
  to : Double
  lit : Bool
  pulse : Bool
}

///|
/// Where every part goes (StationGlyph.kt glyphLayout): the arcs, and the red dots' angles.
fn glyph_layout(g : GlyphCounts) -> (Array[GlyphArc], Array[Double]) {
  let pi = 3.141592653589793
  let gap_deg = (1.7 + 1.8) / glyph_r * 180.0 / pi
  let ring = g.online + g.dim
  let connecting = if g.connecting < 0 {
    0
  } else if g.connecting > g.dim {
    g.dim
  } else {
    g.connecting
  }
  let arcs : Array[GlyphArc] = []
  if ring > 6 {
    let slot = 360.0 / 7.0
    let from = 180.0 + slot / 2.0 + gap_deg / 2.0
    let to = 540.0 - slot / 2.0 - gap_deg / 2.0
    arcs.push({ from, to, lit: false, pulse: false })
    let lit = from + (to - from) * g.online.to_double() / ring.to_double()
    if connecting > 0 {
      arcs.push({
        from: lit,
        to: from + (to - from) * (g.online + connecting).to_double() / ring.to_double(),
        lit: false,
        pulse: true,
      })
    }
    if g.online > 0 {
      arcs.push({ from, to: lit, lit: true, pulse: false })
    }
  } else if ring > 0 {
    let slot = 360.0 / (ring + 1).to_double()
    for i in 0..<ring {
      let mid = 180.0 + slot * (i + 1).to_double()
      arcs.push({
        from: mid - slot / 2.0 + gap_deg / 2.0,
        to: mid + slot / 2.0 - gap_deg / 2.0,
        lit: i < g.online,
        pulse: i >= g.online && i < g.online + connecting,
      })
    }
  }
  let k = if g.failing > 2 { 2 } else if g.failing < 0 { 0 } else { g.failing }
  let step = 3.1 / glyph_r * 180.0 / pi
  let dots = Array::makei(k, fn(i) { 180.0 + (i.to_double() - (k - 1).to_double() / 2.0) * step })
  (arcs, dots)
}

///|
/// A point of the ring's circle (or one `r` round the middle) at `deg` clockwise from 12 o'clock.
fn ring_at(deg : Double, r : Double) -> (Double, Double) {
  let a = deg * 3.141592653589793 / 180.0
  (12.0 + r * @math.sin(a), 12.0 - r * @math.cos(a))
}

///|
fn num(x : Double) -> String {
  ((x * 1000.0).round() / 1000.0).to_string()
}

///|
/// An arc of the ring as a path (split in two where it is long: an SVG arc of more than 180° is one of two).
fn arc_path(from : Double, to : Double) -> String {
  let b = StringBuilder()
  let (x0, y0) = ring_at(from, glyph_r)
  b.write_string("M\{num(x0)} \{num(y0)}")
  let mut at = from
  while at < to - 0.001 {
    let next = if to - at > 170.0 { at + 170.0 } else { to }
    let (x, y) = ring_at(next, glyph_r)
    b.write_string(" A\{num(glyph_r)} \{num(glyph_r)} 0 0 1 \{num(x)} \{num(y)}")
    at = next
  }
  b.to_string()
}

///|
/// An ellipse round (cx, cy) as a path.
fn ellipse_path(cx : Double, cy : Double, rx : Double, ry : Double) -> String {
  "M\{num(cx - rx)} \{num(cy)} A\{num(rx)} \{num(ry)} 0 1 0 \{num(cx + rx)} \{num(cy)} A\{num(rx)} \{num(ry)} 0 1 0 \{num(cx - rx)} \{num(cy)} Z"
}

///|
/// A rounded rectangle as a path.
fn round_rect_path(x : Double, y : Double, w : Double, h : Double, r : Double) -> String {
  "M\{num(x + r)} \{num(y)} H\{num(x + w - r)} A\{num(r)} \{num(r)} 0 0 1 \{num(x + w)} \{num(y + r)} V\{num(y + h - r)} A\{num(r)} \{num(r)} 0 0 1 \{num(x + w - r)} \{num(y + h)} H\{num(x + r)} A\{num(r)} \{num(r)} 0 0 1 \{num(x)} \{num(y + h - r)} V\{num(y + r)} A\{num(r)} \{num(r)} 0 0 1 \{num(x + r)} \{num(y)} Z"
}

///|
/// `color` with its alpha times `k`.
fn faded(color : Int64, k : Double) -> Int64 {
  let a = ((color & 0xFFL).to_double() * k).round().to_int64()
  (color & 0xFFFFFF00L) | (if a > 255L { 255L } else { a })
}

///|
fn glyph_layer(d : String, fill : Int64, stroke : Int64, width : Double, even_odd? : Bool = false) -> @pixels.VectorPath {
  { d, fill, stroke, width, even_odd, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 }
}

///|
/// The robot's blink: once in 2.6 s (the web's), a declared endless decoration (Ctx::cycle, resident).
let glyph_blink_period : Double = 2600.0

///|
/// The steps of the resident clock in the blink's loop its eyes change at: shutting from 2288 ms, open again at its end.
// kept across runs: a table, never written
let glyph_blink_steps : Array[Double] = [2300.0, 2400.0, 2500.0]

///|
/// A link on its way: its arc's breath, 1.4 s, a declared endless decoration (resident).
let glyph_breath_period : Double = 1400.0

///|
/// The stations' glyph `size` square in `tint` (failing ones' dots in `red`). It blinks while a station works and an
/// arc breathes while a link is on its way (endless decorations, Ctx::cycle: resident, up as long as Home is, so on the
/// one clock's steps); still with motion reduced.
pub fn station_glyph(c : @ui.Ctx, g : GlyphCounts, size : Double, tint : Int64, red : Int64) -> Int {
  let (arcs, dots) = glyph_layout(g)
  let still = @ui.reduced_motion()
  let blinking = if g.asleep { 0 } else { g.working }
  // a blink: open most of the time, shut for a moment (2.6 s, shut at 93%: down over 130 ms, up over 182)
  let mut eye = 1.0
  if blinking > 0 && !still {
    // (on the resident clock's steps, a frame only at those of the blink: open, it is the same at every other)
    let t = (c.loop_at(glyph_blink_period, glyph_blink_steps) / @ui.cycle_step_ms).floor() * @ui.cycle_step_ms
    if t >= 2288.0 {
      eye = if t < 2418.0 {
        1.0 - 0.9 * (t - 2288.0) / 130.0
      } else {
        0.1 + 0.9 * (t - 2418.0) / 182.0
      }
      eye = (eye * 10.0).round() / 10.0
    }
  }
  // a link on its way: its arc breathes between the track and ink (1.4 s), held halfway with motion reduced; breathing,
  // drawn apart over the rest in ink, its opacity a look by the clock (Ctx::cycle_look): what holds the glyph is not
  // built again for each step of it (built each step, the stations' tab on the phone's bar built the whole frame ten
  // times a second, and each frame after it again, for as long as a station could not be reached)
  let breathing = arcs.iter().any(fn(a) { a.pulse }) && !still
  let whole = if g.asleep { 0.4 } else { 1.0 }
  let layers : Array[@pixels.VectorPath] = []
  let breaths : Array[@pixels.VectorPath] = []
  for a in arcs {
    if a.pulse && breathing {
      breaths.push(glyph_layer(arc_path(a.from, a.to), 0L, faded(tint, whole), 1.8))
      continue
    }
    let k = if a.lit { 1.0 } else if a.pulse { 0.5 } else { glyph_track }
    layers.push(glyph_layer(arc_path(a.from, a.to), 0L, faded(tint, k * whole), 1.8))
  }
  for d in dots {
    let (x, y) = ring_at(d, glyph_r)
    layers.push(glyph_layer(ellipse_path(x, y, 1.25, 1.25), faded(red, whole), 0L, 0.0))
  }
  // the robot: its face with its eyes (or, asleep, its shut eyes) cut out of it
  let body = StringBuilder()
  body.write_string(round_rect_path(7.1, 7.9, 9.8, 8.2, 3.0))
  if g.asleep {
    for x in [(9.2, 10.8), (13.2, 14.8)] {
      body.write_string(" " + round_rect_path(x.0 - 0.6, 11.5, x.1 - x.0 + 1.2, 1.2, 0.6))
    }
  } else {
    for i, x in [10.3, 13.7] {
      let ry = 1.25 * (if blinking >= (if i == 1 { 1 } else { 2 }) { eye } else { 1.0 })
      body.write_string(" " + ellipse_path(x, 12.0, 1.1, ry))
    }
  }
  layers.push(glyph_layer(body.to_string(), faded(tint, whole), 0L, 0.0, even_odd=true))
  let key = "glyph-state/\{g.online}/\{g.dim}/\{g.failing}/\{g.connecting}/\{g.asleep}/\{blinking > 0}/\{eye}/\{breathing}/\{red}/\{tint}"
  if !breathing {
    return draw_drawable(c, key, { w: 24.0, h: 24.0, layers }, size, None)
  }
  // (as big as the glyph: the breath laid over it whole)
  c.box(fn() {
    draw_drawable(c, key, { w: 24.0, h: 24.0, layers }, size, None) |> ignore
    let breath = c.layer(fn() {
      draw_drawable(c, "glyph-breath/" + key, { w: 24.0, h: 24.0, layers: breaths }, size, None) |> ignore
    })
    c.cycle_look(
      breath,
      glyph_breath_period,
      fn(f) {
        let p = f * 2.0
        let p = if p < 1.0 { p } else { 2.0 - p }
        @ui.look(alpha=((glyph_track + (0.85 - glyph_track) * standard_at(p)) * 20.0).round() / 20.0)
      },
      resident=true,
    )
  })
}

///|
/// Compose's FastOutSlowIn (.4, 0, .2, 1) at `t` (0–1 of the time).
fn standard_at(t : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  if t >= 1.0 {
    return 1.0
  }
  let bez = fn(a : Double, b : Double, s : Double) { 3.0 * a * s * (1.0 - s) * (1.0 - s) + 3.0 * b * s * s * (1.0 - s) + s * s * s }
  // the curve's s for x = t, by halving
  let mut lo = 0.0
  let mut hi = 1.0
  for _ in 0..<30 {
    let mid = (lo + hi) / 2.0
    if bez(0.4, 0.2, mid) < t {
      lo = mid
    } else {
      hi = mid
    }
  }
  bez(0.0, 1.0, (lo + hi) / 2.0)
}

///|
/// A rounded frame `w` by `h` (its corner `r`) drawn as dashes `line` wide in `color` (CSS's `dashed`: a dash three of
/// its widths, a gap two, spread to come round evenly), its line's middle on the frame; what stands by it is under.
pub fn dashed_frame(c : @ui.Ctx, w : Double, h : Double, r : Double, line : Double, color : Int64) -> Int {
  let path = StringBuilder()
  for o in @ui.dashed_outlines(w, h, r, line) {
    let pts = o.0
    for i in 0..<(pts.length() / 2) {
      path.write_string(if i == 0 { " M" } else { " L" })
      path.write_string("\{num(pts[2 * i] + line / 2.0)} \{num(pts[2 * i + 1] + line / 2.0)}")
    }
  }
  let d : @pixels.Vector = {
    w: w + line,
    h: h + line,
    layers: [glyph_layer(path.to_string(), 0L, color, line)],
  }
  draw_drawable(c, "dashed/\{w}/\{h}/\{r}/\{line}/\{color}", d, w + line, None)
}

///|
/// The glyph at rest as an icon for the system's bars (@hostapi.NavItem `icon`: icon_data's groups, a 24 grid, in the
/// one ink the system tints it with): the ring's arcs, the track's fainter (a group `4 a 0` the alpha of those after),
/// the failing stations' dots, the robot with its eyes cut out of it (`5`: what it covers cleared). No blink, no
/// breath: the system's tab bar draws it once.
pub fn station_glyph_icon(g : GlyphCounts) -> String {
  // (the same counts the same icon: the bars are handed it every frame, it is worked out as they change)
  match glyph_icon_last.val {
    Some((was, icon)) if was == g => return icon
    _ => ()
  }
  let icon = glyph_icon_of(g)
  glyph_icon_last.val = Some((g, icon))
  icon
}

///|
/// The last counts station_glyph_icon was asked for and its icon.
// kept across runs: what a pure function of the counts gave for them, the same in any run
let glyph_icon_last : Ref[(GlyphCounts, String)?] = Ref(None)

///|
/// station_glyph_icon's icon, worked out.
fn glyph_icon_of(g : GlyphCounts) -> String {
  let (arcs, dots) = glyph_layout(g)
  let whole = if g.asleep { 0.4 } else { 1.0 }
  let out = StringBuilder()
  let group = fn(kind : Int, width : Double, pts : Array[Double]) {
    out.write_string("\{kind} \{num(width)} \{pts.length() / 2}")
    for v in pts {
      out.write_string(" " + num(v))
    }
    out.write_string(" ")
  }
  let alpha = fn(a : Double) { out.write_string("4 \{num(a)} 0 ") }
  let shape = fn(d : String, kind : Int, width : Double) {
    for sub in glyph_layer(d, 0L, 0L, 0.0).outlines(1.0, 4.0) {
      group(kind, width, sub.0)
    }
  }
  for a in arcs {
    alpha(whole * (if a.lit { 1.0 } else { glyph_icon_track }))
    shape(arc_path(a.from, a.to), 0, 1.8)
  }
  alpha(whole)
  for d in dots {
    let (x, y) = ring_at(d, glyph_r)
    shape(ellipse_path(x, y, 1.25, 1.25), 2, 0.0)
  }
  shape(round_rect_path(7.1, 7.9, 9.8, 8.2, 3.0), 2, 0.0)
  if g.asleep {
    for x in [(9.2, 10.8), (13.2, 14.8)] {
      shape(round_rect_path(x.0 - 0.6, 11.5, x.1 - x.0 + 1.2, 1.2, 0.6), 5, 0.0)
    }
  } else {
    for x in [10.3, 13.7] {
      shape(ellipse_path(x, 12.0, 1.1, 1.25), 5, 0.0)
    }
  }
  out.to_string().trim_end(chars=" ").to_string()
}

///|
/// The ring's track in the system's bars: fainter than the ink, as it is drawn, but seen on its glass.
let glyph_icon_track : Double = 0.3
