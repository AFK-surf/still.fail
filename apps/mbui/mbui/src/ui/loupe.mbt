// The loupe (iOS's text loupe, Android's Magnifier): what a finger holds hidden under it shown larger over it, in a
// capsule above the finger, a drop of liquid glass growing out of it and following it, while the finger drags what
// needs seeing where it is: a field's caret or the ends of what is picked in it by their handles, a long press's word
// slid on (app.mbt's handle_drag, word_drag), or anything that asks for it this frame (Ctx::loupe). Drawn as the
// frame's painting ends, over everything: the frame's instances under the finger copied, larger about where the finger
// reads (what it moves, over it), into the capsule, cut to it; glass as the ground of its tint; a thin lens of liquid
// glass over it all. Drawn only: nothing in it is pressed.

///|
/// Asked this frame: magnify where the finger is, `reach` over it (what a widget dragged by a finger asks while it is:
/// a slider's thumb, a knob; what it moves hanging that far over the finger), as a field's handles do by themselves.
pub fn Ctx::loupe(self : Ctx, reach? : Double = 0.0) -> Unit {
  self.loupe_asked = true
  self.loupe_reach = reach
}

///|
/// Its size, how much larger what is in it is, how far over the finger a field's caret is as its handle is dragged
/// (the handle hanging under it: editor.mbt's handle_r), how far over the finger it is (its middle), and how far it
/// stays in from the window's sides.
pub let loupe_w : Double = 124.0

///|
pub let loupe_h : Double = 48.0

///|
pub let loupe_zoom : Double = 1.35

///|
pub let loupe_handle_reach : Double = 26.0

///|
pub let loupe_lift : Double = 92.0

///|
let loupe_side : Double = 8.0

///|
/// Where the loupe is this frame, as a drop of liquid it moves as: where it reads, its middle, its width and height.
/// While asked, it grows out of the finger on a spring with give (past its size and back) and follows it on a stiff
/// one, drawn out along the way it goes as fast as the finger goes (as the bar's ball at speed); let go, it goes back
/// into where the finger was. None once it is gone.
fn Ctx::loupe_at(self : Ctx) -> (Double, Double, Double, Double, Double, Double)? {
  let reach = if self.loupe_asked {
    self.loupe_reach
  } else if self.down && pointing() is Finger && self.handle_drag != 0 {
    loupe_handle_reach
  } else if self.down && pointing() is Finger && self.word_drag != 0 {
    // (the finger on the words it widens by)
    0.0
  } else {
    -1.0
  }
  self.loupe_asked = false
  let asked = reach >= 0.0 && self.down
  if asked {
    let half = loupe_w / 2.0
    self.loupe_src = (self.px, self.py - reach)
    self.loupe_to = (
      dclamp(self.px, half + loupe_side, dmax(half + loupe_side, self.width - half - loupe_side)),
      dmax(loupe_h / 2.0 + loupe_side, self.py - loupe_lift),
    )
    self.loupe_foot = (self.px, self.py)
  }
  let grow = self.spring("\u{2}loupe/grow", if asked { 1.0 } else { 0.0 }, from=0.0, stiffness=loupe_grow_k, damping=loupe_grow_c)
  if !asked && grow <= 0.01 {
    return None
  }
  let (tx, ty) = self.loupe_to
  let x = self.spring("\u{2}loupe/x", tx, stiffness=loupe_follow_k, damping=loupe_follow_c)
  let y = self.spring("\u{2}loupe/y", ty, stiffness=loupe_follow_k, damping=loupe_follow_c)
  let (fx, fy) = self.loupe_foot
  let (sx, sy) = self.loupe_src
  // drawn out along its way as far behind as it is, flatter for it; grown out of the finger
  let behind = ((x - tx) * (x - tx) + (y - ty) * (y - ty)).sqrt()
  let stretch = dmin(loupe_stretch_most, behind * loupe_stretch)
  let g = dmax(0.0, grow)
  let w = (loupe_w + stretch) * g
  let h = dmax(0.0, loupe_h - stretch * loupe_flatten) * dmin(g, 1.0 + (g - 1.0) * 0.5)
  Some((sx, sy, fx + (x - fx) * dmin(g, 1.0), fy + (y - fy) * dmin(g, 1.0), w, h))
}

///|
/// The springs it moves on: growing (some give: past its size and back) and following the finger (stiff: with it at
/// once, a hair behind as it goes, a hair past where it stops), and how much it is drawn out by how far behind it is
/// (as fast as the finger goes), at most, and flatter for it.
let loupe_grow_k : Double = 360.0

///|
let loupe_grow_c : Double = 20.0

///|
let loupe_follow_k : Double = 1400.0

///|
let loupe_follow_c : Double = 52.0

///|
let loupe_stretch : Double = 2.4

///|
let loupe_stretch_most : Double = 40.0

///|
let loupe_flatten : Double = 0.25

///|
/// The loupe painted over the frame's instances (see the file's head).
fn Ctx::paint_loupe(self : Ctx) -> Unit {
  let (sx, sy, cx, cy, lw, lh) = match self.loupe_at() {
    Some(at) => at
    None => return
  }
  if lw < 1.0 || lh < 1.0 {
    return
  }
  let z = loupe_zoom
  let x0 = cx - lw / 2.0
  let y0 = cy - lh / 2.0
  let r = lh / 2.0
  // what it shows: the frame round where the finger reads, as far as the capsule holds at its zoom
  let (qx0, qy0) = (sx - lw / 2.0 / z, sy - lh / 2.0 / z)
  let (qx1, qy1) = (sx + lw / 2.0 / z, sy + lh / 2.0 / z)
  let n = self.ninst
  let (cr, cg, cb) = self.clear
  let ground = (((cr * 255.0).round().to_int64() & 0xFFL) << 24) |
    (((cg * 255.0).round().to_int64() & 0xFFL) << 16) |
    (((cb * 255.0).round().to_int64() & 0xFFL) << 8) |
    0xFFL
  // its shadow, outside it, and its ground (the window's, under what it shows)
  self.push_inst(x0, y0 + loupe_shadow_y, lw, lh, r, 2.0, 0.0, loupe_shadow, loupe_shadow_c, 1.0, 1.0,
    loupe_shadow_y, 0.0, 0.0)
  self.emit_rect(x0, y0, lw, lh, r, ground, 0.0, 0L, 1.0)
  // what it shows, copied from under the finger
  let i0 = self.ninst
  for k in 0..<n {
    let b = k * inst_size
    let a = self.inst
    let kind = a[b + 5]
    // (what is inked by glass and what punches through: left out)
    if kind == 7.0 || kind == 9.0 {
      continue
    }
    let (x, y, w, h) = (a[b], a[b + 1], a[b + 2], a[b + 3])
    if x > qx1 || y > qy1 || x + w < qx0 || y + h < qy0 {
      continue
    }
    if a[b + 16] > qx1 || a[b + 17] > qy1 || a[b + 18] < qx0 || a[b + 19] < qy0 {
      continue
    }
    while (self.ninst + 2) * inst_size > self.inst.length() {
      self.grow()
    }
    let a = self.inst
    let d = self.ninst * inst_size
    a.blit_to(a, len=inst_size, src_offset=b, dst_offset=d)
    if kind == 5.0 || kind == 6.0 {
      // glass as its tint, opaque: a ground of its colour (what it frosts is under it, in the loupe at another size)
      // (its tint's colour, as opaque as the glass is drawn: a rect's alpha where glass has its opacity, 15)
      a[d + 5] = 0.0
      a[d + 11] = a[d + 15]
      for j in [6, 7, 12, 13, 14, 15, 20, 21, 22, 23] {
        a[d + j] = 0.0
      }
    }
    self.ninst = self.ninst + 1
  }
  // larger about where the finger reads, in the capsule, cut to it
  let shape = (r, r, r, r)
  let smooth = (0.0, 0.0, 0.0, 0.0)
  push_clip_r(x0, y0, x0 + lw, y0 + lh, shape, smooth)
  self.transform_insts(i0, self.ninst, sx, sy, z, z, cx - sx, cy - sy, (x0, y0, x0 + lw, y0 + lh), shape, smooth)
  pop_clip()
  // over it a lens of liquid glass, as the bar's ball held is: what it shows bent at its rim, the rim lit (a capture of
  // its own: what is under it, the copies)
  // (glass drawn solid: none, what it shows as it is)
  if glass_paint.solid {
    return
  }
  let lens = Node::new()
  lens.x = x0
  lens.y = y0
  lens.fw = lw
  lens.fh = lh
  lens.radius = r
  glass_run_break()
  self.emit_glass(lens, loupe_glass, 1.0)
  glass_run_break()
}

///|
/// The loupe's lens: clear, a touch of white, thin: its rim bending what is under it a little, the colours split less.
// kept across runs: a value (no field of it changes)
let loupe_glass : Glass = Glass::liquid(
  blur=0.0,
  tint=0xFFFFFF0AL,
  solid=0xFFFFFFFFL,
  bezel=7.0,
  refraction=4.0,
  chroma=0.04,
  adaptive=false,
)

///|
/// Its shadow (a floating thing's).
let loupe_shadow : Double = 14.0

///|
let loupe_shadow_y : Double = 4.0

///|
let loupe_shadow_c : Int64 = 0x00000040L

