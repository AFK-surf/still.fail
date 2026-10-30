// Zooming and panning a picture in a stage (an image, a video's frames, a remote screen: still.fail's Android app's
// shared ui/Zoom.kt ZoomState, the web's FilePreview.tsx useZoom): fitted to the stage (a margin round it, enlarged
// or not), zoomed around a point (two fingers' pinch, a double tap, the wheel, a button), panned, and kept within the
// stage: smaller than it, centred; larger, no gap at its edges (or, free, anywhere: a page on a canvas, dragged about
// it). A zoom said with a glide goes there on a Move as long as its way is far, a motion said once as it sets out (Zoom::step reads where it has got to); one let go by a
// finger moving goes on at its speed, slowing, to its edges (fling). What the fingers do is the view's: it says what
// they came to (transform, pan, fling, zoom_to, double_tap).

///|
/// Where a picture shows in its stage: `scale` is stage points per picture pixel, `x` and `y` move its centre from the
/// stage's. `nw` × `nh` is the picture's size (its pixels; 0 until known), `bw` × `bh` the stage's.
pub struct Zoom {
  mut nw : Double
  mut nh : Double
  mut bw : Double
  mut bh : Double
  mut scale : Double
  mut x : Double
  mut y : Double
  mut fitted : Bool
  /// the margin round the fitted picture, for a stage this wide
  margin_of : (Double) -> Double
  /// fitted larger than the picture's own size where the stage has room (else never over 1)
  enlarge : Bool
  /// the least and the most it zooms to, for the fitted scale
  min_of : (Double) -> Double
  max_of : (Double) -> Double
  /// moved anywhere on the stage, not kept within it (its scale still within its bounds)
  free : Bool
  /// the fitted scale a whole number of these (0: as it comes)
  fit_step : Double
  // a glide: whether one goes on, how far (0 … 1, a motion), from, to (scale, x, y)
  mut gliding : Bool
  glide : @motion.Value
  g_from : FixedArray[Double]
  g_to : FixedArray[Double]
  // a fling: whether one goes on, where it has x and where y (each a motion: Motion's inertia, stopped at the edges)
  mut flinging : Bool
  fling_x : @motion.Value
  fling_y : @motion.Value
  /// told each time where it shows is changed (Zoom::moved), read where that is read (Zoom::rect): what was built by
  /// where it was is built again, whoever changed it, as it was built or between frames
  priv place : @signals.Signal[Int]
}

///|
/// How a picture let go slows: as e^(−t / this) (ms), Motion's inertia's own time constant (about the desktop's coasting,
/// 0.997 a ms), setting out as fast as the finger went.
pub let zoom_fling_ms : Double = 325.0

///|
/// A picture's zoom, as Zoom.kt's: fitted within a margin (12, or 32 on a stage 640 wide or more), never enlarged;
/// down to half the fitted size (of 100% at most) and up to 16 times its own; its glides a Move as long as the
/// picture's corners go far (@ui.move_ms). A stage's own (a
/// remote screen, fitted edge to edge, as far as 5 times the fitted size): `margin`, `enlarge`, `min_scale` and
/// `max_scale` (each of the fitted scale) say so. `free`: moved anywhere on the stage (a page on a canvas); `fit_step`:
/// the fitted scale a whole number of these, rounded down.
pub fn Zoom::new(
  margin? : (Double) -> Double = fn(bw) { if bw < 640.0 { 12.0 } else { 32.0 } },
  enlarge? : Bool = false,
  min_scale? : (Double) -> Double = fn(fit) { zmin(fit, 1.0) / 2.0 },
  max_scale? : (Double) -> Double = fn(_) { 16.0 },
  free? : Bool = false,
  fit_step? : Double = 0.0,
) -> Zoom {
  {
    nw: 0.0,
    nh: 0.0,
    bw: 0.0,
    bh: 0.0,
    scale: 1.0,
    x: 0.0,
    y: 0.0,
    fitted: true,
    margin_of: margin,
    enlarge,
    min_of: min_scale,
    max_of: max_scale,
    free,
    fit_step,
    gliding: false,
    glide: @motion.Value::new(1.0),
    g_from: FixedArray::make(3, 0.0),
    g_to: FixedArray::make(3, 0.0),
    flinging: false,
    fling_x: @motion.Value::new(0.0),
    fling_y: @motion.Value::new(0.0),
    place: @signals.signal(0),
  }
}

///|
fn zmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn zabs(a : Double) -> Double {
  if a < 0.0 {
    -a
  } else {
    a
  }
}

///|
fn zmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// The fitted scale: the whole picture within the stage, its margin round it (not enlarged, unless it may be).
pub fn Zoom::fit(self : Zoom) -> Double {
  if self.nw <= 0.0 || self.nh <= 0.0 || self.bw <= 0.0 || self.bh <= 0.0 {
    return 1.0
  }
  let m = (self.margin_of)(self.bw)
  let k = zmin((self.bw - 2.0 * m) / self.nw, (self.bh - 2.0 * m) / self.nh)
  let k = if self.enlarge { k } else { zmin(1.0, k) }
  if self.fit_step > 0.0 {
    (k / self.fit_step).floor() * self.fit_step
  } else {
    k
  }
}

///|
/// The least it zooms to.
pub fn Zoom::min_scale(self : Zoom) -> Double {
  (self.min_of)(self.fit())
}

///|
/// The most it zooms to.
pub fn Zoom::max_scale(self : Zoom) -> Double {
  (self.max_of)(self.fit())
}

///|
/// Larger than fitted.
pub fn Zoom::zoomed(self : Zoom) -> Bool {
  self.scale > self.fit() * 1.01
}

///|
/// The picture's size known (again): fitted, it is fitted to it; else kept within the stage.
pub fn Zoom::natural(self : Zoom, w : Double, h : Double) -> Unit {
  if w == self.nw && h == self.nh {
    return
  }
  self.nw = w
  self.nh = h
  if self.fitted {
    self.scale = self.fit()
    self.x = 0.0
    self.y = 0.0
  } else {
    self.clamp()
  }
  self.moved()
}

///|
/// The stage's size (again): fitted, the picture is fitted to it; else kept within it.
pub fn Zoom::boxed(self : Zoom, w : Double, h : Double) -> Unit {
  if w == self.bw && h == self.bh {
    return
  }
  self.bw = w
  self.bh = h
  if self.fitted {
    self.scale = self.fit()
    self.x = 0.0
    self.y = 0.0
  } else {
    self.clamp()
  }
  self.moved()
}

///|
/// Its scale within its bounds, the picture within the stage: smaller than it, centred; larger, no gap at its edges.
fn Zoom::clamp(self : Zoom) -> Unit {
  if self.nw <= 0.0 {
    return
  }
  self.scale = zmax(self.min_scale(), zmin(self.max_scale(), self.scale))
  if self.free {
    return
  }
  let sx = zmax(0.0, (self.nw * self.scale - self.bw) / 2.0)
  let sy = zmax(0.0, (self.nh * self.scale - self.bh) / 2.0)
  self.x = zmax(-sx, zmin(sx, self.x))
  self.y = zmax(-sy, zmin(sy, self.y))
}

///|
/// Where it shows changed: what read it told.
fn Zoom::moved(self : Zoom) -> Unit {
  self.place.set(@signals.untracked(fn() { self.place.get() }) + 1)
}

///|
/// The picture's place on the stage (x, y, w, h), once its size is known: followed (what reads it is built again as it
/// is moved, Zoom::moved).
pub fn Zoom::rect(self : Zoom) -> (Double, Double, Double, Double)? {
  self.place.get() |> ignore
  if self.nw <= 0.0 || self.nh <= 0.0 {
    return None
  }
  let w = self.nw * self.scale
  let h = self.nh * self.scale
  Some((self.bw / 2.0 + self.x - w / 2.0, self.bh / 2.0 + self.y - h / 2.0, w, h))
}

///|
/// Moved by a finger (dx, dy), a glide called off.
pub fn Zoom::pan(self : Zoom, dx : Double, dy : Double) -> Unit {
  self.stop_glide()
  self.fitted = false
  self.x = self.x + dx
  self.y = self.y + dy
  self.clamp()
  self.moved()
}

///|
/// By `zoom` around (ax, ay) on the stage, and moved by (dx, dy): two fingers pinching (Zoom.kt transform), the point
/// under them staying under them.
pub fn Zoom::transform(self : Zoom, ax : Double, ay : Double, zoom : Double, dx : Double, dy : Double) -> Unit {
  self.stop_glide()
  let next = zmax(self.min_scale(), zmin(self.max_scale(), self.scale * zoom))
  let f = next / self.scale
  let px = ax - self.bw / 2.0
  let py = ay - self.bh / 2.0
  self.fitted = false
  self.scale = next
  self.x = px - (px - self.x) * f + dx
  self.y = py - (py - self.y) * f + dy
  self.clamp()
  self.moved()
}

///|
/// To `target` (at once, or gliding), the picture's point under (ax, ay) on the stage staying put.
pub fn Zoom::zoom_to(self : Zoom, target : Double, ax : Double, ay : Double, glide : Bool) -> Unit {
  let next = zmax(self.min_scale(), zmin(self.max_scale(), target))
  let px = ax - self.bw / 2.0
  let py = ay - self.bh / 2.0
  let f = next / self.scale
  let mut tx = px - (px - self.x) * f
  let mut ty = py - (py - self.y) * f
  if !self.free {
    let sx = zmax(0.0, (self.nw * next - self.bw) / 2.0)
    let sy = zmax(0.0, (self.nh * next - self.bh) / 2.0)
    tx = zmax(-sx, zmin(sx, tx))
    ty = zmax(-sy, zmin(sy, ty))
  }
  self.fitted = false
  self.glide_to(next, tx, ty, glide)
}

///|
/// Back to fitted, gliding.
pub fn Zoom::reset(self : Zoom) -> Unit {
  self.glide_to(self.fit(), 0.0, 0.0, true)
  self.fitted = true
}

///|
/// Back to fitted at once.
pub fn Zoom::fit_now(self : Zoom) -> Unit {
  self.glide_to(self.fit(), 0.0, 0.0, false)
  self.fitted = true
}

///|
/// A glide or a fling called off where it is (a finger took it).
pub fn Zoom::stop_glide(self : Zoom) -> Unit {
  if self.gliding {
    self.gliding = false
    self.glide.set(1.0)
  }
  self.stop_fling() |> ignore
}

///|
/// A fling called off where it has got to (a finger came down on it): whether one went on.
pub fn Zoom::stop_fling(self : Zoom) -> Bool {
  if !self.flinging {
    return false
  }
  self.flinging = false
  self.fling_x.stop()
  self.fling_y.stop()
  self.x = self.fling_x.get()
  self.y = self.fling_y.get()
  self.clamp()
  self.moved()
  true
}

///|
/// Let go by a finger moving (vx, vy) (stage points per ms): on at that speed, slowing (zoom_fling_ms), to a stop or, kept
/// within the stage, to its edge.
pub fn Zoom::fling(self : Zoom, vx : Double, vy : Double) -> Unit {
  self.stop_glide()
  if self.nw <= 0.0 {
    return
  }
  let sx = zmax(0.0, (self.nw * self.scale - self.bw) / 2.0)
  let sy = zmax(0.0, (self.nh * self.scale - self.bh) / 2.0)
  let go = fn(v : @motion.Value, from : Double, speed : Double, room : Double) {
    v.set(from)
    if speed != 0.0 && (self.free || room > 0.0) {
      let (min, max) = if self.free { (None, None) } else { (Some(-room), Some(room)) }
      // at an edge it stops there (Motion's drag with no give past its ends)
      let spec = @motion.inertia_to(
        power=zoom_fling_ms / 1000.0,
        time_constant=zoom_fling_ms,
        bounce_stiffness=1000000.0,
        bounce_damping=10000000.0,
        min?=min,
        max?=max,
      )
      ignore(v.start(from, spec, velocity=speed * 1000.0))
    }
  }
  go(self.fling_x, self.x, vx, sx)
  go(self.fling_y, self.y, vy, sy)
  self.fitted = false
  self.flinging = self.fling_x.is_animating() || self.fling_y.is_animating()
}

///|
fn Zoom::glide_to(self : Zoom, s : Double, x : Double, y : Double, glide : Bool) -> Unit {
  if !glide {
    self.stop_glide()
    self.scale = s
    self.x = x
    self.y = y
    self.moved()
    return
  }
  self.g_from[0] = self.scale
  self.g_from[1] = self.x
  self.g_from[2] = self.y
  self.g_to[0] = s
  self.g_to[1] = x
  self.g_to[2] = y
  // said once as it sets out: the motion asks the frames until it is there
  self.gliding = true
  self.glide.set(0.0)
  // (as long as the furthest of its corners goes)
  let far = zmax(zabs(x - self.g_from[1]), zabs(y - self.g_from[2])) +
    zmax(self.nw, self.nh) * zabs(s - self.g_from[0])
  ignore(self.glide.start(1.0, @motion.move(over=far)))
  self.moved()
}

///|
/// Where a glide or a fling has got to this frame (a view showing the picture reads it each frame before drawing it).
pub fn Zoom::step(self : Zoom) -> Unit {
  if self.flinging {
    self.x = self.fling_x.get()
    self.y = self.fling_y.get()
    self.clamp()
    if !self.fling_x.is_animating() && !self.fling_y.is_animating() {
      self.flinging = false
    }
  }
  if !self.gliding {
    return
  }
  let e = self.glide.get()
  self.scale = self.g_from[0] + (self.g_to[0] - self.g_from[0]) * e
  self.x = self.g_from[1] + (self.g_to[1] - self.g_from[1]) * e
  self.y = self.g_from[2] + (self.g_to[2] - self.g_from[2]) * e
  if !self.glide.is_animating() {
    self.gliding = false
  }
}

///|
/// A double tap: fitted, in to 2.5× the fitted size (at least 100%) around it; zoomed, back to fitted.
pub fn Zoom::double_tap(self : Zoom, ax : Double, ay : Double) -> Unit {
  if self.zoomed() {
    self.reset()
  } else {
    self.zoom_to(zmax(self.fit() * 2.5, 1.0), ax, ay, true)
  }
}

///|
/// The picture's point `at` (0 … 1 of its width and height) brought `margin` within the stage's edges, the picture
/// moved as little as it takes (a pointer kept in sight while zoomed in).
pub fn Zoom::keep(self : Zoom, at : (Double, Double), margin : Double) -> Unit {
  let (x, y, w, h) = match self.rect() {
    Some(r) => r
    None => return
  }
  let px = x + at.0 * w
  let py = y + at.1 * h
  let off = fn(v : Double, room : Double) {
    if room < 2.0 * margin {
      room / 2.0 - v
    } else if v < margin {
      margin - v
    } else if v > room - margin {
      room - margin - v
    } else {
      0.0
    }
  }
  let dx = off(px, self.bw)
  let dy = off(py, self.bh)
  if dx != 0.0 || dy != 0.0 {
    self.pan(dx, dy)
  }
}

///|
/// The stage resized to `w` × `h` (a keyboard up or down): the picture drawn as large as it was (within its bounds), the
/// point `at` of it (0 … 1; None: what was in the stage's middle) where it was on the stage and then kept `margin`
/// within it.
pub fn Zoom::resize_keeping(
  self : Zoom,
  w : Double,
  h : Double,
  at : (Double, Double)?,
  margin : Double,
) -> Unit {
  let was = match self.rect() {
    Some(r) => r
    None => {
      self.bw = w
      self.bh = h
      self.fit_now()
      return
    }
  }
  let (wx, wy, ww, wh) = was
  let u = match at {
    Some(a) => a
    None => ((self.bw / 2.0 - wx) / ww, (self.bh / 2.0 - wy) / wh)
  }
  // where that point was on the stage, its new place's centre offset making it stay there
  let px = wx + u.0 * ww
  let py = wy + u.1 * wh
  self.stop_glide()
  self.bw = w
  self.bh = h
  self.fitted = false
  self.scale = zmax(self.min_scale(), zmin(self.max_scale(), self.scale))
  let nw = self.nw * self.scale
  let nh = self.nh * self.scale
  self.x = px - u.0 * nw + nw / 2.0 - w / 2.0
  self.y = py - u.1 * nh + nh / 2.0 - h / 2.0
  self.clamp()
  self.keep(u, margin)
}
