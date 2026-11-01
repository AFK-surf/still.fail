// svgtypes' path data (path.rs: PathParser, SimplifyingPathParser) and kurbo's SVG arcs as cubics (kurbo svg.rs
// Arc::from_svg_arc, arc.rs append_iter): a `d` as absolute moves, lines, cubics, quads and closes.

///|
priv enum PSeg {
  PMove(Bool, Double, Double)
  PLine(Bool, Double, Double)
  PHLine(Bool, Double)
  PVLine(Bool, Double)
  PCurve(Bool, Double, Double, Double, Double, Double, Double)
  PSmooth(Bool, Double, Double, Double, Double)
  PQuad(Bool, Double, Double, Double, Double)
  PSmoothQuad(Bool, Double, Double)
  PArc(Bool, Double, Double, Double, Bool, Bool, Double, Double)
  PClose(Bool)
}

///|
pub(all) enum SimpleSeg {
  SMoveTo(Double, Double)
  SLineTo(Double, Double)
  SCurveTo(Double, Double, Double, Double, Double, Double)
  SQuadTo(Double, Double, Double, Double)
  SClose
} derive(Eq, Show, Debug)

///|
fn is_cmd(c : Int) -> Bool {
  match Int::unsafe_to_char(c) {
    'M' | 'm' | 'Z' | 'z' | 'L' | 'l' | 'H' | 'h' | 'V' | 'v' | 'C' | 'c' | 'S' | 's' | 'Q' | 'q' | 'T' | 't' | 'A'
    | 'a' => true
    _ => false
  }
}

///|
fn is_abs_cmd(c : Int) -> Bool {
  c >= 0x41 && c <= 0x5A
}

///|
fn is_number_start(c : Int) -> Bool {
  is_digit_b(c) || c == 0x2E || c == 0x2D || c == 0x2B
}

///|
fn Stream::parse_flag(self : Stream) -> Bool? {
  self.skip_spaces()
  let c = self.cur()
  if c == 0x30 || c == 0x31 {
    self.pos += 1
    if self.is_curr(0x2C) {
      self.pos += 1
    }
    self.skip_spaces()
    Some(c == 0x31)
  } else {
    None
  }
}

///|
/// The segments of `d` as written (PathParser), up to the first error (which ends it).
fn parse_path_segments(text : String) -> Array[PSeg] {
  let s = Stream::new(text)
  let out : Array[PSeg] = []
  let mut prev_cmd = -1
  while true {
    s.skip_spaces()
    if s.at_end() {
      break
    }
    let first = s.cur()
    let has_prev = prev_cmd != -1
    if !has_prev && !is_cmd(first) {
      break
    }
    if !has_prev && first != 0x4D && first != 0x6D {
      break
    }
    let mut implicit_move = false
    let mut cmd = 0
    if is_cmd(first) {
      cmd = first
      s.pos += 1
    } else if is_number_start(first) && has_prev {
      if prev_cmd == 0x5A || prev_cmd == 0x7A {
        break
      }
      if prev_cmd == 0x4D || prev_cmd == 0x6D {
        implicit_move = true
        cmd = if is_abs_cmd(prev_cmd) { 0x4C } else { 0x6C }
      } else {
        cmd = prev_cmd
      }
    } else {
      break
    }
    let abs = is_abs_cmd(cmd)
    let lower = if abs { cmd + 0x20 } else { cmd }
    let n = fn() { s.parse_list_number() }
    let seg : PSeg? = match Int::unsafe_to_char(lower) {
      'm' =>
        match (n(), n()) {
          (Some(x), Some(y)) => Some(PMove(abs, x, y))
          _ => None
        }
      'l' =>
        match (n(), n()) {
          (Some(x), Some(y)) => Some(PLine(abs, x, y))
          _ => None
        }
      'h' =>
        match n() {
          Some(x) => Some(PHLine(abs, x))
          None => None
        }
      'v' =>
        match n() {
          Some(y) => Some(PVLine(abs, y))
          None => None
        }
      'c' =>
        match (n(), n(), n(), n(), n(), n()) {
          (Some(a), Some(b), Some(c), Some(d), Some(e), Some(f)) => Some(PCurve(abs, a, b, c, d, e, f))
          _ => None
        }
      's' =>
        match (n(), n(), n(), n()) {
          (Some(a), Some(b), Some(c), Some(d)) => Some(PSmooth(abs, a, b, c, d))
          _ => None
        }
      'q' =>
        match (n(), n(), n(), n()) {
          (Some(a), Some(b), Some(c), Some(d)) => Some(PQuad(abs, a, b, c, d))
          _ => None
        }
      't' =>
        match (n(), n()) {
          (Some(x), Some(y)) => Some(PSmoothQuad(abs, x, y))
          _ => None
        }
      'a' => {
        let rx = n()
        let ry = n()
        let rot = n()
        let large = if rx is Some(_) && ry is Some(_) && rot is Some(_) { s.parse_flag() } else { None }
        let sweep = if large is Some(_) { s.parse_flag() } else { None }
        let x = if sweep is Some(_) { n() } else { None }
        let y = if x is Some(_) { n() } else { None }
        match (rx, ry, rot, large, sweep, x, y) {
          (Some(rx), Some(ry), Some(rot), Some(l), Some(sw), Some(x), Some(y)) => Some(PArc(abs, rx, ry, rot, l, sw, x, y))
          _ => None
        }
      }
      _ => Some(PClose(abs))
    }
    match seg {
      Some(seg) => out.push(seg)
      None => break
    }
    prev_cmd = if implicit_move { if abs { 0x4D } else { 0x6D } } else { cmd }
  }
  out
}

///|
/// `d` as absolute simple segments (SimplifyingPathParser), up to the first error.
fn parse_path_simple(text : String) -> Array[SimpleSeg] {
  let out : Array[SimpleSeg] = []
  let mut prev_mx = 0.0
  let mut prev_my = 0.0
  let mut prev_tx = 0.0
  let mut prev_ty = 0.0
  let mut prev_x = 0.0
  let mut prev_y = 0.0
  let mut prev_seg : PSeg = PMove(true, 0.0, 0.0)
  let mut prev_simple : SimpleSeg? = None
  for segment in parse_path_segments(text) {
    let buffer : Array[SimpleSeg] = []
    if prev_simple is Some(SClose) {
      match segment {
        PMove(_, _, _) | PClose(_) => ()
        _ => {
          let ns = SMoveTo(prev_mx, prev_my)
          buffer.push(ns)
          prev_simple = Some(ns)
        }
      }
    }
    match segment {
      PMove(abs, x, y) => {
        let mut x = x
        let mut y = y
        if !abs {
          if prev_simple is Some(SClose) {
            x = x + prev_mx
            y = y + prev_my
          } else {
            x = x + prev_x
            y = y + prev_y
          }
        }
        buffer.push(SMoveTo(x, y))
        prev_seg = segment
      }
      PLine(abs, x, y) => {
        let (x, y) = if abs { (x, y) } else { (x + prev_x, y + prev_y) }
        buffer.push(SLineTo(x, y))
        prev_seg = segment
      }
      PHLine(abs, x) => {
        let x = if abs { x } else { x + prev_x }
        buffer.push(SLineTo(x, prev_y))
        prev_seg = segment
      }
      PVLine(abs, y) => {
        let y = if abs { y } else { y + prev_y }
        buffer.push(SLineTo(prev_x, y))
        prev_seg = segment
      }
      PCurve(abs, x1, y1, x2, y2, x, y) => {
        let (x1, y1, x2, y2, x, y) = if abs {
          (x1, y1, x2, y2, x, y)
        } else {
          (x1 + prev_x, y1 + prev_y, x2 + prev_x, y2 + prev_y, x + prev_x, y + prev_y)
        }
        buffer.push(SCurveTo(x1, y1, x2, y2, x, y))
        prev_seg = PCurve(true, x1, y1, x2, y2, x, y)
      }
      PSmooth(abs, x2, y2, x, y) => {
        let (x1, y1) = match prev_seg {
          PCurve(_, _, _, px2, py2, px, py) | PSmooth(_, px2, py2, px, py) => (px * 2.0 - px2, py * 2.0 - py2)
          _ => (prev_x, prev_y)
        }
        let (x2, y2, x, y) = if abs { (x2, y2, x, y) } else { (x2 + prev_x, y2 + prev_y, x + prev_x, y + prev_y) }
        buffer.push(SCurveTo(x1, y1, x2, y2, x, y))
        prev_seg = PSmooth(true, x2, y2, x, y)
      }
      PQuad(abs, x1, y1, x, y) => {
        let (x1, y1, x, y) = if abs { (x1, y1, x, y) } else { (x1 + prev_x, y1 + prev_y, x + prev_x, y + prev_y) }
        buffer.push(SQuadTo(x1, y1, x, y))
        prev_seg = PQuad(true, x1, y1, x, y)
      }
      PSmoothQuad(abs, x, y) => {
        let (x1, y1) = match prev_seg {
          PQuad(_, qx1, qy1, qx, qy) => (qx * 2.0 - qx1, qy * 2.0 - qy1)
          PSmoothQuad(_, qx, qy) => (qx * 2.0 - prev_tx, qy * 2.0 - prev_ty)
          _ => (prev_x, prev_y)
        }
        prev_tx = x1
        prev_ty = y1
        let (x, y) = if abs { (x, y) } else { (x + prev_x, y + prev_y) }
        buffer.push(SQuadTo(x1, y1, x, y))
        prev_seg = PSmoothQuad(true, x, y)
      }
      PArc(abs, rx, ry, rot, large, sweep, x, y) => {
        let (x, y) = if abs { (x, y) } else { (x + prev_x, y + prev_y) }
        match svg_arc_to_cubics(prev_x, prev_y, x, y, rx, ry, to_radians_d(rot), large, sweep) {
          Some(cubics) => for c in cubics { buffer.push(c) }
          None => buffer.push(SLineTo(x, y))
        }
        prev_seg = segment
      }
      PClose(_) => {
        if !(prev_simple is Some(SClose)) {
          buffer.push(SClose)
        }
        prev_seg = segment
      }
    }
    if buffer.length() > 0 {
      let last = buffer[buffer.length() - 1]
      prev_simple = Some(last)
      match last {
        SMoveTo(x, y) => {
          prev_x = x
          prev_y = y
          prev_mx = x
          prev_my = y
        }
        SLineTo(x, y) | SCurveTo(_, _, _, _, x, y) | SQuadTo(_, _, x, y) => {
          prev_x = x
          prev_y = y
        }
        SClose => {
          prev_x = prev_mx
          prev_y = prev_my
        }
      }
    }
    out.append(buffer)
  }
  out
}

///|
/// kurbo: an SVG arc's ellipse arc as cubics at tolerance 0.1, None where it is a straight line.
fn svg_arc_to_cubics(
  fx : Double,
  fy : Double,
  tx : Double,
  ty : Double,
  rx : Double,
  ry : Double,
  x_rotation : Double,
  large_arc : Bool,
  sweep : Bool,
) -> Array[SimpleSeg]? {
  let pi = 3.141592653589793
  if rx.abs() <= 1.0e-5 || ry.abs() <= 1.0e-5 || (fx == tx && fy == ty) {
    return None
  }
  let mut rx = rx.abs()
  let mut ry = ry.abs()
  let xr = x_rotation % (2.0 * pi)
  let sin_phi = @dmath.sin(xr)
  let cos_phi = @dmath.cos(xr)
  let hd_x = (fx - tx) * 0.5
  let hd_y = (fy - ty) * 0.5
  let hs_x = (fx + tx) * 0.5
  let hs_y = (fy + ty) * 0.5
  let px = cos_phi * hd_x + sin_phi * hd_y
  let py = -sin_phi * hd_x + cos_phi * hd_y
  let rf = px * px / (rx * rx) + py * py / (ry * ry)
  if rf > 1.0 {
    let scale = rf.sqrt()
    rx = rx * scale
    ry = ry * scale
  }
  let rxry = rx * ry
  let rxpy = rx * py
  let rypx = ry * px
  let sum_of_sq = rxpy * rxpy + rypx * rypx
  let sign_coe = if large_arc == sweep { -1.0 } else { 1.0 }
  let coe = sign_coe * ((rxry * rxry - sum_of_sq) / sum_of_sq).abs().sqrt()
  let tcx = coe * rxpy / ry
  let tcy = -coe * rypx / rx
  let cx = cos_phi * tcx - sin_phi * tcy + hs_x
  let cy = sin_phi * tcx + cos_phi * tcy + hs_y
  let start_angle = @dmath.atan2((py - tcy) / ry, (px - tcx) / rx)
  let mut sweep_angle = (@dmath.atan2((-py - tcy) / ry, (-px - tcx) / rx) - start_angle) % (2.0 * pi)
  if sweep && sweep_angle < 0.0 {
    sweep_angle = sweep_angle + 2.0 * pi
  } else if !sweep && sweep_angle > 0.0 {
    sweep_angle = sweep_angle - 2.0 * pi
  }
  // append_iter
  let tolerance = 0.1
  let sign = if sweep_angle > 0.0 { 1.0 } else if sweep_angle < 0.0 { -1.0 } else if 1.0 / sweep_angle < 0.0 { -1.0 } else { 1.0 }
  let scaled_err = (if rx > ry { rx } else { ry }) / tolerance
  let n_err0 = @dmath.pow(1.1163 * scaled_err, 1.0 / 6.0)
  let n_err = if n_err0 > 3.999999 { n_err0 } else { 3.999999 }
  let n = (n_err * sweep_angle.abs() * (1.0 / (2.0 * pi))).ceil()
  let angle_step = sweep_angle / n
  let n = n.to_int()
  let arm_len = 4.0 / 3.0 * @dmath.tan((0.25 * angle_step).abs()) * sign
  let sample = fn(angle : Double) -> (Double, Double) {
    let u = rx * @dmath.cos(angle)
    let v = ry * @dmath.sin(angle)
    let s = @dmath.sin(x_rotation)
    let c = @dmath.cos(x_rotation)
    (u * c - v * s, u * s + v * c)
  }
  let mut angle0 = start_angle
  let mut p0 = sample(angle0)
  let out : Array[SimpleSeg] = []
  for _ in 0..<n {
    let angle1 = angle0 + angle_step
    let d0 = sample(angle0 + pi / 2.0)
    let p1 = (p0.0 + arm_len * d0.0, p0.1 + arm_len * d0.1)
    let p3 = sample(angle1)
    let d1 = sample(angle1 + pi / 2.0)
    let p2 = (p3.0 - arm_len * d1.0, p3.1 - arm_len * d1.1)
    angle0 = angle1
    p0 = p3
    out.push(SCurveTo(cx + p1.0, cy + p1.1, cx + p2.0, cy + p2.1, cx + p3.0, cy + p3.1))
  }
  Some(out)
}
