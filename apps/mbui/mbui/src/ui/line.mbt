// Lines (Compose's drawPath with a round-capped Stroke): drawn in a box, each piece of one an instance the renderers
// draw as it is (scene.mbt's kind 10: the distance to a piece, its ends round), so a line is there in the frame it is
// first built, nothing made or decoded for it first. A spinner's arc turning (Ctx::cycle for where it is), a line drawn
// by hand under words as it is drawn (`upto`).

///|
/// A box `w` by `h` that draws `lines` over its ground (in its own coordinates, from its top left).
pub fn Ctx::lines(self : Ctx, lines : Array[Line], w~ : Size, h~ : Size) -> Int {
  let i = self.alloc_part(kind_box, true, false)
  let n = self.nodes[i]
  n.w = w
  n.h = h
  n.lines = lines
  i
}

///|
/// A node's lines painted, each as far along it as it is drawn.
fn Ctx::paint_lines(self : Ctx, n : Node, alpha : Double) -> Unit {
  self.emit_lines(n.x, n.y, n.lines, alpha)
}

///|
/// `lines` drawn from (`ox`, `oy`) (an old view's box's, a node of the window's tree's), each as far along it as it says.
fn Ctx::emit_lines(self : Ctx, ox : Double, oy : Double, lines : Array[Line], alpha : Double) -> Unit {
  for ln in lines {
    let pts = ln.points
    if pts.is_empty() || ln.upto <= 0.0 || ln.width <= 0.0 {
      continue
    }
    let hw = ln.width / 2.0
    let mut total = 0.0
    for k in 1..<pts.length() {
      total = total + dist(pts[k - 1], pts[k])
    }
    // a single point, or none of its length: a dot
    if total == 0.0 {
      let (x, y) = pts[0]
      self.emit_line(ox + x, oy + y, ox + x, oy + y, hw, ln.color, alpha)
      continue
    }
    let mut left = total * dmin(ln.upto, 1.0)
    for k in 1..<pts.length() {
      let (ax, ay) = pts[k - 1]
      let (bx, by) = pts[k]
      let d = dist(pts[k - 1], pts[k])
      if d >= left {
        let t = if d > 0.0 { left / d } else { 0.0 }
        self.emit_line(ox + ax, oy + ay, ox + ax + (bx - ax) * t, oy + ay + (by - ay) * t, hw, ln.color, alpha)
        break
      }
      self.emit_line(ox + ax, oy + ay, ox + bx, oy + by, hw, ln.color, alpha)
      left = left - d
    }
  }
}

///|
fn dist(a : (Double, Double), b : (Double, Double)) -> Double {
  let dx = b.0 - a.0
  let dy = b.1 - a.1
  (dx * dx + dy * dy).sqrt()
}

///|
/// A piece of a line from (`ax`, `ay`) to (`bx`, `by`), `hw` half its width (scene.mbt's kind 10): its rect what it
/// covers and a pixel round it, its ends as shares of that rect.
fn Ctx::emit_line(
  self : Ctx,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  hw : Double,
  color : Int64,
  alpha : Double,
) -> Unit {
  let x0 = dmin(ax, bx) - hw - 1.0
  let y0 = dmin(ay, by) - hw - 1.0
  let w = (ax - bx).abs() + 2.0 * (hw + 1.0)
  let h = (ay - by).abs() + 2.0 * (hw + 1.0)
  self.push_inst(
    x0,
    y0,
    w,
    h,
    hw,
    10.0,
    0.0,
    0.0,
    color,
    alpha,
    (ax - x0) / w,
    (ay - y0) / h,
    (bx - x0) / w,
    (by - y0) / h,
  )
}

///|
/// The pieces of lines drawn in the last frame (Ctx::lines), each as (x0, y0, x1, y1, its width, its colour RRGGBBAA with
/// its opacity applied), in the window, where they are drawn.
pub fn Tester::drawn_lines(self : Tester) -> Array[(Double, Double, Double, Double, Double, Int64)] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    if a[b + 5] == 10.0 {
      let byte = fn(v : Double) { (v * 255.0 + 0.5).to_int64() & 0xFFL }
      // (turned: where the renderers turn its ends to, by 32 about 33, 34)
      let (ca, sa) = (@dmath.cos(a[b + 32]), @dmath.sin(a[b + 32]))
      let at = fn(x : Double, y : Double) {
        if a[b + 32] == 0.0 {
          (x, y)
        } else {
          let (dx, dy) = (x - a[b + 33], y - a[b + 34])
          (a[b + 33] + ca * dx - sa * dy, a[b + 34] + sa * dx + ca * dy)
        }
      }
      let (x0, y0) = at(a[b] + a[b + 12] * a[b + 2], a[b + 1] + a[b + 13] * a[b + 3])
      let (x1, y1) = at(a[b] + a[b + 14] * a[b + 2], a[b + 1] + a[b + 15] * a[b + 3])
      out.push(
        (
          x0,
          y0,
          x1,
          y1,
          a[b + 4] * 2.0,
          (byte(a[b + 8]) << 24) | (byte(a[b + 9]) << 16) | (byte(a[b + 10]) << 8) | byte(a[b + 11]),
        ),
      )
    }
  }
  out
}
