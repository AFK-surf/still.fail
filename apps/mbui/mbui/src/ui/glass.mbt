// Glass: a box whose ground is what was drawn under it, blurred (frosted) or
// bent at its rim (liquid). The scene says where the glass is; the renderers
// copy what is drawn below it when they reach it, blur it, and draw on.
//
// A glass instance (scene.mbt's 28 numbers):
//   0-3 rect · 4 radius · 5 kind (5 frosted, 6 liquid) · 6 saturation
//   7 blur (the Gaussian's deviation, logical px: CSS blur()'s)
//   8-11 tint rgba (over the frost) · 16-19, 24-27 clip (rect, corners)
//   frosted: 12-14 the rim's hairline, its lit top-left, its back (white's
//            alpha, Bar.kt rim) · 15 opacity · 21-23 a notch in its top
//            edge (its box's notch_*: the circle's middle below the top,
//            its radius, its fillets'; scene.mbt)
//   liquid:  12 the rim's light · 13 the bezel's width · 14 unused
//            15 opacity · 21 how far the bezel bends what is under it
//            (px) · 22 the colours' split (0-1) · 23 the smooth-min radius
//            two shapes of one group merge within
//   20 the capture it shares: -1, -2, … (negative, so a run of glass is a run
//      of its own for the renderers' image runs): glass one after another
//      with nothing drawn between, the same blur and kind, not over each
//      other, shares one copy of what is under it; up to 8 liquid shapes of
//      one capture are one merged shape. Frosted glass made `shares_capture`
//      takes the last capture whatever is drawn between and wherever it is
//      (over that glass too, at its blur): it frosts what that glass frosts,
//      not the glass (Bar.kt: the ball and the action frost the pages, not
//      the bar). A renderer copies what is under every instance of a
//      capture when it reaches the first.
// Text in liquid glass that is `adaptive` is drawn as kind 7: a glyph whose
// ink the renderer picks from how light what is under its glass is (21-23:
// the glass's centre and half its size, where to look).

///|
/// The glass of a frame being painted: the capture the last glass instance
/// took (its id, the first instance of its run, how many), whether glass
/// is solid this frame, liquid groups being painted, the adaptive glass
/// text is in.
priv struct GlassPaint {
  mut run : Int
  // the last capture of frosted glass (0 none): what glass `shares_capture` takes
  mut frost_run : Int
  mut run_start : Int
  mut run_len : Int
  mut solid : Bool
  mut checked_at : Int
  mut forced : Int
  mut in_group : Int
  // text in adaptive liquid glass: its centre and half its size (0: none)
  mut ink_x : Double
  mut ink_y : Double
  mut ink_r : Double
}

///|
let glass_paint : GlassPaint = {
  run: 0,
  frost_run: 0,
  run_start: -1,
  run_len: 0,
  solid: false,
  checked_at: -1000,
  forced: -1,
  in_group: 0,
  ink_x: 0.0,
  ink_y: 0.0,
  ink_r: 0.0,
}

///|
fn reset_glass() -> Unit {
  glass_paint.run = 0
  glass_paint.frost_run = 0
  glass_paint.run_start = -1
  glass_paint.run_len = 0
  glass_paint.solid = false
  glass_paint.checked_at = -1000
  glass_paint.forced = -1
  glass_paint.in_group = 0
  glass_paint.ink_r = 0.0
}

///|
/// Glass as glass, or solid from now on (None: as the system says, which is
/// what MBUI_GLASS=solid or the system's reduce transparency make solid).
pub fn set_glass_solid(solid : Bool?) -> Unit {
  glass_paint.forced = match solid {
    None => -1
    Some(true) => 1
    Some(false) => 0
  }
  glass_paint.checked_at = -1000
}

///|
/// Whether glass is drawn solid in this frame.
pub fn Ctx::glass_solid(self : Ctx) -> Bool {
  ignore(self)
  glass_paint.solid
}

///|
/// At the start of painting a frame: a new set of captures; what the system
/// says about transparency, asked now and then (it is a setting, seldom
/// changed).
fn Ctx::glass_frame(self : Ctx) -> Unit {
  glass_paint.run = 0
  glass_paint.frost_run = 0
  glass_paint.run_start = -1
  glass_paint.run_len = 0
  glass_paint.in_group = 0
  glass_paint.ink_r = 0.0
  if glass_paint.forced >= 0 {
    glass_paint.solid = glass_paint.forced == 1
  } else if self.frame_no - glass_paint.checked_at >= 30 ||
    self.frame_no < glass_paint.checked_at {
    glass_paint.checked_at = self.frame_no
    glass_paint.solid = h_reduce_transparency()
  }
}

///|
fn rects_meet(a : Int, b : Int, inst : FixedArray[Double]) -> Bool {
  let pa = a * inst_size
  let pb = b * inst_size
  inst[pa] < inst[pb] + inst[pb + 2] &&
  inst[pb] < inst[pa] + inst[pa + 2] &&
  inst[pa + 1] < inst[pb + 1] + inst[pb + 3] &&
  inst[pb + 1] < inst[pa + 1] + inst[pa + 3]
}

///|
/// The glass instance of node `n` (its frame), at `alpha`.
fn Ctx::emit_glass(self : Ctx, n : Node, gl : Glass, alpha : Double) -> Unit {
  self.glass_inst(n.x, n.y, n.fw, n.fh, n.radius, gl, alpha)
  // (frosted: its corners each its own; liquid merges shapes of one corner each, the renderers' groups: its roundest)
  if !gl.liquid {
    self.corners_last(n)
  }
  self.glass_capture(self.ninst - 1, gl.liquid, gl.shares_capture)
}

///|
/// A glass instance at (x, y), `w` by `h`, corners `radius` round, as `gl` says, at `alpha`: its capture not yet told
/// (Ctx::glass_capture, as it goes into the frame).
fn Ctx::glass_inst(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  gl : Glass,
  alpha : Double,
) -> Unit {
  let kind = if gl.liquid { 6.0 } else { 5.0 }
  self.push_inst(
    x,
    y,
    w,
    h,
    radius,
    kind,
    gl.saturation,
    gl.blur,
    gl.tint,
    1.0,
    if gl.liquid { gl.rim } else { gl.rim_edge },
    if gl.liquid { gl.bezel } else { gl.rim_lit },
    if gl.liquid { 0.0 } else { gl.rim_back },
    alpha,
  )
  let b = (self.ninst - 1) * inst_size
  let a = self.inst
  a[b + 21] = gl.refraction
  a[b + 22] = gl.chroma
  a[b + 23] = gl.merge
}

///|
/// The capture glass instance `k` (just put into the frame, its kind and blur said) takes, as the frame is composed: the
/// last frosted capture's where it `shares` one; else that of the glass just before it, where it may share it; else one
/// of its own. Told of each glass as it goes into the frame, whoever made it (a node of the old view's as it is painted,
/// a node of the window's tree's as its instances are composed: never kept with them).
fn Ctx::glass_capture(self : Ctx, k : Int, liquid : Bool, shares : Bool) -> Unit {
  let b = k * inst_size
  let a = self.inst
  let kind = a[b + 5]
  let blur = a[b + 7]
  if shares && !liquid && glass_paint.frost_run != 0 {
    // the last frosted capture's (liquid glass's is no frost, and only of what is under its shapes), the run as it was
    a[b + 20] = -glass_paint.frost_run.to_double()
    return
  }
  // one capture with the glass just before it: right after it, as it is,
  // the same blur, not over it, and (liquid) a group of fewer than 8
  let prev = glass_paint.run_start + glass_paint.run_len
  let mut same = glass_paint.run != 0 &&
    prev == k &&
    a[(k - 1) * inst_size + 5] == kind &&
    a[(k - 1) * inst_size + 7] == blur &&
    (!liquid || glass_paint.run_len < 8)
  if same && !liquid {
    for j in glass_paint.run_start..<k {
      if rects_meet(j, k, a) {
        same = false
        break
      }
    }
  }
  if same {
    glass_paint.run_len = glass_paint.run_len + 1
  } else {
    glass_paint.run = glass_paint.run + 1
    glass_paint.run_start = k
    glass_paint.run_len = 1
    if !liquid {
      glass_paint.frost_run = glass_paint.run
    }
  }
  a[b + 20] = -glass_paint.run.to_double()
}

///|
/// The glass next drawn starts a capture of its own, whatever was drawn just before it.
fn glass_run_break() -> Unit {
  glass_paint.run_start = -1
  glass_paint.run_len = 0
}

///|
/// The liquid glass in `i`'s subtree, one after another (a glass group: so
/// they are one capture and merge), before anything in it is drawn.
fn Ctx::emit_group_glass(self : Ctx, i : Int, alpha_in : Double) -> Unit {
  let mut c = self.nodes[i].first
  while c >= 0 {
    let n = self.nodes[c]
    let alpha = alpha_in * n.opacity
    if alpha > 0.002 {
      match n.glass {
        Some(gl) if gl.liquid => self.emit_glass(n, gl, alpha)
        _ => ()
      }
      self.emit_group_glass(c, alpha)
    }
    c = n.next
  }
}

///|
/// The box's ground: its glass (or the glass's solid ground), and its own
/// colour over that if it has one. The shadow of glass is drawn after it,
/// outside it only, so the glass does not frost its own shadow.
fn Ctx::paint_glass(self : Ctx, n : Node, gl : Glass, alpha : Double) -> Unit {
  if glass_paint.solid {
    if n.shadow > 0.0 {
      self.paint_shadow(n, alpha, false)
    }
    self.emit_rect(n.x, n.y, n.fw, n.fh, n.radius, gl.solid, 0.0, 0L, alpha)
    self.notch_last(n)
    self.corners_last(n)
    return
  }
  if !gl.liquid || glass_paint.in_group == 0 {
    self.emit_glass(n, gl, alpha)
    if !gl.liquid {
      self.notch_last(n)
    }
  }
  if n.shadow > 0.0 && !gl.liquid {
    self.paint_shadow(n, alpha, true)
  }
}

///|
/// The box's shadow; `outside`: only where the box is not.
fn Ctx::paint_shadow(self : Ctx, n : Node, alpha : Double, outside : Bool) -> Unit {
  let dy = if n.shadow_y >= 0.0 { n.shadow_y } else { n.shadow * 0.35 }
  self.push_inst(
    n.x,
    n.y + dy,
    n.fw,
    n.fh,
    n.radius,
    2.0,
    0.0,
    n.shadow,
    n.shadow_c,
    alpha,
    if outside { 1.0 } else { 0.0 },
    dy,
    0.0,
    0.0,
  )
  self.corners_last(n)
}
