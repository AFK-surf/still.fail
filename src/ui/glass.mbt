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
/// How a glass box looks. `blur` is CSS blur()'s deviation, in logical px;
/// `tint` is laid over the frost (its alpha how much); `saturation` as CSS
/// saturate(); `solid` is the ground drawn instead where the system asks for
/// less transparency (or MBUI_GLASS=solid).
pub(all) struct Glass {
  blur : Double
  tint : Int64
  saturation : Double
  solid : Int64
  // the rim, frosted: a hairline inside the edge, light along the top and
  // left, less along the foot and right (white's alpha each; Bar.kt rim)
  rim_edge : Double
  rim_lit : Double
  rim_back : Double
  // liquid
  liquid : Bool
  rim : Double
  bezel : Double
  refraction : Double
  chroma : Double
  merge : Double
  adaptive : Bool
  // frosted: frosts what the glass before it frosts (its capture), not what
  // has been drawn since
  shares_capture : Bool
}

///|
/// Frosted glass: what is under it blurred by `blur` (CSS px), `tint` over it.
pub fn Glass::frosted(
  blur~ : Double,
  tint~ : Int64,
  solid~ : Int64,
  saturation? : Double = 1.0,
  rim_edge? : Double = 0.0,
  rim_lit? : Double = 0.0,
  rim_back? : Double = 0.0,
  shares_capture? : Bool = false,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge,
    rim_lit,
    rim_back,
    liquid: false,
    rim: 0.0,
    bezel: 0.0,
    refraction: 0.0,
    chroma: 0.0,
    merge: 0.0,
    adaptive: false,
    shares_capture,
  }
}

///|
/// The same glass frosting what the glass painted before it in this frame frosts (its capture, at that glass's
/// blur), whatever has been drawn since, over that glass too: a ball over a bar, both of the page under them.
pub fn Glass::sharing(self : Glass) -> Glass {
  { ..self, shares_capture: true }
}

///|
/// Liquid glass: nearly clear, what is under it bent along its rim (a bezel
/// `bezel` wide moving it by up to `refraction` px, the colours split by
/// `chroma`), a light rim, text in it inked by what is under it
/// (`adaptive`); shapes of one `glass_group` within `merge` of each other
/// flow into one.
pub fn Glass::liquid(
  blur? : Double = 1.0,
  tint? : Int64 = 0xFFFFFF1AL,
  solid? : Int64 = 0xECECF0FFL,
  saturation? : Double = 1.3,
  rim? : Double = 0.55,
  bezel? : Double = 14.0,
  refraction? : Double = 9.0,
  chroma? : Double = 0.18,
  merge? : Double = 16.0,
  adaptive? : Bool = true,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge: 0.0,
    rim_lit: 0.0,
    rim_back: 0.0,
    liquid: true,
    rim,
    bezel,
    refraction,
    chroma,
    merge,
    adaptive,
    shares_capture: false,
  }
}

///|
/// The glass of a frame being painted: the capture the last glass instance
/// took (its id, the first instance of its run, how many), whether glass
/// is solid this frame, liquid groups being painted, the adaptive glass
/// text is in.
priv struct GlassPaint {
  mut run : Int
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
  let kind = if gl.liquid { 6.0 } else { 5.0 }
  self.push_inst(
    n.x,
    n.y,
    n.fw,
    n.fh,
    n.radius,
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
  let k = self.ninst - 1
  let b = k * inst_size
  let a = self.inst
  a[b + 21] = gl.refraction
  a[b + 22] = gl.chroma
  a[b + 23] = gl.merge
  if gl.shares_capture && !gl.liquid && glass_paint.run != 0 {
    // the last capture's, the run as it was
    a[b + 20] = -glass_paint.run.to_double()
    return
  }
  // one capture with the glass just before it: right after it, as it is,
  // the same blur, not over it, and (liquid) a group of fewer than 8
  let prev = glass_paint.run_start + glass_paint.run_len
  let mut same = glass_paint.run != 0 &&
    prev == k &&
    a[(k - 1) * inst_size + 5] == kind &&
    a[(k - 1) * inst_size + 7] == gl.blur &&
    (!gl.liquid || glass_paint.run_len < 8)
  if same && !gl.liquid {
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
  }
  a[b + 20] = -glass_paint.run.to_double()
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
}
