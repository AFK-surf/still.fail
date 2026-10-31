// Zooming and panning a picture in a stage (an image, a video's frames, a remote screen: still.fail's Android app's
// shared ui/Zoom.kt ZoomState, the web's FilePreview.tsx useZoom): fitted to the stage (a margin round it, enlarged
// or not), zoomed around a point (two fingers' pinch, a double tap, the wheel, a button), panned, and kept within the
// stage: smaller than it, centred; larger, no gap at its edges (or, free, anywhere: a page on a canvas, dragged about
// it). A zoom said with a glide goes there on a Move as long as its way is far; one let go by a finger moving goes on at
// its speed, slowing, to its edges (fling): each a way said once as it sets out, at the moment of what told it (an
// input's, a frame's), where it is at a moment a function of that way and the moment (ZPath). What the fingers do is
// the view's: it says what they came to (transform, pan, fling, zoom_to, double_tap). Each command starts from where
// the picture is at its moment, by what it was told and the way it is on, whatever frames were drawn (Zoom::settle),
// and tells what reads it once, as it leaves it (Zoom::moved). (Zoom::step still copies where it is into its fields for
// what reads them: the old way, read by nothing of its own.)

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
  // a glide: whether one goes on, how far (0 … 1, its way), from, to (scale, x, y)
  mut gliding : Bool
  priv glide : ZPath
  g_from : FixedArray[Double]
  g_to : FixedArray[Double]
  // a fling: whether one goes on, the ways of x and of y (Motion's inertia, stopped at the edges)
  mut flinging : Bool
  priv fling_x : ZPath
  priv fling_y : ZPath
  /// what it was told to show, as each change of it leaves it (Zoom::said: its sizes, where it is or the way it goes):
  /// read where where it shows is read (Zoom::rect), so that what was built by it is built again as that changes, by
  /// whatever way, whoever changed it, as it was built or between frames; told the same, none
  priv place : @signals.Signal[ZoomSaid]
}

///|
/// What a zoom was told to show: the picture's size and the stage's, where it is (scale, x, y) and whether fitted, the
/// glide or the fling it is on (where a glide goes; a fling's own way its motions'). Where it shows at a moment is a
/// function of this and of those motions (Zoom::rect).
priv struct ZoomSaid {
  nw : Double
  nh : Double
  bw : Double
  bh : Double
  scale : Double
  x : Double
  y : Double
  fitted : Bool
  gliding : Bool
  to : (Double, Double, Double)
  flinging : Bool
} derive(Eq)

///|
/// One number's way, said once as it sets out (from where, how fast, to where, by what, from when): where it is at a
/// moment worked out from that alone, whatever frames were drawn; said to move till it ends (the frames come).
priv struct ZPath {
  mut from : Double
  mut v0 : Double
  mut to : Double
  mut spec : @motion.Spec
  mut start : Double
  mut dur : Double
  mut on : Bool
  mover : @ui.Mover
}

///|
fn ZPath::new() -> ZPath {
  { from: 0.0, v0: 0.0, to: 0.0, spec: @motion.Snap(0.0), start: 0.0, dur: 0.0, on: false, mover: @ui.Mover::new() }
}

///|
impl @ui.Moving for ZPath with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  if self.on {
    self.end()
  } else {
    -1.0
  }
}

///|
/// When it is there: its time goes in whole ms (Spec::value_at), so at the first whole ms its length is out.
fn ZPath::end(self : ZPath) -> Double {
  self.start + self.dur.ceil()
}

///|
/// Off from `from` (as fast as `v0`, per second) to `to` by `spec`, from the moment `at` (its cause's).
fn ZPath::go(self : ZPath, from : Double, to : Double, spec : @motion.Spec, v0 : Double, at : Double) -> Unit {
  self.from = from
  self.v0 = v0
  self.to = to
  self.spec = spec
  self.start = at
  self.dur = spec.duration(from, to, v0)
  self.on = true
  // (said to move till it ends: frames come; told between frames, one owed)
  ignore(@ui.current().set_out(self.mover, self as &@ui.Moving, what="a zoom's way"))
}

///|
/// Stopped at `t`, where it is then: there from here on, as what was told of it before says (read anywhere after).
fn ZPath::halt(self : ZPath, t : Double) -> Unit {
  let v = self.at(t)
  self.on = false
  self.from = v
  self.to = v
}

///|
/// Where it is at `t`.
fn ZPath::at(self : ZPath, t : Double) -> Double {
  if !self.on {
    return self.to
  }
  self.spec.value_at(zmax(0.0, t - self.start), self.dur, self.from, self.to, self.v0).0
}

///|
/// Where it is as what is built or drawn now reads it (the frame's moment): built again each frame while it goes.
fn ZPath::shown(self : ZPath) -> Double {
  let c = @ui.current()
  let going = self.on && c.moment() < self.end()
  c.shows_motion(self.mover, going)
  self.at(c.moment())
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
    glide: ZPath::new(),
    g_from: FixedArray::make(3, 0.0),
    g_to: FixedArray::make(3, 0.0),
    flinging: false,
    fling_x: ZPath::new(),
    fling_y: ZPath::new(),
    place: @signals.signal(
      { nw: 0.0, nh: 0.0, bw: 0.0, bh: 0.0, scale: 1.0, x: 0.0, y: 0.0, fitted: true, gliding: false, to: (0.0, 0.0, 0.0), flinging: false },
      same=fn(a, b) { a == b },
    ),
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
  // (as it shows: what reads it followed as Zoom::rect is)
  let scale = match self.rect() {
    Some((_, _, w, _)) if self.nw > 0.0 => w / self.nw
    _ => self.scale
  }
  scale > self.fit() * 1.01
}

///|
/// The moment a command is told at: `at` where who tells it says (an event's own); else, told as the window's tree does
/// something (an event, a step, something due), that one's moment (@ui.tree_cause); else what the frame or the host has
/// as it is told (Ctx::moment: a frame's, as it is built; the host's clock, between frames: the old views' input, read
/// as they are built, the way there). Taken once, as the command begins, and handed on to all it does: where it starts
/// from, where its way sets out.
fn cause(at : Double?) -> Double {
  match at {
    Some(a) => a
    None =>
      match @ui.tree_cause() {
        Some(m) => m
        None => @ui.current().moment()
      }
  }
}

///|
/// The picture's size known (again): fitted, it is fitted to it; else kept within the stage.
pub fn Zoom::natural(self : Zoom, w : Double, h : Double, at? : Double) -> Unit {
  if w == self.nw && h == self.nh {
    return
  }
  // (what it was on settled where it is: the picture fitted again or kept within from there)
  self.settle(cause(at)) |> ignore
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
pub fn Zoom::boxed(self : Zoom, w : Double, h : Double, at? : Double) -> Unit {
  if w == self.bw && h == self.bh {
    return
  }
  self.settle(cause(at)) |> ignore
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
/// What it was told to show, as it is now (place).
fn Zoom::said(self : Zoom) -> ZoomSaid {
  {
    nw: self.nw,
    nh: self.nh,
    bw: self.bw,
    bh: self.bh,
    scale: self.scale,
    x: self.x,
    y: self.y,
    fitted: self.fitted,
    gliding: self.gliding,
    to: (self.g_to[0], self.g_to[1], self.g_to[2]),
    flinging: self.flinging,
  }
}

///|
/// What it was told to show, told (each way it is told anything ends so): what reads where it shows, told where that
/// is otherwise; told the same, nothing.
fn Zoom::moved(self : Zoom) -> Unit {
  self.place.set(self.said())
}

///|
/// Read where what is worked out from what it was told (at a moment of its own: Zoom::rect_at) follows each time it is
/// told otherwise.
pub fn Zoom::told(self : Zoom) -> Unit {
  self.place.get() |> ignore
}

///|
/// The picture's place on the stage (x, y, w, h), once its size is known: as it was told, and where a glide or a fling
/// has it now, read of their motions (what reads it is built again as it is told otherwise and as they go, wherever it
/// is read; not as where Zoom::step was called).
pub fn Zoom::rect(self : Zoom) -> (Double, Double, Double, Double)? {
  let d = self.place.get()
  if d.nw <= 0.0 || d.nh <= 0.0 {
    return None
  }
  let (scale, x, y) = if d.flinging {
    self.kept_within(d.scale, self.fling_x.shown(), self.fling_y.shown())
  } else if d.gliding {
    let e = self.glide.shown()
    (
      self.g_from[0] + (d.to.0 - self.g_from[0]) * e,
      self.g_from[1] + (d.to.1 - self.g_from[1]) * e,
      self.g_from[2] + (d.to.2 - self.g_from[2]) * e,
    )
  } else {
    (d.scale, d.x, d.y)
  }
  let w = d.nw * scale
  let h = d.nh * scale
  Some((d.bw / 2.0 + x - w / 2.0, d.bh / 2.0 + y - h / 2.0, w, h))
}

///|
/// How big it is shown as the frame draws it, as Zoom::rect has it (what it was told, a glide's way read of its motion:
/// what reads it built again as it is told otherwise and as the glide goes), not the field Zoom::step copies it into.
pub fn Zoom::scale_now(self : Zoom) -> Double {
  let d = self.place.get()
  if d.gliding && !d.flinging {
    let e = self.glide.shown()
    self.g_from[0] + (d.to.0 - self.g_from[0]) * e
  } else {
    d.scale
  }
}

///|
/// Where the picture shows at the moment `at` (an event's: what it is decided by, where the finger is on it then), by
/// what it was told and the ways it is on, read of nothing followed; Zoom::rect's at that moment.
pub fn Zoom::rect_at(self : Zoom, at : Double) -> (Double, Double, Double, Double)? {
  if self.nw <= 0.0 || self.nh <= 0.0 {
    return None
  }
  let (scale, x, y) = self.shown_now(at)
  let w = self.nw * scale
  let h = self.nh * scale
  Some((self.bw / 2.0 + x - w / 2.0, self.bh / 2.0 + y - h / 2.0, w, h))
}

///|
/// How big it is shown at the moment `at` (by what it was told and the ways it is on, read of nothing followed).
pub fn Zoom::scale_at(self : Zoom, at : Double) -> Double {
  self.shown_now(at).0
}

///|
/// Whether it is zoomed in at the moment `at` (Zoom::zoomed's, at that moment, nothing followed).
pub fn Zoom::zoomed_at(self : Zoom, at : Double) -> Bool {
  let (scale, _, _) = self.shown_now(at)
  scale > self.fit() * 1.01
}

///|
/// Where (`x`, `y`) at `scale` is, kept within the stage (Zoom::clamp's, read only).
fn Zoom::kept_within(self : Zoom, scale : Double, x : Double, y : Double) -> (Double, Double, Double) {
  if self.free {
    return (scale, x, y)
  }
  let sx = zmax(0.0, (self.nw * scale - self.bw) / 2.0)
  let sy = zmax(0.0, (self.nh * scale - self.bh) / 2.0)
  (scale, zmax(-sx, zmin(sx, x)), zmax(-sy, zmin(sy, y)))
}

///|
/// Where it shows at the moment a command is told (Ctx::moment: an input's, between frames; a frame's, in one), by what
/// it was told and the ways it is on (Zoom::rect's), read of nothing followed: where that command starts from.
fn Zoom::shown_now(self : Zoom, t : Double) -> (Double, Double, Double) {
  if self.flinging {
    self.kept_within(self.scale, self.fling_x.at(t), self.fling_y.at(t))
  } else if self.gliding {
    let e = self.glide.at(t)
    (
      self.g_from[0] + (self.g_to[0] - self.g_from[0]) * e,
      self.g_from[1] + (self.g_to[1] - self.g_from[1]) * e,
      self.g_from[2] + (self.g_to[2] - self.g_from[2]) * e,
    )
  } else {
    (self.scale, self.x, self.y)
  }
}

///|
/// A glide or a fling it is on called off where it has it now (shown_now: what was told and the motions, whether a
/// frame sampled them or not), the place it is at said so; nothing told yet (Zoom::moved, once its command is done).
/// Whether one went on.
fn Zoom::settle(self : Zoom, t : Double) -> Bool {
  if !self.gliding && !self.flinging {
    return false
  }
  let (s, x, y) = self.shown_now(t)
  self.gliding = false
  self.glide.halt(t)
  self.flinging = false
  self.fling_x.halt(t)
  self.fling_y.halt(t)
  self.scale = s
  self.x = x
  self.y = y
  true
}

///|
/// Moved by (dx, dy) and kept within the stage, from where it shows now; told nothing yet.
fn Zoom::pan_by(self : Zoom, dx : Double, dy : Double, t : Double) -> Unit {
  self.settle(t) |> ignore
  let (x0, y0) = (self.x, self.y)
  self.x = self.x + dx
  self.y = self.y + dy
  self.clamp()
  // (moved nowhere, by nothing or against the stage's edges: as it was, fitted still if it was)
  if self.x != x0 || self.y != y0 {
    self.fitted = false
  }
}

///|
/// Moved by a finger (dx, dy), a glide called off where it had it. (Each command below: what it was told before
/// settled at its moment first, then its whole change, then told once, as it is left: Zoom::moved.)
pub fn Zoom::pan(self : Zoom, dx : Double, dy : Double, at? : Double) -> Unit {
  self.pan_by(dx, dy, cause(at))
  self.moved()
}

///|
/// By `zoom` around (ax, ay) on the stage, and moved by (dx, dy): two fingers pinching (Zoom.kt transform), the point
/// under them staying under them.
pub fn Zoom::transform(
  self : Zoom,
  ax : Double,
  ay : Double,
  zoom : Double,
  dx : Double,
  dy : Double,
  at? : Double,
) -> Unit {
  self.settle(cause(at)) |> ignore
  let next = zmax(self.min_scale(), zmin(self.max_scale(), self.scale * zoom))
  let f = next / self.scale
  let px = ax - self.bw / 2.0
  let py = ay - self.bh / 2.0
  let was = (self.scale, self.x, self.y)
  self.scale = next
  self.x = px - (px - self.x) * f + dx
  self.y = py - (py - self.y) * f + dy
  self.clamp()
  // (as it was, at its bounds and edges: fitted still if it was)
  if (self.scale, self.x, self.y) != was {
    self.fitted = false
  }
  self.moved()
}

///|
/// To `target` (at once, or gliding), the picture's point under (ax, ay) on the stage staying put.
pub fn Zoom::zoom_to(self : Zoom, target : Double, ax : Double, ay : Double, glide : Bool, at? : Double) -> Unit {
  let t = cause(at)
  self.settle(t) |> ignore
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
  self.glide_to(next, tx, ty, glide, t)
  self.moved()
}

///|
/// Back to fitted, gliding.
pub fn Zoom::reset(self : Zoom, at? : Double) -> Unit {
  let t = cause(at)
  self.settle(t) |> ignore
  self.glide_to(self.fit(), 0.0, 0.0, true, t)
  self.fitted = true
  self.moved()
}

///|
/// Back to fitted at once.
pub fn Zoom::fit_now(self : Zoom, at? : Double) -> Unit {
  let t = cause(at)
  self.settle(t) |> ignore
  self.glide_to(self.fit(), 0.0, 0.0, false, t)
  self.fitted = true
  self.moved()
}

///|
/// A glide or a fling called off where it is (a finger took it).
pub fn Zoom::stop_glide(self : Zoom, at? : Double) -> Unit {
  self.settle(cause(at)) |> ignore
  self.moved()
}

///|
/// A fling called off where it has got to (a finger came down on it): whether one went on (none: nothing done).
pub fn Zoom::stop_fling(self : Zoom, at? : Double) -> Bool {
  let t = cause(at)
  // (one still going at the press's moment, by its way: whatever a frame drew or sampled meanwhile)
  if !self.flinging || t >= self.fling_end() {
    return false
  }
  // (a fling and a glide are never both on: a fling sets out from where a glide was settled)
  self.settle(t) |> ignore
  self.moved()
  true
}

///|
/// Let go by a finger moving (vx, vy) (stage points per ms): on at that speed, slowing (zoom_fling_ms), to a stop or, kept
/// within the stage, to its edge.
pub fn Zoom::fling(self : Zoom, vx : Double, vy : Double, at? : Double) -> Unit {
  let at = cause(at)
  self.settle(at) |> ignore
  if self.nw <= 0.0 {
    self.moved()
    return
  }
  let sx = zmax(0.0, (self.nw * self.scale - self.bw) / 2.0)
  let sy = zmax(0.0, (self.nh * self.scale - self.bh) / 2.0)
  let go = fn(v : ZPath, from : Double, speed : Double, room : Double) {
    v.on = false
    v.to = from
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
      v.go(from, from, spec, speed * 1000.0, at)
    }
  }
  go(self.fling_x, self.x, vx, sx)
  go(self.fling_y, self.y, vy, sy)
  self.fitted = false
  self.flinging = self.fling_x.on || self.fling_y.on
  self.moved()
}

///|
/// To `s` at (`x`, `y`), at once or gliding from where it is (settled by the command first); told nothing yet.
fn Zoom::glide_to(self : Zoom, s : Double, x : Double, y : Double, glide : Bool, t : Double) -> Unit {
  if !glide {
    self.scale = s
    self.x = x
    self.y = y
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
  // (as long as the furthest of its corners goes; from the moment it is told)
  let far = zmax(zabs(x - self.g_from[1]), zabs(y - self.g_from[2])) +
    zmax(self.nw, self.nh) * zabs(s - self.g_from[0])
  self.glide.go(0.0, 1.0, @motion.move(over=far), 0.0, t)
}

///|
/// Where a glide or a fling has got to this frame (a view showing the picture reads it each frame before drawing it).
pub fn Zoom::step(self : Zoom) -> Unit {
  // (the old way: where it is, as drawn now, copied into its fields for what reads them; nothing of its own reads them
  // for where it shows or where a command starts from, and it changes nothing of what it was told: its ways kept whole,
  // going or not by a command's moment, Zoom::stop_fling)
  let c = @ui.current()
  if self.flinging {
    self.x = self.fling_x.shown()
    self.y = self.fling_y.shown()
    self.clamp()
  }
  if !self.gliding {
    return
  }
  let e = self.glide.shown()
  self.scale = self.g_from[0] + (self.g_to[0] - self.g_from[0]) * e
  self.x = self.g_from[1] + (self.g_to[1] - self.g_from[1]) * e
  self.y = self.g_from[2] + (self.g_to[2] - self.g_from[2]) * e
  ignore(c)
}

///|
/// When the glide it was told to go on has it there (the frames' clock, ms; -1 none going), followed: told again as it
/// is told otherwise (Zoom::told). What shows how big it is (a per cent) reads the clock until then, nothing after.
pub fn Zoom::glide_ends(self : Zoom) -> Double {
  self.told()
  if !self.gliding || !self.glide.on {
    return -1.0
  }
  self.glide.end()
}

///|
/// How big it was shown as it was last told and how big it was told to be (a glide it was told: from where it set out,
/// to where it goes; else where it is, twice), followed: told again as it is told otherwise (Zoom::told). What is laid
/// out by how big it is (a per cent's room) by these, as they are told, never by the way between.
pub fn Zoom::scales_told(self : Zoom) -> (Double, Double) {
  self.told()
  if self.gliding {
    (self.g_from[0], self.g_to[0])
  } else {
    (self.scale, self.scale)
  }
}

///|
/// How big it is shown as what is drawn is drawn at `now` (a node's drawn_at: Zoom::glide_ends' reader), as it was
/// told: a glide's way read at that moment while it goes, where it was told to go after.
pub fn Zoom::scale_shown(self : Zoom, now : Double) -> Double {
  self.told()
  self.scale_at(now)
}

///|
/// When a fling has it where it rests (the frames' clock, ms; -1 none going).
pub fn Zoom::fling_ends(self : Zoom) -> Double {
  if !self.flinging {
    return -1.0
  }
  self.fling_end()
}

///|
/// When its fling's ways end (the later of the two).
fn Zoom::fling_end(self : Zoom) -> Double {
  let end = fn(p : ZPath) { if p.on { p.end() } else { -1.0 } }
  zmax(end(self.fling_x), end(self.fling_y))
}

///|
/// A double tap: fitted, in to 2.5× the fitted size (at least 100%) around it; zoomed, back to fitted.
pub fn Zoom::double_tap(self : Zoom, ax : Double, ay : Double, at? : Double) -> Unit {
  // (zoomed or not as it is at the tap's moment, a glide's way read there)
  let t = cause(at)
  self.settle(t) |> ignore
  if self.scale > self.fit() * 1.01 {
    self.reset(at=t)
  } else {
    self.zoom_to(zmax(self.fit() * 2.5, 1.0), ax, ay, true, at=t)
  }
}

///|
/// Where the picture is on the stage now (x, y, w, h), as Zoom::rect has it, read of nothing followed.
fn Zoom::rect_now(self : Zoom, t : Double) -> (Double, Double, Double, Double)? {
  if self.nw <= 0.0 || self.nh <= 0.0 {
    return None
  }
  let (scale, x, y) = self.shown_now(t)
  let w = self.nw * scale
  let h = self.nh * scale
  Some((self.bw / 2.0 + x - w / 2.0, self.bh / 2.0 + y - h / 2.0, w, h))
}

///|
/// The picture's point `at` brought `margin` within the stage's edges, as little as it takes; told nothing yet.
fn Zoom::keep_in(self : Zoom, at : (Double, Double), margin : Double, t : Double) -> Unit {
  let (x, y, w, h) = match self.rect_now(t) {
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
    self.pan_by(dx, dy, t)
  }
}

///|
/// The picture's point `at` (0 … 1 of its width and height) brought `margin` within the stage's edges, the picture
/// moved as little as it takes (a pointer kept in sight while zoomed in).
pub fn Zoom::keep(self : Zoom, at : (Double, Double), margin : Double, when? : Double) -> Unit {
  self.keep_in(at, margin, cause(when))
  self.moved()
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
  when? : Double,
) -> Unit {
  let t = cause(when)
  let was = match self.rect_now(t) {
    Some(r) => r
    None => {
      self.settle(t) |> ignore
      self.bw = w
      self.bh = h
      self.glide_to(self.fit(), 0.0, 0.0, false, t)
      self.fitted = true
      self.moved()
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
  self.settle(t) |> ignore
  self.bw = w
  self.bh = h
  self.fitted = false
  self.scale = zmax(self.min_scale(), zmin(self.max_scale(), self.scale))
  let nw = self.nw * self.scale
  let nh = self.nh * self.scale
  self.x = px - u.0 * nw + nw / 2.0 - w / 2.0
  self.y = py - u.1 * nh + nh / 2.0 - h / 2.0
  self.clamp()
  self.keep_in(u, margin, t)
  self.moved()
}
