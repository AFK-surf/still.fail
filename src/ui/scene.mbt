// Painting: the laid-out tree becomes a flat list of instances (24 floats
// each) that every renderer draws with one shader:
//   0-3 rect x y w h · 4 radius · 5 kind · 6 border width · 7 blur
//   8-11 color rgba · 12-15 border color, or the glyph's atlas rect
//   16-19 clip x0 y0 x1 y1 · 20 image id · 21-23 a notch in its top edge
//   (kinds 0 and 5: its circle's middle below the top, its radius, its
//   fillets'; 0 none: Ctx::box notch_r)
// kinds: 0 rounded rect, 1 glyph (alpha mask), 2 shadow (12 > 0: only
// outside its box, which is 13 above it), 3 color glyph, 4 image (12-15 its
// uv rect, 0-1), 5 frosted glass, 6 liquid glass, 7 a glyph in liquid glass
// inked by what is under it (glass.mbt), 9 a hole where a native view shows
// (written transparent, without blending: native.mbt).

///|
let inst_size = 24

///|
fn Ctx::grow(self : Ctx) -> Unit {
  let old = self.inst
  let bigger = FixedArray::make(old.length() * 2, 0.0)
  old.blit_to(bigger, len=self.ninst * inst_size)
  self.inst = bigger
}

///|
let clip_stack : Array[Double] = [0.0, 0.0, 1.0e9, 1.0e9]

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
  let k = clip_stack.length() - 4
  a[b + 16] = clip_stack[k]
  a[b + 17] = clip_stack[k + 1]
  a[b + 18] = clip_stack[k + 2]
  a[b + 19] = clip_stack[k + 3]
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
  let k = clip_stack.length() - 4
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
    let gx = ((ox + dx + tl.xs[c] + g.ox) * sc).round() / sc
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
  let k = clip_stack.length() - 4
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
    self.next_hit_ids.push(n.id)
    self.next_hit_rects.push(dmax(n.x, cx0))
    self.next_hit_rects.push(dmax(n.y, cy0))
    self.next_hit_rects.push(dmin(n.x + n.fw, cx1))
    self.next_hit_rects.push(dmin(n.y + n.fh, cy1))
  }
  // a modal's ground: the wheel stops at it too (overlay.mbt)
  if n.blocks && n.id != 0 {
    self.next_scroll_ids.push(n.id)
    self.next_scroll_rects.push(dmax(n.x, cx0))
    self.next_scroll_rects.push(dmax(n.y, cy0))
    self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
    self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
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
    clip_stack.push(dmax(n.x, cx0))
    clip_stack.push(dmax(n.y, cy0))
    clip_stack.push(dmin(n.x + n.fw, cx1))
    clip_stack.push(dmin(n.y + n.fh, cy1))
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
        let k = clip_stack.length() - 4
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
    for _ in 0..<4 {
      clip_stack.pop() |> ignore
    }
  }
  if n.kind == kind_list {
    self.paint_scrollbar(n, alpha)
  }
}
