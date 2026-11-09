// tiny-skia's hairlines (src/scan/hairline.rs, hairline_aa.rs, after Skia's SkScan_Hairline.cpp and
// SkScan_Antihair.cpp): strokes thinner than a pixel drawn as lines, curves cut into lines; the anti-aliased ones
// and anti-aliased rects with partial coverage at their edges.

///|
let max_cubic_subdivide_level : Int = 9

///|
let max_quad_subdivide_level : Int = 5

///|
/// A hairline's line procedure: plain (hair_line_rgn) or anti-aliased (anti_hair_line_rgn).
priv enum LineProc {
  PlainLines
  AntiLines
}

///|
fn LineProc::call(self : LineProc, points : Array[Point], clip : ScreenIntRect?, blitter : &Blitter) -> Unit {
  match self {
    PlainLines => hair_line_rgn(points, clip, blitter)
    AntiLines => anti_hair_line_rgn(points, clip, blitter)
  }
}

///|
fn hairline_stroke_path(path : Path, line_cap : LineCap, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  stroke_path_impl(path, line_cap, clip, PlainLines, blitter)
}

///|
fn hairline_aa_stroke_path(path : Path, line_cap : LineCap, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  stroke_path_impl(path, line_cap, clip, AntiLines, blitter)
}

///|
fn hair_line_rgn(points : Array[Point], clip : ScreenIntRect?, blitter : &Blitter) -> Unit {
  let max : Float = 32767.0
  let fixed_bounds = Rect::from_ltrb(-max, -max, max, max).unwrap()
  let clip_bounds = match clip {
    Some(c) => Some(c.to_rect())
    None => None
  }
  for i in 0..<(points.length() - 1) {
    let pts = [Point::zero(), Point::zero()]
    if !line_intersect([points[i], points[i + 1]], fixed_bounds, pts) {
      continue
    }
    match clip_bounds {
      Some(cb) => {
        let tmp = [pts[0], pts[1]]
        if !line_intersect(tmp, cb, pts) {
          continue
        }
      }
      None => ()
    }
    let mut x0 = fdot6_from_f32(pts[0].x)
    let mut y0 = fdot6_from_f32(pts[0].y)
    let mut x1 = fdot6_from_f32(pts[1].x)
    let mut y1 = fdot6_from_f32(pts[1].y)
    let dx = x1 - x0
    let dy = y1 - y0
    if dx.abs() > dy.abs() {
      if x0 > x1 {
        let t = x0
        x0 = x1
        x1 = t
        let t = y0
        y0 = y1
        y1 = t
      }
      let mut ix0 = fdot6_round(x0)
      let ix1 = fdot6_round(x1)
      if ix0 == ix1 {
        continue
      }
      let slope = fdot16_div(dy, dx)
      let mut start_y = fdot6_to_fdot16(y0) + ((slope * ((32 - x0) & 63)) >> 6)
      let max_y = match clip_bounds {
        Some(cb) => fdot16_from_f32(cb.bottom)
        None => 2147483647
      }
      while true {
        if ix0 >= 0 && start_y >= 0 && start_y < max_y {
          blitter.blit_h(ix0, start_y >> 16, 1)
        }
        start_y += slope
        ix0 += 1
        if ix0 >= ix1 {
          break
        }
      }
    } else {
      if y0 > y1 {
        let t = x0
        x0 = x1
        x1 = t
        let t = y0
        y0 = y1
        y1 = t
      }
      let mut iy0 = fdot6_round(y0)
      let iy1 = fdot6_round(y1)
      if iy0 == iy1 {
        continue
      }
      let slope = fdot16_div(dx, dy)
      let mut start_x = fdot6_to_fdot16(x0) + ((slope * ((32 - y0) & 63)) >> 6)
      while true {
        if start_x >= 0 && iy0 >= 0 {
          blitter.blit_h(start_x >> 16, iy0, 1)
        }
        start_x += slope
        iy0 += 1
        if iy0 >= iy1 {
          break
        }
      }
    }
  }
}

///|
fn stroke_path_impl(path : Path, line_cap : LineCap, clip : ScreenIntRect, line_proc : LineProc, blitter : &Blitter) -> Unit {
  let mut inset_clip : IntRect? = None
  let mut outset_clip : IntRect? = None
  let cap_out : Float = if line_cap == Butt { 1.0 } else { 2.0 }
  let ibounds = match path.bounds.outset(cap_out, cap_out) {
    Some(r) =>
      match r.round_out() {
        Some(v) => v
        None => return
      }
    None => return
  }
  let cr = clip.to_int_rect()
  if cr.intersect(ibounds) is None {
    return
  }
  if !cr.contains(ibounds) {
    match cr.make_outset(1, 1) {
      Some(v) => outset_clip = Some(v)
      None => return
    }
    match cr.inset(1, 1) {
      Some(v) => inset_clip = Some(v)
      None => return
    }
  }
  let clip = Some(clip)
  let mut prev_verb : PathVerb = Move
  let mut first_pt = Point::zero()
  let mut last_pt = Point::zero()
  let iter = path.segments()
  while iter.next() is Some(segment) {
    let verb = iter.curr_verb()
    let next_verb = iter.next_verb()
    let mut last_pt2 = Point::zero()
    match segment {
      MoveTo(p) => {
        first_pt = p
        last_pt = p
        last_pt2 = p
      }
      LineTo(p) => {
        let points = [last_pt, p]
        if line_cap != Butt {
          extend_pts(line_cap, prev_verb, next_verb, points)
        }
        line_proc.call(points, clip, blitter)
        last_pt = p
        last_pt2 = points[0]
      }
      QuadTo(p0, p1) => {
        let points = [last_pt, p0, p1]
        if line_cap != Butt {
          extend_pts(line_cap, prev_verb, next_verb, points)
        }
        hair_quad(points, clip, inset_clip, outset_clip, compute_quad_level(points), line_proc, blitter)
        last_pt = p1
        last_pt2 = points[0]
      }
      CubicTo(p0, p1, p2) => {
        let points = [last_pt, p0, p1, p2]
        if line_cap != Butt {
          extend_pts(line_cap, prev_verb, next_verb, points)
        }
        hair_cubic(points, clip, inset_clip, outset_clip, line_proc, blitter)
        last_pt = p2
        last_pt2 = points[0]
      }
      Close => {
        let points = [last_pt, first_pt]
        if line_cap != Butt && prev_verb == Move {
          extend_pts(line_cap, prev_verb, next_verb, points)
        }
        line_proc.call(points, clip, blitter)
        last_pt2 = points[0]
      }
    }
    if line_cap != Butt {
      if prev_verb == Move && (verb == Line || verb == Quad || verb == Cubic) {
        first_pt = last_pt2
      }
      prev_verb = verb
    }
  }
}

///|
fn extend_pts(line_cap : LineCap, prev_verb : PathVerb, next_verb : PathVerb?, points : Array[Point]) -> Unit {
  let n = points.length()
  let cap_outset : Float = if line_cap == Square { 0.5 } else { float_pi / 8.0 }
  if prev_verb == Move {
    let first = points[0]
    let mut offset = 0
    let mut controls = n - 1
    let mut tangent = Point::zero()
    while true {
      offset += 1
      tangent = first - points[offset]
      if !tangent.is_zero() {
        break
      }
      controls -= 1
      if controls == 0 {
        break
      }
    }
    if tangent.is_zero() {
      tangent = Point::from_xy(1.0, 0.0)
      controls = n - 1
    } else {
      tangent = tangent.normalized().unwrap_or(Point::zero())
    }
    offset = 0
    while true {
      points[offset] = { x: points[offset].x + tangent.x * cap_outset, y: points[offset].y + tangent.y * cap_outset }
      offset += 1
      controls += 1
      if controls >= n {
        break
      }
    }
  }
  if next_verb is (Some(Move) | Some(Close) | None) {
    let last = points[n - 1]
    let mut offset = n - 1
    let mut controls = n - 1
    let mut tangent = Point::zero()
    while true {
      offset -= 1
      tangent = last - points[offset]
      if !tangent.is_zero() {
        break
      }
      controls -= 1
      if controls == 0 {
        break
      }
    }
    if tangent.is_zero() {
      tangent = Point::from_xy(-1.0, 0.0)
      controls = n - 1
    } else {
      tangent = tangent.normalized().unwrap_or(Point::zero())
    }
    offset = n - 1
    while true {
      points[offset] = { x: points[offset].x + tangent.x * cap_outset, y: points[offset].y + tangent.y * cap_outset }
      offset -= 1
      controls += 1
      if controls >= n {
        break
      }
    }
  }
}

///|
fn hair_quad(
  points : Array[Point],
  clip : ScreenIntRect?,
  inset_clip : IntRect?,
  outset_clip : IntRect?,
  level : Int,
  line_proc : LineProc,
  blitter : &Blitter,
) -> Unit {
  let mut clip = clip
  match inset_clip {
    Some(ic) => {
      let inset_clip = ic.to_rect()
      let outset_clip = match outset_clip {
        Some(v) => v.to_rect()
        None => return
      }
      let bounds = match compute_nocheck_bounds(points) {
        Some(v) => v
        None => return
      }
      if !geometric_overlap(outset_clip, bounds) {
        return
      } else if geometric_contains(inset_clip, bounds) {
        clip = None
      }
    }
    None => ()
  }
  hair_quad2(points, clip, level, line_proc, blitter)
}

///|
/// f32x2 min/max lanes (pmin, pmax) over the points.
fn compute_nocheck_bounds(points : Array[Point]) -> Rect? {
  let mut minx = points[0].x
  let mut miny = points[0].y
  let mut maxx = minx
  let mut maxy = miny
  for i in 1..<points.length() {
    let p = points[i]
    minx = if p.x < minx { p.x } else { minx }
    miny = if p.y < miny { p.y } else { miny }
    maxx = if maxx < p.x { p.x } else { maxx }
    maxy = if maxy < p.y { p.y } else { maxy }
  }
  Rect::from_ltrb(minx, miny, maxx, maxy)
}

///|
fn geometric_overlap(a : Rect, b : Rect) -> Bool {
  a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
}

///|
fn geometric_contains(outer : Rect, inner : Rect) -> Bool {
  inner.right <= outer.right && inner.left >= outer.left && inner.bottom <= outer.bottom && inner.top >= outer.top
}

///|
fn hair_quad2(points : Array[Point], clip : ScreenIntRect?, level : Int, line_proc : LineProc, blitter : &Blitter) -> Unit {
  let coeff = QuadCoeff::from_points(points)
  let lines = 1 << level
  let tmp = Array::make(lines + 1, Point::zero())
  tmp[0] = points[0]
  let mut t : Float = 0.0
  let dt : Float = 1.0 / fi(lines)
  for i in 1..<lines {
    t = t + dt
    tmp[i] = coeff.eval(t)
  }
  tmp[lines] = points[2]
  line_proc.call(tmp, clip, blitter)
}

///|
fn compute_quad_level(points : Array[Point]) -> Int {
  let d = compute_int_quad_dist(points)
  let mut level = (33 - d.clz()) >> 1
  if level > max_quad_subdivide_level {
    level = max_quad_subdivide_level
  }
  level
}

///|
fn compute_int_quad_dist(points : Array[Point]) -> Int {
  let dx = (half(points[0].x + points[2].x) - points[1].x).abs()
  let dy = (half(points[0].y + points[2].y) - points[1].y).abs()
  let idx = saturate_i32(dx.ceil())
  let idy = saturate_i32(dy.ceil())
  if idx.reinterpret_as_uint() > idy.reinterpret_as_uint() {
    idx + (idy.reinterpret_as_uint() >> 1).reinterpret_as_int()
  } else {
    idy + (idx.reinterpret_as_uint() >> 1).reinterpret_as_int()
  }
}

///|
fn hair_cubic(
  points : Array[Point],
  clip : ScreenIntRect?,
  inset_clip : IntRect?,
  outset_clip : IntRect?,
  line_proc : LineProc,
  blitter : &Blitter,
) -> Unit {
  let mut clip = clip
  match inset_clip {
    Some(ic) => {
      let inset_clip = ic.to_rect()
      let outset_clip = match outset_clip {
        Some(v) => v.to_rect()
        None => return
      }
      let bounds = match compute_nocheck_bounds(points) {
        Some(v) => v
        None => return
      }
      if !geometric_overlap(outset_clip, bounds) {
        return
      } else if geometric_contains(inset_clip, bounds) {
        clip = None
      }
    }
    None => ()
  }
  if quick_cubic_niceness_check(points) {
    hair_cubic2(points, clip, line_proc, blitter)
  } else {
    let tmp = Array::make(13, Point::zero())
    let t_values = new_t_values()
    let count = chop_cubic_at_max_curvature(points, t_values, tmp)
    for i in 0..<count {
      let o = i * 3
      hair_cubic2([tmp[o], tmp[o + 1], tmp[o + 2], tmp[o + 3]], clip, line_proc, blitter)
    }
  }
}

///|
fn quick_cubic_niceness_check(points : Array[Point]) -> Bool {
  lt_90(points[1], points[0], points[3]) &&
  lt_90(points[2], points[0], points[3]) &&
  lt_90(points[1], points[3], points[0]) &&
  lt_90(points[2], points[3], points[0])
}

///|
fn lt_90(p0 : Point, pivot : Point, p2 : Point) -> Bool {
  (p0 - pivot).dot(p2 - pivot) >= 0.0
}

///|
fn hair_cubic2(points : Array[Point], clip : ScreenIntRect?, line_proc : LineProc, blitter : &Blitter) -> Unit {
  let lines = compute_cubic_segments(points)
  if lines == 1 {
    line_proc.call([points[0], points[3]], clip, blitter)
    return
  }
  let coeff = CubicCoeff::from_points(points)
  let tmp = Array::make(lines + 1, Point::zero())
  let dt : Float = 1.0 / fi(lines)
  let mut t : Float = 0.0
  tmp[0] = points[0]
  for i in 1..<lines {
    t = t + dt
    tmp[i] = coeff.eval(t)
  }
  if tmp.iter().all(fn(p) { p.is_finite() }) {
    tmp[lines] = points[3]
    line_proc.call(tmp, clip, blitter)
  }
}

///|
fn compute_cubic_segments(points : Array[Point]) -> Int {
  let one_third : Float = 1.0 / 3.0
  let two_third : Float = 2.0 / 3.0
  let p0 = points[0]
  let p1 = points[1]
  let p2 = points[2]
  let p3 = points[3]
  let p13x = one_third * p3.x + two_third * p0.x
  let p13y = one_third * p3.y + two_third * p0.y
  let p23x = one_third * p0.x + two_third * p3.x
  let p23y = one_third * p0.y + two_third * p3.y
  let pmax = fn(a : Float, b : Float) { if a < b { b } else { a } }
  let dx = pmax((p1.x - p13x).abs(), (p2.x - p23x).abs())
  let dy = pmax((p1.y - p13y).abs(), (p2.y - p23y).abs())
  let diff = pmax(dx, dy)
  let mut tol : Float = 1.0 / 8.0
  for i in 0..<max_cubic_subdivide_level {
    if diff < tol {
      return 1 << i
    }
    tol = tol * 4.0
  }
  1 << max_cubic_subdivide_level
}

// ── anti-aliased ──────────────────────────────────────────────────────

///|
fn alpha_mul(value : Int, alpha256 : Int) -> Int {
  ((value * alpha256) >> 8) & 0xFF
}

///|
fn fill_rect_aa(rect : Rect, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  let rect = match rect.intersect(clip.to_rect()) {
    Some(v) => v
    None => return
  }
  fill_dot8(
    fdot8_from_fdot16(fdot16_from_f32(rect.left)),
    fdot8_from_fdot16(fdot16_from_f32(rect.top)),
    fdot8_from_fdot16(fdot16_from_f32(rect.right)),
    fdot8_from_fdot16(fdot16_from_f32(rect.bottom)),
    true,
    blitter,
  )
}

///|
fn fill_dot8(l : Int, t : Int, r : Int, b : Int, fill_inner : Bool, blitter : &Blitter) -> Unit {
  if l >= r || t >= b {
    return
  }
  let mut top = t >> 8
  if top == (b - 1) >> 8 {
    do_scanline(l, top, r, (b - t - 1) & 0xFF, blitter)
    return
  }
  if (t & 0xFF) != 0 {
    do_scanline(l, top, r, (256 - (t & 0xFF)) & 0xFF, blitter)
    top += 1
  }
  let bottom = b >> 8
  let height = bottom - top
  if height > 0 {
    let mut left = l >> 8
    if left == (r - 1) >> 8 {
      if left >= 0 && top >= 0 {
        blitter.blit_v(left, top, height, (r - l - 1) & 0xFF)
      }
    } else {
      if (l & 0xFF) != 0 {
        if left >= 0 && top >= 0 {
          blitter.blit_v(left, top, height, (256 - (l & 0xFF)) & 0xFF)
        }
        left += 1
      }
      let right = r >> 8
      let width = right - left
      if fill_inner {
        if width > 0 && left >= 0 && top >= 0 {
          blitter.blit_rect({ x: left, y: top, width, height })
        }
      }
      if (r & 0xFF) != 0 {
        if right >= 0 && top >= 0 {
          blitter.blit_v(right, top, height, (r & 0xFF) & 0xFF)
        }
      }
    }
  }
  if (b & 0xFF) != 0 {
    do_scanline(l, bottom, r, (b & 0xFF) & 0xFF, blitter)
  }
}

///|
fn do_scanline(l : Int, top : Int, r : Int, alpha : Int, blitter : &Blitter) -> Unit {
  if top < 0 {
    return
  }
  if l >> 8 == (r - 1) >> 8 {
    if l >> 8 >= 0 {
      blitter.blit_v(l >> 8, top, 1, alpha_mul(alpha, r - l))
    }
    return
  }
  let mut left = l >> 8
  if (l & 0xFF) != 0 {
    if l >> 8 >= 0 {
      blitter.blit_v(l >> 8, top, 1, alpha_mul(alpha, 256 - (l & 0xFF)))
    }
    left += 1
  }
  let right = r >> 8
  let width = right - left
  if width > 0 && left >= 0 {
    call_hline_blitter(left, Some(top), width, alpha, blitter)
  }
  if (r & 0xFF) != 0 {
    if right >= 0 {
      blitter.blit_v(right, top, 1, alpha_mul(alpha, r & 0xFF))
    }
  }
}

///|
fn call_hline_blitter(x : Int, y : Int?, count : Int, alpha : Int, blitter : &Blitter) -> Unit {
  let buffer = 100
  let runs = FixedArray::make(buffer + 1, 0)
  let aa = FixedArray::make(buffer, 0)
  let mut x = x
  let mut count = count
  while true {
    aa[0] = alpha
    let mut n = count
    if n > buffer {
      n = buffer
    }
    runs[0] = n
    runs[n] = 0
    match y {
      Some(y) => blitter.blit_anti_h(x, y, aa, runs)
      None => ()
    }
    x += n
    if n >= count || count == 0 {
      break
    }
    count -= n
  }
}

///|
fn anti_hair_line_rgn(points : Array[Point], clip : ScreenIntRect?, blitter : &Blitter) -> Unit {
  let max : Float = 32767.0
  let fixed_bounds = Rect::from_ltrb(-max, -max, max, max).unwrap()
  let clip_bounds = match clip {
    Some(c) => c.to_rect().outset(1.0, 1.0)
    None => None
  }
  for i in 0..<(points.length() - 1) {
    let pts = [Point::zero(), Point::zero()]
    if !line_intersect([points[i], points[i + 1]], fixed_bounds, pts) {
      continue
    }
    match clip_bounds {
      Some(cb) => {
        let tmp = [pts[0], pts[1]]
        if !line_intersect(tmp, cb, pts) {
          continue
        }
      }
      None => ()
    }
    let x0 = fdot6_from_f32(pts[0].x)
    let y0 = fdot6_from_f32(pts[0].y)
    let x1 = fdot6_from_f32(pts[1].x)
    let y1 = fdot6_from_f32(pts[1].y)
    match clip {
      Some(c) => {
        let left = if x0 < x1 { x0 } else { x1 }
        let top = if y0 < y1 { y0 } else { y1 }
        let right = if x0 > x1 { x0 } else { x1 }
        let bottom = if y0 > y1 { y0 } else { y1 }
        let ir = match
          IntRect::from_ltrb(fdot6_floor(left) - 1, fdot6_floor(top) - 1, fdot6_ceil(right) + 1, fdot6_ceil(bottom) + 1) {
          Some(v) => v
          None => return
        }
        let cr = c.to_int_rect()
        if cr.intersect(ir) is None {
          continue
        }
        if !cr.contains(ir) {
          match ir.intersect(cr) {
            Some(r) =>
              match r.to_screen_int_rect() {
                Some(sub) => do_anti_hairline(x0, y0, x1, y1, Some(sub), blitter)
                None => ()
              }
            None => ()
          }
          continue
        }
      }
      None => ()
    }
    do_anti_hairline(x0, y0, x1, y1, None, blitter)
  }
}

///|
priv enum HairKind {
  HLine
  Horish
  VLine
  Vertish
}

///|
fn do_anti_hairline(x0 : Int, y0 : Int, x1 : Int, y1 : Int, clip_opt : ScreenIntRect?, blitter : &Blitter) -> Unit {
  let mut x0 = x0
  let mut y0 = y0
  let mut x1 = x1
  let mut y1 = y1
  let mut clip_opt = clip_opt
  if any_bad_ints(x0, y0, x1, y1) != 0 {
    return
  }
  if (x1 - x0).abs() > fdot6_from_i32(511) || (y1 - y0).abs() > fdot6_from_i32(511) {
    let hx = (x0 >> 1) + (x1 >> 1)
    let hy = (y0 >> 1) + (y1 >> 1)
    do_anti_hairline(x0, y0, hx, hy, clip_opt, blitter)
    do_anti_hairline(hx, hy, x1, y1, clip_opt, blitter)
    return
  }
  let mut scale_start = 0
  let mut scale_stop = 0
  let mut istart = 0
  let mut istop = 0
  let mut fstart = 0
  let mut slope = 0
  let mut kind = HLine
  if (x1 - x0).abs() > (y1 - y0).abs() {
    if x0 > x1 {
      let t = x0
      x0 = x1
      x1 = t
      let t = y0
      y0 = y1
      y1 = t
    }
    istart = fdot6_floor(x0)
    istop = fdot6_ceil(x1)
    fstart = fdot6_to_fdot16(y0)
    if y0 == y1 {
      slope = 0
      kind = HLine
    } else {
      slope = fdot16_fast_div(y1 - y0, x1 - x0)
      fstart += (slope * (32 - (x0 & 63)) + 32) >> 6
      kind = Horish
    }
    if istop - istart == 1 {
      scale_start = x1 - x0
      scale_stop = 0
    } else {
      scale_start = 64 - (x0 & 63)
      scale_stop = x1 & 63
    }
    match clip_opt {
      Some(c) => {
        let clip = c.to_int_rect()
        if istart >= clip.right() || istop <= clip.left() {
          return
        }
        if istart < clip.left() {
          fstart += slope * (clip.left() - istart)
          istart = clip.left()
          scale_start = 64
          if istop - istart == 1 {
            scale_start = contribution_64(x1)
            scale_stop = 0
          }
        }
        if istop > clip.right() {
          istop = clip.right()
          scale_stop = 0
        }
        if istart == istop {
          return
        }
        let (top0, bottom0) = if slope >= 0 {
          (
            fdot16_floor_to_i32(fstart - fdot16_half),
            fdot16_ceil_to_i32(fstart + (istop - istart - 1) * slope + fdot16_half),
          )
        } else {
          (
            fdot16_floor_to_i32(fstart + (istop - istart - 1) * slope - fdot16_half),
            fdot16_ceil_to_i32(fstart + fdot16_half),
          )
        }
        let top = top0 - 1
        let bottom = bottom0 + 1
        if top >= clip.bottom() || bottom <= clip.top() {
          return
        }
        if clip.top() <= top && clip.bottom() >= bottom {
          clip_opt = None
        }
      }
      None => ()
    }
  } else {
    if y0 > y1 {
      let t = x0
      x0 = x1
      x1 = t
      let t = y0
      y0 = y1
      y1 = t
    }
    istart = fdot6_floor(y0)
    istop = fdot6_ceil(y1)
    fstart = fdot6_to_fdot16(x0)
    if x0 == x1 {
      if y0 == y1 {
        return
      }
      slope = 0
      kind = VLine
    } else {
      slope = fdot16_fast_div(x1 - x0, y1 - y0)
      fstart += (slope * (32 - (y0 & 63)) + 32) >> 6
      kind = Vertish
    }
    if istop - istart == 1 {
      scale_start = y1 - y0
      scale_stop = 0
    } else {
      scale_start = 64 - (y0 & 63)
      scale_stop = y1 & 63
    }
    match clip_opt {
      Some(c) => {
        let clip = c.to_int_rect()
        if istart >= clip.bottom() || istop <= clip.top() {
          return
        }
        if istart < clip.top() {
          fstart += slope * (clip.top() - istart)
          istart = clip.top()
          scale_start = 64
          if istop - istart == 1 {
            scale_start = contribution_64(y1)
            scale_stop = 0
          }
        }
        if istop > clip.bottom() {
          istop = clip.bottom()
          scale_stop = 0
        }
        if istart == istop {
          return
        }
        let (left0, right0) = if slope >= 0 {
          (
            fdot16_floor_to_i32(fstart - fdot16_half),
            fdot16_ceil_to_i32(fstart + (istop - istart - 1) * slope + fdot16_half),
          )
        } else {
          (
            fdot16_floor_to_i32(fstart + (istop - istart - 1) * slope - fdot16_half),
            fdot16_ceil_to_i32(fstart + fdot16_half),
          )
        }
        let left = left0 - 1
        let right = right0 + 1
        if left >= clip.right() || right <= clip.left() {
          return
        }
        if clip.left() <= left && clip.right() >= right {
          clip_opt = None
        }
      }
      None => ()
    }
  }
  let blitter : &Blitter = match clip_opt {
    Some(clip) => (({ blitter, clip } : RectClipBlitter) as &Blitter)
    None => blitter
  }
  let istart = istart
  fstart = hair_draw_cap(kind, blitter, istart, fstart, slope, scale_start)
  let istart = istart + 1
  let full_spans = istop - istart - (if scale_stop > 0 { 1 } else { 0 })
  if full_spans > 0 {
    fstart = hair_draw_line(kind, blitter, istart, istart + full_spans, fstart, slope)
  }
  if scale_stop > 0 {
    ignore(hair_draw_cap(kind, blitter, istop - 1, fstart, slope, scale_stop))
  }
}

///|
fn bad_int(x : Int) -> Int {
  x & -x
}

///|
fn any_bad_ints(a : Int, b : Int, c : Int, d : Int) -> Int {
  (bad_int(a) | bad_int(b) | bad_int(c) | bad_int(d)) >> 31
}

///|
fn contribution_64(ordinate : Int) -> Int {
  ((ordinate - 1) & 63) + 1
}

///|
fn i32_to_alpha(a : Int) -> Int {
  a & 0xFF
}

///|
/// u32's `max(1) - 1`
fn minus1(v : Int) -> Int {
  (if v < 1 { 1 } else { v }) - 1
}

///|
fn hair_draw_cap(kind : HairKind, blitter : &Blitter, x : Int, fy : Int, slope : Int, mod64 : Int) -> Int {
  match kind {
    HLine => {
      let fy = fy + fdot16_one / 2
      let fy = if fy < 0 { 0 } else { fy }
      let y = fy >> 16
      let a = i32_to_alpha(fy >> 8)
      let ma = fdot6_small_scale(a, mod64)
      if ma != 0 {
        call_hline_blitter(x, Some(y), 1, ma, blitter)
      }
      let ma = fdot6_small_scale(255 - a, mod64)
      if ma != 0 {
        call_hline_blitter(x, if y >= 1 { Some(y - 1) } else { None }, 1, ma, blitter)
      }
      fy - fdot16_one / 2
    }
    Horish => {
      let fy = fy + fdot16_one / 2
      let fy = if fy < 0 { 0 } else { fy }
      let lower_y = fy >> 16
      let a = i32_to_alpha(fy >> 8)
      let a0 = fdot6_small_scale(255 - a, mod64)
      let a1 = fdot6_small_scale(a, mod64)
      blitter.blit_anti_v2(x, minus1(lower_y), a0, a1)
      fy + slope - fdot16_one / 2
    }
    VLine => {
      let fx = fy + fdot16_one / 2
      let fx = if fx < 0 { 0 } else { fx }
      let xx = fx >> 16
      let a = i32_to_alpha(fx >> 8)
      let ma = fdot6_small_scale(a, mod64)
      if ma != 0 {
        blitter.blit_v(xx, x, 1, ma)
      }
      let ma = fdot6_small_scale(255 - a, mod64)
      if ma != 0 {
        blitter.blit_v(minus1(xx), x, 1, ma)
      }
      fx - fdot16_one / 2
    }
    Vertish => {
      let fx = fy + fdot16_one / 2
      let fx = if fx < 0 { 0 } else { fx }
      let xx = fx >> 16
      let a = i32_to_alpha(fx >> 8)
      blitter.blit_anti_h2(minus1(xx), x, fdot6_small_scale(255 - a, mod64), fdot6_small_scale(a, mod64))
      fx + slope - fdot16_one / 2
    }
  }
}

///|
fn hair_draw_line(kind : HairKind, blitter : &Blitter, x : Int, stop : Int, fy : Int, slope : Int) -> Int {
  match kind {
    HLine => {
      let count = stop - x
      if count == 0 {
        return fy
      }
      let fy = fy + fdot16_one / 2
      let fy = if fy < 0 { 0 } else { fy }
      let y = fy >> 16
      let a = i32_to_alpha(fy >> 8)
      if a != 0 {
        call_hline_blitter(x, Some(y), count, a, blitter)
      }
      let a = 255 - a
      if a != 0 {
        call_hline_blitter(x, if y >= 1 { Some(y - 1) } else { None }, count, a, blitter)
      }
      fy - fdot16_one / 2
    }
    Horish => {
      let mut x = x
      let mut fy = fy + fdot16_one / 2
      while true {
        fy = if fy < 0 { 0 } else { fy }
        let lower_y = fy >> 16
        let a = i32_to_alpha(fy >> 8)
        blitter.blit_anti_v2(x, minus1(lower_y), 255 - a, a)
        fy += slope
        x += 1
        if x >= stop {
          break
        }
      }
      fy - fdot16_one / 2
    }
    VLine => {
      let height = stop - x
      if height == 0 {
        return fy
      }
      let fx = fy + fdot16_one / 2
      let fx = if fx < 0 { 0 } else { fx }
      let xx = fx >> 16
      let a = i32_to_alpha(fx >> 8)
      if a != 0 {
        blitter.blit_v(xx, x, height, a)
      }
      let a = 255 - a
      if a != 0 {
        blitter.blit_v(minus1(xx), x, height, a)
      }
      fx - fdot16_one / 2
    }
    Vertish => {
      let mut y = x
      let mut fx = fy + fdot16_one / 2
      while true {
        fx = if fx < 0 { 0 } else { fx }
        let xx = fx >> 16
        let a = i32_to_alpha(fx >> 8)
        blitter.blit_anti_h2(minus1(xx), y, 255 - a, a)
        fx += slope
        y += 1
        if y >= stop {
          break
        }
      }
      fx - fdot16_one / 2
    }
  }
}

///|
/// A blitter that keeps to a rect (RectClipBlitter).
priv struct RectClipBlitter {
  blitter : &Blitter
  clip : ScreenIntRect
}

///|
fn compute_anti_width(runs : FixedArray[Int]) -> Int {
  let mut i = 0
  let mut width = 0
  while runs[i] != 0 {
    width += runs[i]
    i += runs[i]
  }
  width
}

///|
impl Blitter for RectClipBlitter with blit_anti_h(self, x, y, antialias, runs) {
  if !(y >= self.clip.y && y - self.clip.y < self.clip.height) || x >= self.clip.right() {
    return
  }
  let mut x0 = x
  let mut x1 = x + compute_anti_width(runs)
  if x1 <= self.clip.x {
    return
  }
  let mut aa = antialias
  let mut rs = runs
  if x0 < self.clip.x {
    let dx = self.clip.x - x0
    break_at(aa, 0, rs, 0, dx)
    aa = FixedArray::makei(aa.length() - dx, fn(i) { aa[i + dx] })
    rs = FixedArray::makei(rs.length() - dx, fn(i) { rs[i + dx] })
    x0 = self.clip.x
  }
  if x1 > self.clip.right() {
    x1 = self.clip.right()
    break_at(aa, 0, rs, 0, x1 - x0)
    rs[x1 - x0] = 0
  }
  self.blitter.blit_anti_h(x0, y, aa, rs)
}

///|
impl Blitter for RectClipBlitter with blit_v(self, x, y, height, alpha) {
  if !(x >= self.clip.x && x - self.clip.x < self.clip.width) {
    return
  }
  let mut y0 = y
  let mut y1 = y + height
  if y0 < self.clip.y {
    y0 = self.clip.y
  }
  if y1 > self.clip.bottom() {
    y1 = self.clip.bottom()
  }
  if y0 < y1 {
    self.blitter.blit_v(x, y0, y1 - y0, alpha)
  }
}

///|
impl Blitter for RectClipBlitter with blit_anti_h2(self, x, y, alpha0, alpha1) {
  let aa = FixedArray::make(2, 0)
  aa[0] = alpha0
  aa[1] = alpha1
  let runs = FixedArray::make(3, 0)
  runs[0] = 1
  runs[1] = 1
  self.blit_anti_h(x, y, aa, runs)
}

///|
impl Blitter for RectClipBlitter with blit_anti_v2(self, x, y, alpha0, alpha1) {
  let a0 = FixedArray::make(1, alpha0)
  let r0 = FixedArray::make(2, 0)
  r0[0] = 1
  self.blit_anti_h(x, y, a0, r0)
  let a1 = FixedArray::make(1, alpha1)
  let r1 = FixedArray::make(2, 0)
  r1[0] = 1
  self.blit_anti_h(x, y + 1, a1, r1)
}

///|
impl Blitter for RectClipBlitter with blit_h(_self, _x, _y, _w) {
  abort("RectClipBlitter: blit_h")
}

///|
impl Blitter for RectClipBlitter with blit_rect(_self, _r) {
  abort("RectClipBlitter: blit_rect")
}
