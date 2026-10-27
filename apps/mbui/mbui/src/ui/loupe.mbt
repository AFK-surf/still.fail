// What a finger hides, for a loupe to show (iOS's text loupe, Android's Magnifier; kit's loupe.mbt draws it): where a
// finger reads as it drags what needs seeing where it is (a field's caret or the ends of what is picked in it by their
// handles, a long press's word slid on: app.mbt's handle_drag, word_drag), and a box that shows what the frame drew
// round a point larger (Ctx::magnified).

///|
/// Where a finger reads now, if it drags what needs seeing there: a field's handle (the caret hanging loupe_reach over
/// the finger, its handle under it), or a long press's word slid on (under the finger itself). None else.
pub fn Ctx::finger_reads(self : Ctx) -> (Double, Double)? {
  if !self.down || !(pointing() is Finger) {
    return None
  }
  if self.handle_drag != 0 {
    Some((self.px, self.py - loupe_reach))
  } else if self.word_drag != 0 {
    Some((self.px, self.py))
  } else {
    None
  }
}

///|
/// How far over a finger dragging a field's handle what it moves is (its caret: editor.mbt's handle, hanging under it).
pub let loupe_reach : Double = 26.0

///|
/// A box `w` by `h`, as round as `round` (a capsule), showing what the frame drew round (`x`, `y`) `zoom` times as large, cut to it:
/// the frame's instances there, drawn before it, copied as it is painted; glass in it as the ground of its tint, what
/// is inked by glass left out. Drawn only.
pub fn Ctx::magnified(
  self : Ctx,
  x : Double,
  y : Double,
  zoom : Double,
  w : Double,
  h : Double,
  round? : Radius = Full,
) -> Int {
  let i = self.box(style=style(w=Fixed(w), h=Fixed(h), radius=round, clip=true), fn() {  })
  self.nodes[i].magnify = Some((x, y, zoom))
  i
}

///|
/// Node `n`'s magnified frame (Ctx::magnified), painted where it is.
fn Ctx::paint_magnified(self : Ctx, n : Node, m : (Double, Double, Double), alpha : Double) -> Unit {
  let (sx, sy, z) = m
  let (cx, cy) = (n.x + n.fw / 2.0, n.y + n.fh / 2.0)
  let (qx0, qy0) = (sx - n.fw / 2.0 / z, sy - n.fh / 2.0 / z)
  let (qx1, qy1) = (sx + n.fw / 2.0 / z, sy + n.fh / 2.0 / z)
  let count = self.ninst
  // its ground: the window's, under what it shows
  let (cr, cg, cb) = self.clear
  let ground = (((cr * 255.0).round().to_int64() & 0xFFL) << 24) |
    (((cg * 255.0).round().to_int64() & 0xFFL) << 16) |
    (((cb * 255.0).round().to_int64() & 0xFFL) << 8) |
    0xFFL
  self.emit_rect(n.x, n.y, n.fw, n.fh, n.radius, ground, 0.0, 0L, alpha)
  let i0 = self.ninst
  for k in 0..<count {
    let b = k * inst_size
    let a = self.inst
    let kind = a[b + 5]
    // (what is inked by glass and what punches through: left out)
    if kind == 7.0 || kind == 9.0 {
      continue
    }
    if a[b] > qx1 || a[b + 1] > qy1 || a[b] + a[b + 2] < qx0 || a[b + 1] + a[b + 3] < qy0 {
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
      // glass as the ground of its tint (a rect's alpha where glass has its opacity, 15): what it frosts is under it,
      // copied at its own size
      a[d + 5] = 0.0
      a[d + 11] = a[d + 15]
      for j in [6, 7, 12, 13, 14, 15, 20, 21, 22, 23] {
        a[d + j] = 0.0
      }
    }
    a[d + 11] = a[d + 11] * alpha
    self.ninst = self.ninst + 1
  }
  // larger about where it reads, in the box, cut to the clip it is painted in (its own: clip)
  let (outer, outer_r, outer_s) = clip_at(clip_top())
  self.transform_insts(i0, self.ninst, sx, sy, z, z, cx - sx, cy - sy, outer, outer_r, outer_s)
}
