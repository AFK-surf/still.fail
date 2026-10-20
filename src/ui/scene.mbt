// Painting: the laid-out tree becomes a flat list of instances (28 floats
// each) that every renderer draws with one shader:
//   0-3 rect x y w h · 4 radius · 5 kind · 6 border width · 7 blur
//   8-11 color rgba · 12-15 border color, or the glyph's atlas rect
//   16-19 clip x0 y0 x1 y1 · 20 image id · 21-23 a notch in its top edge
//   (kinds 0 and 5: its circle's middle below the top, its radius, its
//   fillets'; 0 none: Ctx::box notch_r) · 24-27 the clip's corners' radii
//   (top left, top right, bottom right, bottom left: 16-19 is a rounded rect)
//   · 28-31 how smooth those corners are (smooth.mbt: 0 round, 1 wholly
//   smooth; as the box whose corner it is had room for). A shape's own
//   corner is as smooth as its rect has room for: the renderers say.
// kinds: 0 rounded rect, 1 glyph (alpha mask), 2 shadow (12 > 0: only
// outside its box, which is 13 above it), 3 color glyph, 4 image (12-15 its
// uv rect, 0-1), 5 frosted glass, 6 liquid glass, 7 a glyph in liquid glass
// inked by what is under it (glass.mbt), 9 a hole where a native view shows
// (written transparent, without blending: native.mbt), 10 a piece of a line
// (line.mbt: 4 half its width; 12-15 its ends, x0 y0 x1 y1 as shares of its
// rect, so that what moves or scales the rect takes its ends along; its ends
// round).

///|
let inst_size = 32

///|
fn Ctx::grow(self : Ctx) -> Unit {
  let old = self.inst
  let bigger = FixedArray::make(old.length() * 2, 0.0)
  old.blit_to(bigger, len=self.ninst * inst_size)
  self.inst = bigger
}

///|
/// What cuts what is painted now, a level per clipping node: 12 numbers each, its rect (x0 y0 x1 y1), its corners'
/// radii (top left, top right, bottom right, bottom left) and how smooth each is (smooth.mbt: as the box whose corner it
/// is has room for, kept as the corner is, so a list cut by a card's corners is cut as the card's ground is drawn), what
/// each instance carries (16-19, 24-31). A box with
/// `clip` and a `radius` cuts to its rounded rect (Compose's clip(RoundedCornerShape)), what it holds covered at the
/// edge as its own ground is (the renderers: 0.5 - d · scale of the rounded rect's distance; a clip with no rounded
/// corner cuts hard, at pixel centres, as before), and presses in what it cut away miss (Ctx::hit_clips).
/// Within other clips, the rule for where they meet: their rects' intersection, each of its corners as round as the
/// clips whose corner it is (both's: the rounder), square where it is no clip's corner. So a rect inside a rounded
/// clip (a list in a card, down to its foot) keeps the card's corners where they are its own, and a rounded clip in
/// a rounded clip is right wherever the inner lies within the outer or shares its corners. The error: where one
/// clip's edge cuts through another's rounded corner, not at its corner (a card scrolled part way out of a list, its
/// corner's curve across the list's edge), that corner is square, showing what lies between the curve and the
/// corner (at most (1 - π/4) r² of it); no stencil is kept.
// kept across runs: every clip a paint pushes it pops in the same paint, so between frames only its base level is
// left, the same in every run
let clip_stack : Array[Double] = [0.0, 0.0, 1.0e9, 1.0e9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

///|
/// The numbers a level of `clip_stack` has.
let clip_n = 12

///|
/// Where the clip painted in now starts in `clip_stack`.
fn clip_top() -> Int {
  clip_stack.length() - clip_n
}

///|
/// The corner of the clip `k` (in `clip_stack`) at its corner `corner` (0 top left, then clockwise) where (`x`, `y`) is
/// that corner: its radius and how smooth it is, else square (0, 0).
fn clip_corner_r(k : Int, corner : Int, x : Double, y : Double) -> (Double, Double) {
  let s = clip_stack
  let cx = if corner == 0 || corner == 3 { s[k] } else { s[k + 2] }
  let cy = if corner < 2 { s[k + 1] } else { s[k + 3] }
  if x == cx && y == cy {
    (s[k + 4 + corner], s[k + 8 + corner])
  } else {
    (0.0, 0.0)
  }
}

///|
/// A clip of its own rect (x0 y0 x1 y1, as given) pushed: its corners round where they are the clip it is in's.
fn push_clip(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  let k = clip_top()
  let (tl, stl) = clip_corner_r(k, 0, x0, y0)
  let (tr, s_tr) = clip_corner_r(k, 1, x1, y0)
  let (br, sbr) = clip_corner_r(k, 2, x1, y1)
  let (bl, sbl) = clip_corner_r(k, 3, x0, y1)
  push_clip_r(x0, y0, x1, y1, (tl, tr, br, bl), (stl, s_tr, sbr, sbl))
}

///|
/// A clip pushed: its rect (x0 y0 x1 y1), its corners' radii and how smooth each is (top left, then clockwise).
fn push_clip_r(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  r : (Double, Double, Double, Double),
  sm : (Double, Double, Double, Double),
) -> Unit {
  clip_stack.push(x0)
  clip_stack.push(y0)
  clip_stack.push(x1)
  clip_stack.push(y1)
  clip_stack.push(r.0)
  clip_stack.push(r.1)
  clip_stack.push(r.2)
  clip_stack.push(r.3)
  clip_stack.push(sm.0)
  clip_stack.push(sm.1)
  clip_stack.push(sm.2)
  clip_stack.push(sm.3)
}

///|
/// A node's clip pushed: its rect (`x`, `y`, `w`, `h`) rounded by `radius`, within the clip it is in.
fn push_round_clip(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
) -> Unit {
  let k = clip_top()
  let s = clip_stack
  let x0 = dmax(x, s[k])
  let y0 = dmax(y, s[k + 1])
  let x1 = dmin(x + w, s[k + 2])
  let y1 = dmin(y + h, s[k + 3])
  // as round, and as smooth, as its ground's corners are (the renderers cap a radius at half the shorter side, and
  // smooth it as far as the box has room for)
  let room = dmin(w, h) / 2.0
  let r = dmax(dmin(radius, room), 0.0)
  let sm = smoothness(r, room)
  // where a corner is both's, the rounder
  let corner = fn(j : Int, cx : Double, cy : Double, ox : Double, oy : Double) {
    let (pr, ps) = clip_corner_r(k, j, cx, cy)
    if r > 0.0 && cx == ox && cy == oy && r >= pr {
      (r, sm)
    } else {
      (pr, ps)
    }
  }
  let (tl, stl) = corner(0, x0, y0, x, y)
  let (tr, s_tr) = corner(1, x1, y0, x + w, y)
  let (br, sbr) = corner(2, x1, y1, x + w, y + h)
  let (bl, sbl) = corner(3, x0, y1, x, y + h)
  push_clip_r(x0, y0, x1, y1, (tl, tr, br, bl), (stl, s_tr, sbr, sbl))
}

///|
fn pop_clip() -> Unit {
  for _ in 0..<clip_n {
    clip_stack.pop() |> ignore
  }
}

///|
/// The clip `k` (in `clip_stack`): its rect, its corners' radii and how smooth they are.
fn clip_at(
  k : Int,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), (Double, Double, Double, Double)) {
  let s = clip_stack
  (
    (s[k], s[k + 1], s[k + 2], s[k + 3]),
    (s[k + 4], s[k + 5], s[k + 6], s[k + 7]),
    (s[k + 8], s[k + 9], s[k + 10], s[k + 11]),
  )
}

///|
/// Instance `b`'s clip moved to (`m0` `m1` `m2` `m3`), then cut to the clip `c` (rounded by `r`, as smooth as `sm`):
/// where that moves a corner, the corner is `c`'s (its radius, its smoothness) or square.
fn clamp_inst_clip(
  a : FixedArray[Double],
  b : Int,
  m0 : Double,
  m1 : Double,
  m2 : Double,
  m3 : Double,
  c : (Double, Double, Double, Double),
  r : (Double, Double, Double, Double),
  sm : (Double, Double, Double, Double),
) -> Unit {
  let (c0, c1, c2, c3) = c
  a[b + 16] = dmax(m0, c0)
  a[b + 17] = dmax(m1, c1)
  a[b + 18] = dmin(m2, c2)
  a[b + 19] = dmin(m3, c3)
  let corner = fn(
    j : Int,
    xi : Int,
    yi : Int,
    mx : Double,
    my : Double,
    cx : Double,
    cy : Double,
    cr : Double,
    cs : Double,
  ) {
    if a[b + xi] != mx || a[b + yi] != my {
      let theirs = a[b + xi] == cx && a[b + yi] == cy
      a[b + 24 + j] = if theirs { cr } else { 0.0 }
      a[b + 28 + j] = if theirs { cs } else { 0.0 }
    }
  }
  corner(0, 16, 17, m0, m1, c0, c1, r.0, sm.0)
  corner(1, 18, 17, m2, m1, c2, c1, r.1, sm.1)
  corner(2, 18, 19, m2, m3, c2, c3, r.2, sm.2)
  corner(3, 16, 19, m0, m3, c0, c3, r.3, sm.3)
}

///|
fn Ctx::push_inst(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  kind : Double,
  bw : Double,
  blur : Double,
  color : Int64,
  alpha : Double,
  c2a : Double,
  c2b : Double,
  c2c : Double,
  c2d : Double,
) -> Unit {
  if (self.ninst + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let b = self.ninst * inst_size
  let a = self.inst
  a[b] = x
  a[b + 1] = y
  a[b + 2] = w
  a[b + 3] = h
  a[b + 4] = radius
  a[b + 5] = kind
  a[b + 6] = bw
  a[b + 7] = blur
  a[b + 8] = ((color >> 24) & 0xFFL).to_double() / 255.0
  a[b + 9] = ((color >> 16) & 0xFFL).to_double() / 255.0
  a[b + 10] = ((color >> 8) & 0xFFL).to_double() / 255.0
  a[b + 11] = (color & 0xFFL).to_double() / 255.0 * alpha
  a[b + 12] = c2a
  a[b + 13] = c2b
  a[b + 14] = c2c
  a[b + 15] = c2d
  let k = clip_top()
  a[b + 16] = clip_stack[k]
  a[b + 17] = clip_stack[k + 1]
  a[b + 18] = clip_stack[k + 2]
  a[b + 19] = clip_stack[k + 3]
  a[b + 24] = clip_stack[k + 4]
  a[b + 25] = clip_stack[k + 5]
  a[b + 26] = clip_stack[k + 6]
  a[b + 27] = clip_stack[k + 7]
  a[b + 28] = clip_stack[k + 8]
  a[b + 29] = clip_stack[k + 9]
  a[b + 30] = clip_stack[k + 10]
  a[b + 31] = clip_stack[k + 11]
  a[b + 20] = 0.0 // the image it shows, if any
  // a rect's or frosted glass's notch (none); liquid glass and glyphs in it set theirs after
  a[b + 21] = 0.0
  a[b + 22] = 0.0
  a[b + 23] = 0.0
  self.ninst = self.ninst + 1
}

///|
/// The notch of node `n` (Ctx::box `notch_r`) on the instance just emitted for it (its ground or its glass): where
/// its circle's middle is below the top (21), its radius (22), its fillets' (23).
fn Ctx::notch_last(self : Ctx, n : Node) -> Unit {
  if n.notch_r <= 0.0 {
    return
  }
  let b = (self.ninst - 1) * inst_size
  self.inst[b + 21] = n.notch_y
  self.inst[b + 22] = n.notch_r
  self.inst[b + 23] = n.notch_f
}

///|
fn Ctx::emit_rect(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  color : Int64,
  bw : Double,
  bc : Int64,
  alpha : Double,
) -> Unit {
  let ba = (bc & 0xFFL).to_double() / 255.0 * alpha
  self.push_inst(
    x,
    y,
    w,
    h,
    radius,
    0.0,
    bw,
    0.0,
    color,
    if alpha == 0.0 { 1.0 } else { alpha },
    ((bc >> 24) & 0xFFL).to_double() / 255.0,
    ((bc >> 16) & 0xFFL).to_double() / 255.0,
    ((bc >> 8) & 0xFFL).to_double() / 255.0,
    ba,
  )
}

///|
fn Ctx::emit_text(
  self : Ctx,
  tl : TextLayout,
  ox : Double,
  oy : Double,
  color : Int64,
  alpha : Double,
  center_in? : Double = -1.0,
) -> Unit {
  let s = tl.shaped
  let n = s.starts.length()
  let k = clip_top()
  let cy0 = clip_stack[k + 1]
  let cy1 = clip_stack[k + 3]
  let sc = self.scale
  for c in 0..<n {
    let key = s.keys[c]
    if key < 0 {
      continue
    }
    let line = tl.line_of[c]
    let top = oy + line.to_double() * tl.line_h
    if top > cy1 || top + tl.line_h < cy0 {
      continue
    }
    let g = glyph(key)
    if g.gw <= 0.0 {
      continue
    }
    // centred: each line by half of what it leaves of the box
    let dx = if center_in >= 0.0 && line < tl.line_w.length() {
      dmax((center_in - tl.line_w[line]) / 2.0, 0.0)
    } else {
      0.0
    }
    let gx = ((ox + dx + tl.xs[c] + s.pad + g.ox) * sc).round() / sc
    let gy = ((top + tl.ascent + g.oy) * sc).round() / sc
    let adaptive = glass_paint.ink_r > 0.0 && !g.color
    self.push_inst(
      gx,
      gy,
      g.gw,
      g.gh,
      0.0,
      if g.color { 3.0 } else if adaptive { 7.0 } else { 1.0 },
      0.0,
      0.0,
      if g.color { 0xFFFFFFFFL } else { color },
      alpha,
      g.u,
      g.v,
      g.gw * sc,
      g.gh * sc,
    )
    if adaptive {
      let b = (self.ninst - 1) * inst_size
      self.inst[b + 21] = glass_paint.ink_x
      self.inst[b + 22] = glass_paint.ink_y
      self.inst[b + 23] = glass_paint.ink_r
    }
  }
}

///|
fn Ctx::paint(self : Ctx, i : Int, alpha_in : Double) -> Unit {
  // drawn by its look, tapped as laid out (draw.mbt), when it has one
  if dr.any && self.drawn_paint(i, alpha_in) {
    return
  }
  let n = self.nodes[i]
  let alpha = alpha_in * n.opacity
  if alpha <= 0.002 {
    return
  }
  let k = clip_top()
  let cx0 = clip_stack[k]
  let cy0 = clip_stack[k + 1]
  let cx1 = clip_stack[k + 2]
  let cy1 = clip_stack[k + 3]
  // cull what is outside the clip
  if (n.x > cx1 || n.y > cy1 || n.x + n.fw < cx0 || n.y + n.fh < cy0) &&
    !(dr.any && dr.mode != mode_hits && self.draw_carries(i)) {
    return
  }
  match n.glass {
    Some(gl) => self.paint_glass(n, gl, alpha)
    None => ()
  }
  if n.shadow > 0.0 && n.glass is None {
    self.push_inst(
      n.x,
      n.y + (if n.shadow_y >= 0.0 { n.shadow_y } else { n.shadow * 0.35 }),
      n.fw,
      n.fh,
      n.radius,
      2.0,
      0.0,
      n.shadow,
      n.shadow_c,
      alpha,
      0.0,
      0.0,
      0.0,
      0.0,
    )
  }
  if (n.bg & 0xFFL) != 0L || n.border_w > 0.0 {
    self.emit_rect(
      n.x,
      n.y,
      n.fw,
      n.fh,
      n.radius,
      n.bg,
      n.border_w,
      n.border_c,
      alpha,
    )
    self.notch_last(n)
  }
  if n.hit && n.id != 0 {
    self.push_hit(n.id, dmax(n.x, cx0), dmax(n.y, cy0), dmin(n.x + n.fw, cx1), dmin(n.y + n.fh, cy1))
  }
  // a modal's ground: the wheel stops at it too (overlay.mbt)
  if n.blocks && n.id != 0 {
    self.next_scroll_ids.push(n.id)
    self.next_scroll_rects.push(dmax(n.x, cx0))
    self.next_scroll_rects.push(dmax(n.y, cy0))
    self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
    self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
  }
  if n.lines.length() > 0 {
    self.paint_lines(n, alpha)
  }
  if n.kind == kind_text {
    match n.tl {
      Some(tl) =>
        self.emit_text(
          tl,
          n.x + n.pad_l,
          n.y + n.pad_t,
          n.color,
          alpha,
          center_in=if n.center {
            dmax(n.fw - n.pad_l - n.pad_r, 0.0)
          } else {
            -1.0
          },
        )
      None => ()
    }
    return
  }
  if n.kind == kind_rich {
    self.paint_rich(i, n, alpha)
    return
  }
  if n.kind == kind_editor {
    self.paint_editor(n, alpha)
    return
  }
  if n.kind == kind_image {
    self.paint_image(i, n, alpha)
    return
  }
  if n.kind == kind_native {
    self.paint_native(i, n)
    return
  }
  if n.kind == kind_page {
    self.paint_page(n, alpha)
    return
  }
  if n.kind == kind_list ||
    (
      n.id != 0 &&
      (pagers.contains(n.id) ||
      drags.contains(n.id) ||
      captures.contains(n.id) ||
      sideways.contains(n.id))
    ) {
    self.next_scroll_ids.push(n.id)
    self.next_scroll_rects.push(dmax(n.x, cx0))
    self.next_scroll_rects.push(dmax(n.y, cy0))
    self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
    self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
  }
  let clipped = n.clip
  if clipped {
    push_round_clip(n.x, n.y, n.fw, n.fh, n.radius)
  }
  let first_inst = self.ninst
  // liquid glass in a group: all of it first, so it merges; text in
  // adaptive liquid glass inked by what is under it
  let group = n.glass_group && !glass_paint.solid
  if group {
    self.emit_group_glass(i, alpha)
    glass_paint.in_group = glass_paint.in_group + 1
  }
  let ink = (glass_paint.ink_x, glass_paint.ink_y, glass_paint.ink_r)
  match n.glass {
    Some(gl) if gl.liquid && gl.adaptive && !glass_paint.solid => {
      glass_paint.ink_x = n.x + n.fw / 2.0
      glass_paint.ink_y = n.y + n.fh / 2.0
      glass_paint.ink_r = dmax(dmin(n.fw, n.fh) / 2.0, 1.0)
    }
    _ => ()
  }
  if n.kind == kind_list {
    // under its rows: what the motion package draws there (its rows gone, leaving)
    self.paint_underlay(i)
  }
  let mut c = n.first
  let mut over = false
  while c >= 0 {
    if dr.any && self.drawn_z(c) == 1 {
      over = true
    } else {
      self.paint(c, alpha)
    }
    c = self.nodes[c].next
  }
  if over {
    // what goes over its siblings, after them
    c = n.first
    while c >= 0 {
      if self.drawn_z(c) == 1 {
        self.paint(c, alpha)
      }
      c = self.nodes[c].next
    }
  }
  glass_paint.ink_x = ink.0
  glass_paint.ink_y = ink.1
  glass_paint.ink_r = ink.2
  if group {
    glass_paint.in_group = glass_paint.in_group - 1
  }
  if n.kind == kind_list {
    // Android's stretch past an end (scroll.mbt)
    match self.lists.get(n.id) {
      Some(st) if st.over > 0.0 => {
        let k = clip_top()
        self.stretch_rows(
          st,
          first_inst,
          n.y,
          n.fh,
          clip_stack[k + 1],
          clip_stack[k + 3],
        )
      }
      _ => ()
    }
  }
  if clipped {
    pop_clip()
  }
  if n.kind == kind_list {
    self.paint_scrollbar(n, alpha)
  }
}
