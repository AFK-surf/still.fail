// A remote screen's pointer, as still.fail's Android viewer draws it over the frame (app/remote/ScreenViewer.kt
// Pointer), in the shape the station says its pointer has (a CSS cursor's name: docs/remote-screens.md `cursor`), as
// a Mac draws its own: the arrow white with a dark edge (1.2 wide) as it was; a hand white with a dark edge; the
// others (a text cursor, a cross, the resizing arrows…) dark with a white edge round them. At its own size however the
// frame is zoomed, `pointer_size` square; the point it points with (its hot spot: the arrow's tip, a hand's
// fingertip, the middle of the others) `pointer_hotspot` in from its top left.

///|
/// The arrow's outline (dp from its tip), and the square it is drawn in.
let pointer_outline : Array[Double] = [
  0.0, 0.0, 0.0, 16.0, 4.0, 12.5, 7.0, 18.5, 9.5, 17.5, 6.5, 11.5, 11.5, 11.5,
].map(fn(v) { v + pointer_tip })

///|
/// Where the arrow's tip is in its image, from its top and its left.
pub let pointer_tip : Double = 1.0

///|
pub let pointer_size : Double = 20.0

///|
/// The edge's colour (ScreenViewer.kt Pointer: 0xFF1B1C1F), and the dark of the dark shapes.
let pointer_edge : Int64 = 0x1B1C1FFFL

///|
let pointer_white : Int64 = 0xFFFFFFFFL

///|
/// How wide the white round a dark shape is (dp).
let pointer_halo : Double = 1.0

///|
/// How much of a pixel a layer of a pointer covers: outlines filled (by the nonzero rule: an outline wound the other way
/// is a hole), outlines with a band `hw` wide round them outside too, lines `hw` either side.
priv enum PointerCover {
  Fill(Array[Array[Double]])
  Around(Array[Array[Double]], Double)
  Lines(Array[Array[Double]], Bool, Double)
}

///|
/// The shapes a pointer is drawn in, by the CSS cursor names each stands for.
priv enum PointerShape {
  Arrow
  Text
  VerticalText
  Hand
  ResizeEW
  ResizeNS
  ResizeNWSE
  ResizeNESW
  Move
  Grab
  Grabbing
  Crosshair
  NotAllowed
  Wait
  Progress
}

///|
fn pointer_shape_of(name : String) -> PointerShape {
  match name {
    "text" => Text
    "vertical-text" => VerticalText
    "pointer" => Hand
    "ew-resize" | "col-resize" | "e-resize" | "w-resize" => ResizeEW
    "ns-resize" | "row-resize" | "n-resize" | "s-resize" => ResizeNS
    "nwse-resize" | "nw-resize" | "se-resize" => ResizeNWSE
    "nesw-resize" | "ne-resize" | "sw-resize" => ResizeNESW
    "move" | "all-scroll" => Move
    "grab" => Grab
    "grabbing" => Grabbing
    "crosshair" | "cell" => Crosshair
    "not-allowed" | "no-drop" => NotAllowed
    "wait" => Wait
    "progress" => Progress
    _ => Arrow
  }
}

///|
/// The shape's name in its image's key.
fn pointer_name(shape : PointerShape) -> String {
  match shape {
    Arrow => "arrow"
    Text => "text"
    VerticalText => "vertical-text"
    Hand => "hand"
    ResizeEW => "ew"
    ResizeNS => "ns"
    ResizeNWSE => "nwse"
    ResizeNESW => "nesw"
    Move => "move"
    Grab => "grab"
    Grabbing => "grabbing"
    Crosshair => "crosshair"
    NotAllowed => "not-allowed"
    Wait => "wait"
    Progress => "progress"
  }
}

///|
/// Where the point the pointer of shape `name` points with is in its image, from its left and its top (dp).
pub fn pointer_hotspot(name : String) -> (Double, Double) {
  match pointer_shape_of(name) {
    Arrow | Progress => (pointer_tip, pointer_tip)
    Hand => (8.0, 2.0)
    _ => (10.0, 10.0)
  }
}

///|
/// A rectangle's outline (dp).
fn ptr_rect(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Array[Double] {
  [x0, y0, x1, y0, x1, y1, x0, y1]
}

///|
/// A round's outline (dp), `back`: wound the other way (a hole in what it is filled with).
fn ptr_round(cx : Double, cy : Double, r : Double, back? : Bool = false) -> Array[Double] {
  let n = 32
  let pts = []
  for i in 0..<n {
    let a = (if back { (n - i).to_double() } else { i.to_double() }) * 2.0 * @math.PI / n.to_double()
    pts.push(cx + r * @dmath.cos(a))
    pts.push(cy + r * @dmath.sin(a))
  }
  pts
}

///|
/// A line from (ax, ay) to (bx, by) `r` thick either side, its ends round, as an outline (dp).
fn ptr_capsule(ax : Double, ay : Double, bx : Double, by : Double, r : Double) -> Array[Double] {
  let dx = bx - ax
  let dy = by - ay
  let len = (dx * dx + dy * dy).sqrt()
  let (ux, uy) = (dx / len, dy / len)
  // (across: the line turned a quarter)
  let (nx, ny) = (-uy, ux)
  let n = 10
  let pts = []
  // round its end at b, from one side to the other, then at a back
  for i in 0..=n {
    let a = i.to_double() * @math.PI / n.to_double()
    let (c, s) = (@dmath.cos(a), @dmath.sin(a))
    pts.push(bx + r * (nx * c + ux * s))
    pts.push(by + r * (ny * c + uy * s))
  }
  for i in 0..=n {
    let a = i.to_double() * @math.PI / n.to_double()
    let (c, s) = (@dmath.cos(a), @dmath.sin(a))
    pts.push(ax - r * (nx * c + ux * s))
    pts.push(ay - r * (ny * c + uy * s))
  }
  pts
}

///|
/// An outline wound as a rectangle's (`ptr_rect`) is: clockwise as the image's rows go down.
fn ptr_wound(pts : Array[Double]) -> Array[Double] {
  let n = pts.length() / 2
  let mut area = 0.0
  for i in 0..<n {
    let j = (i + 1) % n
    area = area + pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1]
  }
  if area >= 0.0 {
    pts
  } else {
    let out = []
    for i in 0..<n {
      out.push(pts[(n - 1 - i) * 2])
      out.push(pts[(n - 1 - i) * 2 + 1])
    }
    out
  }
}

///|
/// Outlines turned `quarter` eighths of a turn round the middle of the square (dp).
fn ptr_turned(subs : Array[Array[Double]], eighths : Int) -> Array[Array[Double]] {
  let (c, s) = match eighths % 8 {
    0 => (1.0, 0.0)
    1 => (0.5.sqrt(), 0.5.sqrt())
    2 => (0.0, 1.0)
    3 => (-0.5.sqrt(), 0.5.sqrt())
    4 => (-1.0, 0.0)
    5 => (-0.5.sqrt(), -0.5.sqrt())
    6 => (0.0, -1.0)
    _ => (0.5.sqrt(), -0.5.sqrt())
  }
  subs.map(fn(pts) {
    let out = []
    for i in 0..<(pts.length() / 2) {
      let x = pts[i * 2] - 10.0
      let y = pts[i * 2 + 1] - 10.0
      out.push(10.0 + x * c - y * s)
      out.push(10.0 + x * s + y * c)
    }
    out
  })
}

///|
/// A two headed arrow across the middle, left to right (dp): its shaft and its heads.
fn ptr_both_ways(half : Double) -> Array[Array[Double]] {
  let head = 3.6
  let reach = 3.4
  [
    ptr_rect(10.0 - half + reach - 0.1, 9.25, 10.0 + half - reach + 0.1, 10.75),
    [10.0 - half, 10.0, 10.0 - half + reach, 10.0 - head, 10.0 - half + reach, 10.0 + head],
    [10.0 + half, 10.0, 10.0 + half - reach, 10.0 + head, 10.0 + half - reach, 10.0 - head],
  ]
}

///|
/// An hourglass, its middle at (cx, cy), `k` as large as a whole pointer's (dp).
fn ptr_hourglass(cx : Double, cy : Double, k : Double) -> Array[Array[Double]] {
  let pts = [
    -4.5, -8.0, 4.5, -8.0, 4.5, -6.6, 0.9, 0.0, 4.5, 6.6, 4.5, 8.0, -4.5, 8.0, -4.5,
    6.6, -0.9, 0.0, -4.5, -6.6,
  ]
  [pts.mapi(fn(i, v) { (if i % 2 == 0 { cx } else { cy }) + v * k })]
}

///|
/// A dark shape with the white round it, and dark lines over it (dp).
fn ptr_dark(subs : Array[Array[Double]], lines? : Array[Array[Double]] = []) -> Array[(PointerCover, Int64)] {
  let out = [(Around(subs, pointer_halo), pointer_white), (Fill(subs), pointer_edge)]
  if !lines.is_empty() {
    out.push((Lines(lines, false, 0.55), pointer_edge))
  }
  out
}

///|
/// A white shape with the dark edge round it, and dark lines over it (dp): a hand.
fn ptr_light(subs : Array[Array[Double]], lines : Array[Array[Double]]) -> Array[(PointerCover, Int64)] {
  [
    (Around(subs, 1.1), pointer_edge),
    (Fill(subs), pointer_white),
    (Lines(lines, false, 0.4), pointer_edge),
  ]
}

///|
/// A hand's outlines (dp): its fingers (from the first, each from its knuckle to its tip, how thick), its thumb, and
/// its palm; the lines between its fingers.
fn ptr_hand(
  fingers : Array[(Double, Double, Double, Double, Double)],
  palm : Array[Double],
) -> Array[(PointerCover, Int64)] {
  let subs = fingers.map(fn(f) { ptr_capsule(f.0, f.1, f.2, f.3, f.4) })
  subs.push(palm)
  // all wound the same way, where they overlap filled (the nonzero rule: one wound the other way is a hole)
  let subs = subs.map(ptr_wound)
  // between each finger and the next (the first is the thumb), from the shorter's tip to into the palm
  let lines = []
  for i in 2..<fingers.length() {
    let a = fingers[i - 1]
    let b = fingers[i]
    let x = (a.0 + a.4 + b.0 - b.4) / 2.0
    let top = if a.3 > b.3 { a.3 } else { b.3 }
    lines.push([x, top + 0.5, x, palm[1] + 0.9])
  }
  ptr_light(subs, lines)
}

///|
/// What the pointer of `shape` is drawn of, in order (dp in its `pointer_size` square).
fn pointer_layers(shape : PointerShape) -> Array[(PointerCover, Int64)] {
  match shape {
    // as it always was: the edge over the white, half inside and half outside the outline
    Arrow => [(Fill([pointer_outline]), pointer_white), (Lines([pointer_outline], true, 0.6), pointer_edge)]
    Progress => {
      let out = pointer_layers(Arrow)
      for l in ptr_dark(ptr_hourglass(15.5, 14.5, 0.45)) {
        out.push(l)
      }
      out
    }
    Text =>
      ptr_dark([
        ptr_rect(9.4, 3.0, 10.6, 17.0),
        ptr_rect(7.2, 2.0, 12.8, 3.2),
        ptr_rect(7.2, 16.8, 12.8, 18.0),
      ])
    VerticalText =>
      ptr_dark(
        ptr_turned(
          [
            ptr_rect(9.4, 3.0, 10.6, 17.0),
            ptr_rect(7.2, 2.0, 12.8, 3.2),
            ptr_rect(7.2, 16.8, 12.8, 18.0),
          ],
          2,
        ),
      )
    // the first finger up, the others curled under it, the thumb out to the left
    Hand =>
      ptr_hand(
        [
          (4.2, 10.6, 6.4, 13.6, 1.25),
          (8.0, 10.5, 8.0, 3.2, 1.45),
          (10.85, 11.0, 10.85, 8.6, 1.3),
          (13.4, 11.4, 13.4, 9.4, 1.25),
          (15.75, 12.0, 15.75, 10.4, 1.1),
        ],
        [6.55, 11.0, 16.85, 11.0, 16.85, 14.6, 15.3, 17.0, 15.3, 18.6, 8.3, 18.6, 8.3, 17.4, 5.0, 13.4],
      )
    Grab =>
      ptr_hand(
        [
          (4.6, 10.4, 6.8, 13.6, 1.2),
          (7.3, 11.0, 6.6, 5.4, 1.2),
          (9.8, 10.5, 9.5, 3.4, 1.25),
          (12.4, 10.5, 12.5, 3.8, 1.25),
          (14.6, 11.0, 15.0, 5.8, 1.1),
        ],
        [6.0, 10.4, 16.1, 10.4, 16.1, 14.2, 14.6, 16.8, 14.6, 18.4, 7.6, 18.4, 7.6, 17.2, 4.8, 13.2],
      )
    Grabbing =>
      ptr_hand(
        [
          (4.8, 11.4, 6.8, 13.6, 1.2),
          (7.0, 10.5, 7.0, 8.6, 1.2),
          (9.6, 10.5, 9.6, 7.8, 1.25),
          (12.2, 10.5, 12.2, 7.9, 1.25),
          (14.6, 10.8, 14.6, 8.8, 1.1),
        ],
        [5.8, 10.0, 15.7, 10.0, 15.7, 14.2, 14.4, 16.8, 14.4, 18.4, 7.6, 18.4, 7.6, 17.2, 5.0, 13.4],
      )
    ResizeEW => ptr_dark(ptr_both_ways(8.6))
    ResizeNS => ptr_dark(ptr_turned(ptr_both_ways(8.6), 2))
    ResizeNWSE => ptr_dark(ptr_turned(ptr_both_ways(8.6), 1))
    ResizeNESW => ptr_dark(ptr_turned(ptr_both_ways(8.6), 3))
    Move => {
      let across = ptr_both_ways(8.6)
      let subs = across.copy()
      for s in ptr_turned(across, 2) {
        subs.push(s)
      }
      ptr_dark(subs)
    }
    Crosshair => ptr_dark([ptr_rect(9.45, 1.8, 10.55, 18.2), ptr_rect(1.8, 9.45, 18.2, 10.55)])
    NotAllowed => {
      // a ring, and the bar across it from its top left
      let bar = ptr_turned([ptr_rect(3.6, 9.0, 16.4, 11.0)], 1)
      ptr_dark([ptr_round(10.0, 10.0, 7.6), ptr_round(10.0, 10.0, 5.6, back=true), bar[0]])
    }
    Wait => ptr_dark(ptr_hourglass(10.0, 10.0, 1.0))
  }
}

///|
/// The pointer of `shape` at `px` pixels square (RGBA, straight, rows from the top): each of its layers over those
/// before it.
fn pointer_rgba(shape : PointerShape, px : Int) -> FixedArray[Byte] {
  let k = px.to_double() / pointer_size
  let at = fn(subs : Array[Array[Double]]) { subs.map(fn(pts) { pts.map(fn(v) { v * k }) }) }
  let n = px * px
  // (straight alpha, its colour premultiplied, as it is put together)
  let alpha = FixedArray::make(n, 0.0)
  let rgb = FixedArray::make(n * 3, 0.0)
  for layer in pointer_layers(shape) {
    let cover = FixedArray::make(n, 0.0)
    match layer.0 {
      Fill(subs) => @pixels.fill_cover(cover, px, px, at(subs))
      Around(subs, hw) => {
        @pixels.fill_cover(cover, px, px, at(subs))
        for pts in at(subs) {
          @pixels.stroke_cover(cover, px, px, pts, true, hw * k)
        }
      }
      Lines(subs, closed, hw) =>
        for pts in at(subs) {
          @pixels.stroke_cover(cover, px, px, pts, closed, hw * k)
        }
    }
    let col = layer.1
    let cr = ((col >> 24) & 0xFFL).to_double()
    let cg = ((col >> 16) & 0xFFL).to_double()
    let cb = ((col >> 8) & 0xFFL).to_double()
    for i in 0..<n {
      let a = if cover[i] > 1.0 { 1.0 } else { cover[i] }
      if a > 0.0 {
        rgb[i * 3] = cr * a + rgb[i * 3] * (1.0 - a)
        rgb[i * 3 + 1] = cg * a + rgb[i * 3 + 1] * (1.0 - a)
        rgb[i * 3 + 2] = cb * a + rgb[i * 3 + 2] * (1.0 - a)
        alpha[i] = a + alpha[i] * (1.0 - a)
      }
    }
  }
  let rgba = FixedArray::make(n * 4, b'\x00')
  for i in 0..<n {
    let a = alpha[i]
    if a > 0.0 {
      for j in 0..<3 {
        rgba[i * 4 + j] = (rgb[i * 3 + j] / a + 0.5).to_int().to_byte()
      }
      rgba[i * 4 + 3] = (a * 255.0 + 0.5).to_int().to_byte()
    }
  }
  rgba
}

///|
/// The image (its key for Ctx::image) of the pointer whose shape the station names `shape` (a CSS cursor's name; the
/// arrow for one it has none of its own for), `pointer_size` square, its hot spot `pointer_hotspot(shape)` in from the
/// top left, rasterised at the screen's pixels once.
pub fn pointer_image(c : @ui.Ctx, shape? : String = "default") -> String {
  let (key, png) = pointer_png(c, shape~)
  if !made.contains(key) {
    made[key] = true
    @ui.add_image(key, png())
  }
  key
}

///|
/// The pointer's picture as pointer_image has it, for a host that draws it itself (a remote screen's pointer on its
/// system video layer: @ui.Stream::pointer_image): its key, and its PNG (made as it is asked for, once).
pub fn pointer_png(c : @ui.Ctx, shape? : String = "default") -> (String, () -> Bytes) {
  let px = px_of(c, pointer_size)
  let s = pointer_shape_of(shape)
  let key = "mem:sf/pointer/\{pointer_name(s)}/\{px}"
  (key, fn() {
    match pointer_pngs.get(key) {
      Some(b) => b
      None => {
        let b = @pixels.png(px, px, pointer_rgba(s, px))
        pointer_pngs[key] = b
        b
      }
    }
  })
}

///|
/// The pointers' PNGs made, by their keys (pointer_png).
// kept across runs: each a function of its key alone
let pointer_pngs : Map[String, Bytes] = {}
