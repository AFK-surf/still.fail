// tiny-skia's path stroker (path/src/stroker.rs, after Skia's SkStroke.cpp): a path's outline at a width, its caps
// and joins, curves offset as quads to within the resolution. Rust's out-parameters are results here; its cap and join
// function pointers are the enums they are made from.

///|
pub(all) enum LineCap {
  Butt
  Round
  Square
} derive(Eq, Show, Debug)

///|
pub(all) enum LineJoin {
  Miter
  MiterClip
  Round
  Bevel
} derive(Eq, Show, Debug)

///|
pub(all) struct Stroke {
  mut width : Float
  mut miter_limit : Float
  mut line_cap : LineCap
  mut line_join : LineJoin
  mut dash : StrokeDash?
}

///|
pub fn Stroke::default() -> Stroke {
  { width: 1.0, miter_limit: 4.0, line_cap: Butt, line_join: Miter, dash: None }
}

///|
let quad_recursive_limit : Int = 3

///|
/// 3x the limits seen in practice
let recursive_limits : Array[Int] = [5 * 3, 26 * 3, 11 * 3, 11 * 3]

///|
priv enum ReductionType {
  RPoint
  RLine
  RQuad
  RDegenerate
  RDegenerate2
  RDegenerate3
} derive(Eq)

///|
fn ReductionType::rank(self : ReductionType) -> Int {
  match self {
    RPoint => 0
    RLine => 1
    RQuad => 2
    RDegenerate => 3
    RDegenerate2 => 4
    RDegenerate3 => 5
  }
}

///|
priv enum StrokeType {
  Outer
  Inner
} derive(Eq)

///|
priv enum ResultType {
  Split
  Degenerate
  QuadResult
} derive(Eq)

///|
priv enum IntersectRayType {
  CtrlPt
  ResultTypeRay
} derive(Eq)

///|
/// The path's outline at `stroke`'s width (Path::stroke), curves cut fine enough for `resolution_scale` pixels a unit.
pub fn Path::stroke(self : Path, stroke : Stroke, resolution_scale : Float) -> Path? {
  PathStroker::new().stroke(self, stroke, resolution_scale)
}

///|
priv struct QuadConstruct {
  quad : Array[Point]
  mut tangent_start : Point
  mut tangent_end : Point
  mut start_t : Float
  mut mid_t : Float
  mut end_t : Float
  mut start_set : Bool
  mut end_set : Bool
  mut opposite_tangents : Bool
}

///|
fn QuadConstruct::new() -> QuadConstruct {
  {
    quad: [Point::zero(), Point::zero(), Point::zero()],
    tangent_start: Point::zero(),
    tangent_end: Point::zero(),
    start_t: 0.0,
    mid_t: 0.0,
    end_t: 0.0,
    start_set: false,
    end_set: false,
    opposite_tangents: false,
  }
}

///|
fn QuadConstruct::init(self : QuadConstruct, start : Float, end : Float) -> Bool {
  self.start_t = start
  self.mid_t = norm_clamped(half(start + end))
  self.end_t = end
  self.start_set = false
  self.end_set = false
  self.start_t < self.mid_t && self.mid_t < self.end_t
}

///|
fn QuadConstruct::init_with_start(self : QuadConstruct, parent : QuadConstruct) -> Bool {
  if !self.init(parent.start_t, parent.mid_t) {
    return false
  }
  self.quad[0] = parent.quad[0]
  self.tangent_start = parent.tangent_start
  self.start_set = true
  true
}

///|
fn QuadConstruct::init_with_end(self : QuadConstruct, parent : QuadConstruct) -> Bool {
  if !self.init(parent.mid_t, parent.end_t) {
    return false
  }
  self.quad[2] = parent.quad[2]
  self.tangent_end = parent.tangent_end
  self.end_set = true
  true
}

///|
pub(all) struct PathStroker {
  priv mut radius : Float
  priv mut inv_miter_limit : Float
  priv mut res_scale : Float
  priv mut inv_res_scale : Float
  priv mut inv_res_scale_squared : Float
  priv mut first_normal : Point
  priv mut prev_normal : Point
  priv mut first_unit_normal : Point
  priv mut prev_unit_normal : Point
  priv mut first_pt : Point
  priv mut prev_pt : Point
  priv mut first_outer_pt : Point
  priv mut first_outer_pt_index_in_contour : Int
  priv mut segment_count : Int
  priv mut prev_is_line : Bool
  priv mut capper : LineCap
  priv mut joiner : LineJoin
  priv inner : PathBuilder
  priv mut outer : PathBuilder
  priv cusper : PathBuilder
  priv mut stroke_type : StrokeType
  priv mut recursion_depth : Int
  priv mut found_tangents : Bool
  priv mut join_completed : Bool
}

///|
pub fn PathStroker::new() -> PathStroker {
  {
    radius: 0.0,
    inv_miter_limit: 0.0,
    res_scale: 1.0,
    inv_res_scale: 1.0,
    inv_res_scale_squared: 1.0,
    first_normal: Point::zero(),
    prev_normal: Point::zero(),
    first_unit_normal: Point::zero(),
    prev_unit_normal: Point::zero(),
    first_pt: Point::zero(),
    prev_pt: Point::zero(),
    first_outer_pt: Point::zero(),
    first_outer_pt_index_in_contour: 0,
    segment_count: -1,
    prev_is_line: false,
    capper: Butt,
    joiner: Miter,
    inner: PathBuilder::new(),
    outer: PathBuilder::new(),
    cusper: PathBuilder::new(),
    stroke_type: Outer,
    recursion_depth: 0,
    found_tangents: false,
    join_completed: false,
  }
}

///|
/// The scale a path is drawn at under `ts` (its larger axis), 1 when there is none.
pub fn PathStroker::compute_resolution_scale(ts : Transform) -> Float {
  let sx = Point::from_xy(ts.sx, ts.kx).length()
  let sy = Point::from_xy(ts.ky, ts.sy).length()
  if fin(sx) && fin(sy) {
    let scale = fmax(sx, sy)
    if scale > 0.0 {
      return scale
    }
  }
  1.0
}

///|
pub fn PathStroker::stroke(self : PathStroker, path : Path, stroke : Stroke, resolution_scale : Float) -> Path? {
  if !(stroke.width > 0.0 && fin(stroke.width)) {
    return None
  }
  self.stroke_inner(path, stroke.width, stroke.miter_limit, stroke.line_cap, stroke.line_join, resolution_scale)
}

///|
fn PathStroker::stroke_inner(
  self : PathStroker,
  path : Path,
  width : Float,
  miter_limit : Float,
  line_cap : LineCap,
  line_join : LineJoin,
  res_scale : Float,
) -> Path? {
  let mut line_join = line_join
  let mut inv_miter_limit : Float = 0.0
  if line_join == Miter {
    if miter_limit <= 1.0 {
      line_join = Bevel
    } else {
      inv_miter_limit = invert(miter_limit)
    }
  }
  if line_join == MiterClip {
    inv_miter_limit = invert(miter_limit)
  }
  self.res_scale = res_scale
  self.inv_res_scale = invert(res_scale * 4.0)
  self.inv_res_scale_squared = sqr(self.inv_res_scale)
  self.radius = half(width)
  self.inv_miter_limit = inv_miter_limit
  self.first_normal = Point::zero()
  self.prev_normal = Point::zero()
  self.first_unit_normal = Point::zero()
  self.prev_unit_normal = Point::zero()
  self.first_pt = Point::zero()
  self.prev_pt = Point::zero()
  self.first_outer_pt = Point::zero()
  self.first_outer_pt_index_in_contour = 0
  self.segment_count = -1
  self.prev_is_line = false
  self.capper = line_cap
  self.joiner = line_join
  self.inner.clear()
  self.outer.clear()
  self.cusper.clear()
  self.stroke_type = Outer
  self.recursion_depth = 0
  self.found_tangents = false
  self.join_completed = false
  let mut last_segment_is_line = false
  let iter = path.segments()
  iter.set_auto_close(true)
  while iter.next() is Some(segment) {
    match segment {
      MoveTo(p) => self.move_to(p)
      LineTo(p) => {
        self.line_to(p, Some(iter))
        last_segment_is_line = true
      }
      QuadTo(p1, p2) => {
        self.quad_to(p1, p2)
        last_segment_is_line = false
      }
      CubicTo(p1, p2, p3) => {
        self.cubic_to(p1, p2, p3)
        last_segment_is_line = false
      }
      Close => {
        if line_cap != Butt {
          if self.has_only_move_to() {
            self.line_to(self.first_pt, None)
            last_segment_is_line = true
            continue
          }
          if self.is_current_contour_empty() {
            last_segment_is_line = true
            continue
          }
        }
        self.close(last_segment_is_line)
      }
    }
  }
  self.finish(last_segment_is_line)
}

///|
fn PathStroker::move_to(self : PathStroker, p : Point) -> Unit {
  if self.segment_count > 0 {
    self.finish_contour(false, false)
  }
  self.segment_count = 0
  self.first_pt = p
  self.prev_pt = p
  self.join_completed = false
}

///|
fn PathStroker::line_to(self : PathStroker, p : Point, iter : PathSegmentsIter?) -> Unit {
  let teeny_line = self.prev_pt.equals_within_tolerance(p, scalar_nearly_zero * self.inv_res_scale)
  if self.capper == Butt && teeny_line {
    return
  }
  if teeny_line &&
    (
      self.join_completed ||
      (match iter {
        Some(i) => i.has_valid_tangent()
        None => false
      })
    ) {
    return
  }
  match self.pre_join_to(p, true) {
    Some((normal, unit_normal)) => {
      self.outer.line_to(p.x + normal.x, p.y + normal.y)
      self.inner.line_to(p.x - normal.x, p.y - normal.y)
      self.post_join_to(p, normal, unit_normal)
    }
    None => ()
  }
}

///|
fn PathStroker::quad_to(self : PathStroker, p1 : Point, p2 : Point) -> Unit {
  let quad = [self.prev_pt, p1, p2]
  let (reduction, reduction_type) = check_quad_linear(quad)
  if reduction_type == RPoint || reduction_type == RLine {
    self.line_to(p2, None)
    return
  }
  if reduction_type == RDegenerate {
    self.line_to(reduction, None)
    let save_joiner = self.joiner
    self.joiner = Round
    self.line_to(p2, None)
    self.joiner = save_joiner
    return
  }
  let (normal_ab, unit_ab) = match self.pre_join_to(p1, false) {
    Some(n) => n
    None => {
      self.line_to(p2, None)
      return
    }
  }
  let quad_points = QuadConstruct::new()
  self.init_quad(Outer, 0.0, 1.0, quad_points)
  ignore(self.quad_stroke(quad, quad_points))
  self.init_quad(Inner, 0.0, 1.0, quad_points)
  ignore(self.quad_stroke(quad, quad_points))
  let (normal_bc, unit_bc) = match set_normal_unit_normal(quad[1], quad[2], self.res_scale, self.radius) {
    Some(n) => n
    None => (normal_ab, unit_ab)
  }
  self.post_join_to(p2, normal_bc, unit_bc)
}

///|
fn PathStroker::cubic_to(self : PathStroker, pt1 : Point, pt2 : Point, pt3 : Point) -> Unit {
  let cubic = [self.prev_pt, pt1, pt2, pt3]
  let reduction = [Point::zero(), Point::zero(), Point::zero()]
  let (reduction_type, tangent_pt) = check_cubic_linear(cubic, reduction)
  if reduction_type == RPoint || reduction_type == RLine {
    self.line_to(pt3, None)
    return
  }
  if RDegenerate.rank() <= reduction_type.rank() && RDegenerate3.rank() >= reduction_type.rank() {
    self.line_to(reduction[0], None)
    let save_joiner = self.joiner
    self.joiner = Round
    if RDegenerate2.rank() <= reduction_type.rank() {
      self.line_to(reduction[1], None)
    }
    if reduction_type == RDegenerate3 {
      self.line_to(reduction[2], None)
    }
    self.line_to(pt3, None)
    self.joiner = save_joiner
    return
  }
  let (normal_ab, unit_ab) = match self.pre_join_to(tangent_pt, false) {
    Some(n) => n
    None => {
      self.line_to(pt3, None)
      return
    }
  }
  let t_values = new_t_values()
  let n = find_cubic_inflections(cubic, t_values)
  let mut last_t : Float = 0.0
  for index in 0..=n {
    let next_t = if index < n { t_values[index] } else { 1.0 }
    let quad_points = QuadConstruct::new()
    self.init_quad(Outer, last_t, next_t, quad_points)
    ignore(self.cubic_stroke(cubic, quad_points))
    self.init_quad(Inner, last_t, next_t, quad_points)
    ignore(self.cubic_stroke(cubic, quad_points))
    last_t = next_t
  }
  match find_cubic_cusp(cubic) {
    Some(cusp) => {
      let cusp_loc = eval_cubic_pos_at(cubic, cusp)
      self.cusper.push_circle(cusp_loc.x, cusp_loc.y, self.radius)
    }
    None => ()
  }
  let (normal_cd, unit_cd) = self.set_cubic_end_normal(cubic, normal_ab, unit_ab)
  self.post_join_to(pt3, normal_cd, unit_cd)
}

///|
fn PathStroker::cubic_stroke(self : PathStroker, cubic : Array[Point], quad_points : QuadConstruct) -> Bool {
  if !self.found_tangents {
    let result_type = self.tangents_meet(cubic, quad_points)
    if result_type != QuadResult {
      let ok = points_within_dist(quad_points.quad[0], quad_points.quad[2], self.inv_res_scale)
      if (result_type == Degenerate || ok) && self.cubic_mid_on_line(cubic, quad_points) {
        self.add_degenerate_line(quad_points)
        return true
      }
    } else {
      self.found_tangents = true
    }
  }
  if self.found_tangents {
    let result_type = self.compare_quad_cubic(cubic, quad_points)
    if result_type == QuadResult {
      let stroke = quad_points.quad
      if self.stroke_type == Outer {
        self.outer.quad_to(stroke[1].x, stroke[1].y, stroke[2].x, stroke[2].y)
      } else {
        self.inner.quad_to(stroke[1].x, stroke[1].y, stroke[2].x, stroke[2].y)
      }
      return true
    }
    if result_type == Degenerate {
      if !quad_points.opposite_tangents {
        self.add_degenerate_line(quad_points)
        return true
      }
    }
  }
  if !fin(quad_points.quad[2].x) || !fin(quad_points.quad[2].x) {
    return false
  }
  self.recursion_depth += 1
  if self.recursion_depth > recursive_limits[if self.found_tangents { 1 } else { 0 }] {
    return false
  }
  let half = QuadConstruct::new()
  if !half.init_with_start(quad_points) {
    self.add_degenerate_line(quad_points)
    self.recursion_depth -= 1
    return true
  }
  if !self.cubic_stroke(cubic, half) {
    return false
  }
  if !half.init_with_end(quad_points) {
    self.add_degenerate_line(quad_points)
    self.recursion_depth -= 1
    return true
  }
  if !self.cubic_stroke(cubic, half) {
    return false
  }
  self.recursion_depth -= 1
  true
}

///|
fn PathStroker::cubic_mid_on_line(self : PathStroker, cubic : Array[Point], quad_points : QuadConstruct) -> Bool {
  let (_, stroke_mid, _) = self.cubic_perp_ray(cubic, quad_points.mid_t)
  let dist = pt_to_line(stroke_mid, quad_points.quad[0], quad_points.quad[2])
  dist < self.inv_res_scale_squared
}

///|
/// The point at t, the point a radius off it, and the tangent point there (cubic_perp_ray's out-parameters).
fn PathStroker::cubic_perp_ray(self : PathStroker, cubic : Array[Point], t : Float) -> (Point, Point, Point) {
  let t_pt = eval_cubic_pos_at(cubic, t)
  let mut dxy = eval_cubic_tangent_at(cubic, t)
  let chopped = Array::make(7, Point::zero())
  if dxy.x == 0.0 && dxy.y == 0.0 {
    let mut c_points = cubic
    if is_nearly_zero(t) {
      dxy = cubic[2] - cubic[0]
    } else if is_nearly_zero(1.0 - t) {
      dxy = cubic[3] - cubic[1]
    } else {
      chop_cubic_at2(cubic, 0, t, chopped, 0)
      dxy = chopped[3] - chopped[2]
      if dxy.x == 0.0 && dxy.y == 0.0 {
        dxy = chopped[3] - chopped[1]
        c_points = chopped
      }
    }
    if dxy.x == 0.0 && dxy.y == 0.0 {
      dxy = c_points[3] - c_points[0]
    }
  }
  let (on_pt, tangent) = self.set_ray_points(t_pt, dxy)
  (t_pt, on_pt, tangent)
}

///|
fn PathStroker::set_cubic_end_normal(
  self : PathStroker,
  cubic : Array[Point],
  normal_ab : Point,
  unit_normal_ab : Point,
) -> (Point, Point) {
  let mut ab = cubic[1] - cubic[0]
  let mut cd = cubic[3] - cubic[2]
  let mut degenerate_ab = degenerate_vector(ab)
  let mut degenerate_cb = degenerate_vector(cd)
  if degenerate_ab && degenerate_cb {
    return (normal_ab, unit_normal_ab)
  }
  if degenerate_ab {
    ab = cubic[2] - cubic[0]
    degenerate_ab = degenerate_vector(ab)
  }
  if degenerate_cb {
    cd = cubic[3] - cubic[1]
    degenerate_cb = degenerate_vector(cd)
  }
  if degenerate_ab || degenerate_cb {
    return (normal_ab, unit_normal_ab)
  }
  match set_normal_unit_normal2(cd, self.radius) {
    Some(n) => n
    None => (Point::zero(), Point::zero())
  }
}

///|
fn PathStroker::compare_quad_cubic(self : PathStroker, cubic : Array[Point], quad_points : QuadConstruct) -> ResultType {
  self.cubic_quad_ends(cubic, quad_points)
  let result_type = self.intersect_ray(CtrlPt, quad_points)
  if result_type != QuadResult {
    return result_type
  }
  let (ray1, ray0, _) = self.cubic_perp_ray(cubic, quad_points.mid_t)
  self.stroke_close_enough(quad_points.quad.copy(), ray0, ray1, quad_points)
}

///|
fn PathStroker::cubic_quad_ends(self : PathStroker, cubic : Array[Point], quad_points : QuadConstruct) -> Unit {
  if !quad_points.start_set {
    let (_, on, tangent) = self.cubic_perp_ray(cubic, quad_points.start_t)
    quad_points.quad[0] = on
    quad_points.tangent_start = tangent
    quad_points.start_set = true
  }
  if !quad_points.end_set {
    let (_, on, tangent) = self.cubic_perp_ray(cubic, quad_points.end_t)
    quad_points.quad[2] = on
    quad_points.tangent_end = tangent
    quad_points.end_set = true
  }
}

///|
fn PathStroker::close(self : PathStroker, is_line : Bool) -> Unit {
  self.finish_contour(true, is_line)
}

///|
fn PathStroker::finish_contour(self : PathStroker, close : Bool, curr_is_line : Bool) -> Unit {
  if self.segment_count > 0 {
    if close {
      self.join(
        self.prev_unit_normal,
        self.prev_pt,
        self.first_unit_normal,
        self.prev_is_line,
        curr_is_line,
      )
      self.outer.close()
      let pt = self.inner.last_point().unwrap_or(Point::zero())
      self.outer.move_to(pt.x, pt.y)
      self.outer.reverse_path_to(self.inner)
      self.outer.close()
    } else {
      let pt = self.inner.last_point().unwrap_or(Point::zero())
      cap(self.capper, self.prev_pt, self.prev_normal, pt, curr_is_line, self.outer)
      self.outer.reverse_path_to(self.inner)
      cap(self.capper, self.first_pt, -self.first_normal, self.first_outer_pt, self.prev_is_line, self.outer)
      self.outer.close()
    }
    if !self.cusper.is_empty() {
      self.outer.push_path_builder(self.cusper)
      self.cusper.clear()
    }
  }
  self.inner.clear()
  self.segment_count = -1
  self.first_outer_pt_index_in_contour = self.outer.points.length()
}

///|
/// The normal and unit normal toward `p` (pre_join_to's out-parameters), the join to the last segment made; None
/// when a butt-capped stroke has no normal there.
fn PathStroker::pre_join_to(self : PathStroker, p : Point, curr_is_line : Bool) -> (Point, Point)? {
  let prev_x = self.prev_pt.x
  let prev_y = self.prev_pt.y
  let (normal, unit_normal) = match set_normal_unit_normal(self.prev_pt, p, self.res_scale, self.radius) {
    Some(n) => n
    None => {
      if self.capper == Butt {
        return None
      }
      (Point::from_xy(self.radius, 0.0), Point::from_xy(1.0, 0.0))
    }
  }
  if self.segment_count == 0 {
    self.first_normal = normal
    self.first_unit_normal = unit_normal
    self.first_outer_pt = Point::from_xy(prev_x + normal.x, prev_y + normal.y)
    self.outer.move_to(self.first_outer_pt.x, self.first_outer_pt.y)
    self.inner.move_to(prev_x - normal.x, prev_y - normal.y)
  } else {
    self.join(self.prev_unit_normal, self.prev_pt, unit_normal, self.prev_is_line, curr_is_line)
  }
  self.prev_is_line = curr_is_line
  Some((normal, unit_normal))
}

///|
fn PathStroker::post_join_to(self : PathStroker, p : Point, normal : Point, unit_normal : Point) -> Unit {
  self.join_completed = true
  self.prev_pt = p
  self.prev_unit_normal = unit_normal
  self.prev_normal = normal
  self.segment_count += 1
}

///|
fn PathStroker::init_quad(
  self : PathStroker,
  stroke_type : StrokeType,
  start : Float,
  end : Float,
  quad_points : QuadConstruct,
) -> Unit {
  self.stroke_type = stroke_type
  self.found_tangents = false
  ignore(quad_points.init(start, end))
}

///|
fn PathStroker::quad_stroke(self : PathStroker, quad : Array[Point], quad_points : QuadConstruct) -> Bool {
  let result_type = self.compare_quad_quad(quad, quad_points)
  if result_type == QuadResult {
    let path = if self.stroke_type == Outer { self.outer } else { self.inner }
    path.quad_to(quad_points.quad[1].x, quad_points.quad[1].y, quad_points.quad[2].x, quad_points.quad[2].y)
    return true
  }
  if result_type == Degenerate {
    self.add_degenerate_line(quad_points)
    return true
  }
  self.recursion_depth += 1
  if self.recursion_depth > recursive_limits[quad_recursive_limit] {
    return false
  }
  let half = QuadConstruct::new()
  ignore(half.init_with_start(quad_points))
  if !self.quad_stroke(quad, half) {
    return false
  }
  ignore(half.init_with_end(quad_points))
  if !self.quad_stroke(quad, half) {
    return false
  }
  self.recursion_depth -= 1
  true
}

///|
fn PathStroker::compare_quad_quad(self : PathStroker, quad : Array[Point], quad_points : QuadConstruct) -> ResultType {
  if !quad_points.start_set {
    let (_, on, tangent) = self.quad_perp_ray(quad, quad_points.start_t)
    quad_points.quad[0] = on
    quad_points.tangent_start = tangent
    quad_points.start_set = true
  }
  if !quad_points.end_set {
    let (_, on, tangent) = self.quad_perp_ray(quad, quad_points.end_t)
    quad_points.quad[2] = on
    quad_points.tangent_end = tangent
    quad_points.end_set = true
  }
  let result_type = self.intersect_ray(CtrlPt, quad_points)
  if result_type != QuadResult {
    return result_type
  }
  let (ray1, ray0, _) = self.quad_perp_ray(quad, quad_points.mid_t)
  self.stroke_close_enough(quad_points.quad.copy(), ray0, ray1, quad_points)
}

///|
/// The point a radius off `tp` across `dxy`, and the tangent point past it (set_ray_points' out-parameters).
fn PathStroker::set_ray_points(self : PathStroker, tp : Point, dxy : Point) -> (Point, Point) {
  let dxy = match dxy.with_length(self.radius) {
    Some(d) => d
    None => Point::from_xy(self.radius, 0.0)
  }
  // go opposite ways for outer, inner
  let axis_flip : Float = if self.stroke_type == Outer { 1.0 } else { -1.0 }
  let on_p = Point::from_xy(tp.x + axis_flip * dxy.y, tp.y - axis_flip * dxy.x)
  (on_p, Point::from_xy(on_p.x + dxy.x, on_p.y + dxy.y))
}

///|
fn PathStroker::quad_perp_ray(self : PathStroker, quad : Array[Point], t : Float) -> (Point, Point, Point) {
  let tp = eval_quad_at(quad, t)
  let mut dxy = eval_quad_tangent_at(quad, t)
  if dxy.is_zero() {
    dxy = quad[2] - quad[0]
  }
  let (on_p, tangent) = self.set_ray_points(tp, dxy)
  (tp, on_p, tangent)
}

///|
fn PathStroker::add_degenerate_line(self : PathStroker, quad_points : QuadConstruct) -> Unit {
  if self.stroke_type == Outer {
    self.outer.line_to(quad_points.quad[2].x, quad_points.quad[2].y)
  } else {
    self.inner.line_to(quad_points.quad[2].x, quad_points.quad[2].y)
  }
}

///|
fn PathStroker::stroke_close_enough(
  self : PathStroker,
  stroke : Array[Point],
  ray0 : Point,
  ray1 : Point,
  quad_points : QuadConstruct,
) -> ResultType {
  let stroke_mid = eval_quad_at(stroke, norm_clamped(0.5))
  if points_within_dist(ray0, stroke_mid, self.inv_res_scale) {
    if sharp_angle(quad_points.quad) {
      return Split
    }
    return QuadResult
  }
  if !pt_in_quad_bounds(stroke, ray0, self.inv_res_scale) {
    return Split
  }
  let roots = new_t_values()
  let n = intersect_quad_ray(ray0, ray1, stroke, roots)
  if n != 1 {
    return Split
  }
  let quad_pt = eval_quad_at(stroke, roots[0])
  let error = self.inv_res_scale * (1.0 - (roots[0] - 0.5).abs() * 2.0)
  if points_within_dist(ray0, quad_pt, error) {
    if sharp_angle(quad_points.quad) {
      return Split
    }
    return QuadResult
  }
  Split
}

///|
fn PathStroker::intersect_ray(self : PathStroker, kind : IntersectRayType, quad_points : QuadConstruct) -> ResultType {
  let start = quad_points.quad[0]
  let end = quad_points.quad[2]
  let a_len = quad_points.tangent_start - start
  let b_len = quad_points.tangent_end - end
  let denom = a_len.cross(b_len)
  if denom == 0.0 || !fin(denom) {
    quad_points.opposite_tangents = a_len.dot(b_len) < 0.0
    return Degenerate
  }
  quad_points.opposite_tangents = false
  let ab0 = start - end
  let mut numer_a = b_len.cross(ab0)
  let numer_b = a_len.cross(ab0)
  if (numer_a >= 0.0) == (numer_b >= 0.0) {
    let dist1 = pt_to_line(start, end, quad_points.tangent_end)
    let dist2 = pt_to_line(end, start, quad_points.tangent_start)
    if fmax(dist1, dist2) <= self.inv_res_scale_squared {
      return Degenerate
    }
    return Split
  }
  numer_a = numer_a / denom
  let valid_divide = numer_a > numer_a - 1.0
  if valid_divide {
    if kind == CtrlPt {
      quad_points.quad[1] = Point::from_xy(
        start.x * (1.0 - numer_a) + quad_points.tangent_start.x * numer_a,
        start.y * (1.0 - numer_a) + quad_points.tangent_start.y * numer_a,
      )
    }
    return QuadResult
  }
  quad_points.opposite_tangents = a_len.dot(b_len) < 0.0
  Degenerate
}

///|
fn PathStroker::tangents_meet(self : PathStroker, cubic : Array[Point], quad_points : QuadConstruct) -> ResultType {
  self.cubic_quad_ends(cubic, quad_points)
  self.intersect_ray(ResultTypeRay, quad_points)
}

///|
fn PathStroker::finish(self : PathStroker, is_line : Bool) -> Path? {
  self.finish_contour(false, is_line)
  let buf = self.outer
  self.outer = PathBuilder::new()
  buf.finish()
}

///|
fn PathStroker::has_only_move_to(self : PathStroker) -> Bool {
  self.segment_count == 0
}

///|
fn PathStroker::is_current_contour_empty(self : PathStroker) -> Bool {
  self.inner.is_zero_length_since_point(0) &&
  self.outer.is_zero_length_since_point(self.first_outer_pt_index_in_contour)
}

///|
/// The current joiner between the segments before and after `pivot` (the join procs, on the stroker's builders,
/// which a join may swap).
fn PathStroker::join(
  self : PathStroker,
  before_unit_normal : Point,
  pivot : Point,
  after_unit_normal : Point,
  prev_is_line : Bool,
  curr_is_line : Bool,
) -> Unit {
  match self.joiner {
    Bevel => bevel_joiner(before_unit_normal, pivot, after_unit_normal, self.radius, self.inner, self.outer)
    Round => round_joiner(before_unit_normal, pivot, after_unit_normal, self.radius, self.inner, self.outer)
    Miter =>
      miter_joiner_inner(
        before_unit_normal,
        pivot,
        after_unit_normal,
        self.radius,
        self.inv_miter_limit,
        false,
        prev_is_line,
        curr_is_line,
        self.inner,
        self.outer,
      )
    MiterClip =>
      miter_joiner_inner(
        before_unit_normal,
        pivot,
        after_unit_normal,
        self.radius,
        self.inv_miter_limit,
        true,
        prev_is_line,
        curr_is_line,
        self.inner,
        self.outer,
      )
  }
}

///|
/// A cap at `pivot` (`other_path`: whether the inner path is there, a line's: Rust's Option of it).
fn cap(kind : LineCap, pivot : Point, normal : Point, stop : Point, other_path : Bool, path : PathBuilder) -> Unit {
  match kind {
    Butt => path.line_to(stop.x, stop.y)
    Round => {
      let parallel = normal.rotated_cw()
      let projected_center = pivot + parallel
      path.conic_points_to(projected_center + normal, projected_center, scalar_root_2_over_2)
      path.conic_points_to(projected_center - normal, stop, scalar_root_2_over_2)
    }
    Square => {
      let parallel = normal.rotated_cw()
      if other_path {
        path.set_last_point(
          Point::from_xy(pivot.x + normal.x + parallel.x, pivot.y + normal.y + parallel.y),
        )
        path.line_to(pivot.x - normal.x + parallel.x, pivot.y - normal.y + parallel.y)
      } else {
        path.line_to(pivot.x + normal.x + parallel.x, pivot.y + normal.y + parallel.y)
        path.line_to(pivot.x - normal.x + parallel.x, pivot.y - normal.y + parallel.y)
        path.line_to(stop.x, stop.y)
      }
    }
  }
}

///|
fn is_clockwise(before : Point, after : Point) -> Bool {
  before.x * after.y > before.y * after.x
}

///|
priv enum AngleType {
  Nearly180
  Sharp
  Shallow
  NearlyLine
} derive(Eq)

///|
fn dot_to_angle_type(dot : Float) -> AngleType {
  if dot >= 0.0 {
    if is_nearly_zero(1.0 - dot) {
      NearlyLine
    } else {
      Shallow
    }
  } else if is_nearly_zero(1.0 + dot) {
    Nearly180
  } else {
    Sharp
  }
}

///|
fn handle_inner_join(pivot : Point, after : Point, inner : PathBuilder) -> Unit {
  inner.line_to(pivot.x, pivot.y)
  inner.line_to(pivot.x - after.x, pivot.y - after.y)
}

///|
fn bevel_joiner(
  before_unit_normal : Point,
  pivot : Point,
  after_unit_normal : Point,
  radius : Float,
  inner : PathBuilder,
  outer : PathBuilder,
) -> Unit {
  let mut inner = inner
  let mut outer = outer
  let mut after = after_unit_normal.scaled(radius)
  if !is_clockwise(before_unit_normal, after_unit_normal) {
    let t = inner
    inner = outer
    outer = t
    after = -after
  }
  outer.line_to(pivot.x + after.x, pivot.y + after.y)
  handle_inner_join(pivot, after, inner)
}

///|
fn round_joiner(
  before_unit_normal : Point,
  pivot : Point,
  after_unit_normal : Point,
  radius : Float,
  inner : PathBuilder,
  outer : PathBuilder,
) -> Unit {
  let dot_prod = before_unit_normal.dot(after_unit_normal)
  if dot_to_angle_type(dot_prod) == NearlyLine {
    return
  }
  let mut inner = inner
  let mut outer = outer
  let mut before = before_unit_normal
  let mut after = after_unit_normal
  let mut dir = CW
  if !is_clockwise(before, after) {
    let t = inner
    inner = outer
    outer = t
    before = -before
    after = -after
    dir = CCW
  }
  let ts = Transform::from_row(radius, 0.0, 0.0, radius, pivot.x, pivot.y)
  match Conic::build_unit_arc(before, after, dir, ts) {
    Some(conics) => {
      for conic in conics {
        outer.conic_points_to(conic.points[1], conic.points[2], conic.weight)
      }
      after = after.scaled(radius)
      handle_inner_join(pivot, after, inner)
    }
    None => ()
  }
}

///|
fn miter_joiner_inner(
  before_unit_normal : Point,
  pivot : Point,
  after_unit_normal : Point,
  radius : Float,
  inv_miter_limit : Float,
  miter_clip : Bool,
  prev_is_line : Bool,
  curr_is_line : Bool,
  inner : PathBuilder,
  outer : PathBuilder,
) -> Unit {
  let mut inner = inner
  let mut outer = outer
  let mut curr_is_line = curr_is_line
  let do_blunt_or_clipped = fn(before : Point, mid : Point, after : Point) {
    let after = after.scaled(radius)
    if miter_clip {
      let mid = mid.normalized().unwrap_or(Point::zero())
      let cos_beta = before.dot(mid)
      let sin_beta = before.cross(mid)
      let x : Float = if sin_beta.abs() <= scalar_nearly_zero {
        1.0 / inv_miter_limit
      } else {
        (1.0 / inv_miter_limit - cos_beta) / sin_beta
      }
      let before = before.scaled(radius)
      let before_tangent = before.rotated_cw()
      let after_tangent = after.rotated_ccw()
      let c1 = pivot + before + before_tangent.scaled(x)
      let c2 = pivot + after + after_tangent.scaled(x)
      if prev_is_line {
        outer.set_last_point(c1)
      } else {
        outer.line_to(c1.x, c1.y)
      }
      outer.line_to(c2.x, c2.y)
    }
    if !curr_is_line {
      outer.line_to(pivot.x + after.x, pivot.y + after.y)
    }
    handle_inner_join(pivot, after, inner)
  }
  let do_miter = fn(mid : Point, after : Point) {
    let after = after.scaled(radius)
    if prev_is_line {
      outer.set_last_point(Point::from_xy(pivot.x + mid.x, pivot.y + mid.y))
    } else {
      outer.line_to(pivot.x + mid.x, pivot.y + mid.y)
    }
    if !curr_is_line {
      outer.line_to(pivot.x + after.x, pivot.y + after.y)
    }
    handle_inner_join(pivot, after, inner)
  }
  let dot_prod = before_unit_normal.dot(after_unit_normal)
  let angle_type = dot_to_angle_type(dot_prod)
  let mut before = before_unit_normal
  let mut after = after_unit_normal
  if angle_type == NearlyLine {
    return
  }
  if angle_type == Nearly180 {
    curr_is_line = false
    do_blunt_or_clipped(before, (after - before).scaled(radius / 2.0), after)
    return
  }
  let ccw = !is_clockwise(before, after)
  if ccw {
    let t = inner
    inner = outer
    outer = t
    before = -before
    after = -after
  }
  if dot_prod == 0.0 && inv_miter_limit <= scalar_root_2_over_2 {
    do_miter((before + after).scaled(radius), after)
    return
  }
  let mut mid = if angle_type == Sharp {
    let m = Point::from_xy(after.y - before.y, before.x - after.x)
    if ccw {
      -m
    } else {
      m
    }
  } else {
    Point::from_xy(before.x + after.x, before.y + after.y)
  }
  let sin_half_angle = half(1.0 + dot_prod).sqrt()
  if sin_half_angle < inv_miter_limit {
    curr_is_line = false
    do_blunt_or_clipped(before, mid, after)
    return
  }
  mid = mid.with_length(radius / sin_half_angle).unwrap_or(Point::zero())
  do_miter(mid, after)
}

///|
/// The normal at `radius` and the unit normal of before→after (scaled first by `scale`), None where it has none.
fn set_normal_unit_normal(before : Point, after : Point, scale : Float, radius : Float) -> (Point, Point)? {
  match set_length_from((after.x - before.x) * scale, (after.y - before.y) * scale, 1.0) {
    Some(u) => {
      let unit_normal = u.rotated_ccw()
      Some((unit_normal.scaled(radius), unit_normal))
    }
    None => None
  }
}

///|
fn set_normal_unit_normal2(vec : Point, radius : Float) -> (Point, Point)? {
  match set_length_from(vec.x, vec.y, 1.0) {
    Some(u) => {
      let unit_normal = u.rotated_ccw()
      Some((unit_normal.scaled(radius), unit_normal))
    }
    None => None
  }
}

///|
fn check_quad_linear(quad : Array[Point]) -> (Point, ReductionType) {
  let degenerate_ab = degenerate_vector(quad[1] - quad[0])
  let degenerate_bc = degenerate_vector(quad[2] - quad[1])
  if degenerate_ab && degenerate_bc {
    return (Point::zero(), RPoint)
  }
  if degenerate_ab || degenerate_bc {
    return (Point::zero(), RLine)
  }
  if !quad_in_line(quad) {
    return (Point::zero(), RQuad)
  }
  let t = find_quad_max_curvature(quad)
  if t == 0.0 || t == 1.0 {
    return (Point::zero(), RLine)
  }
  (eval_quad_at(quad, t), RDegenerate)
}

///|
fn degenerate_vector(v : Point) -> Bool {
  !v.can_normalize()
}

///|
fn quad_in_line(quad : Array[Point]) -> Bool {
  let mut pt_max : Float = -1.0
  let mut outer1 = 0
  let mut outer2 = 0
  for index in 0..<2 {
    for inner in (index + 1)..<3 {
      let test_diff = quad[inner] - quad[index]
      let test_max = fmax(test_diff.x.abs(), test_diff.y.abs())
      if pt_max < test_max {
        outer1 = index
        outer2 = inner
        pt_max = test_max
      }
    }
  }
  let mid = outer1 ^ outer2 ^ 3
  let line_slop = pt_max * pt_max * 0.000005
  pt_to_line(quad[mid], quad[outer1], quad[outer2]) <= line_slop
}

///|
fn pt_to_line(pt : Point, line_start : Point, line_end : Point) -> Float {
  let dxy = line_end - line_start
  let ab0 = pt - line_start
  let numer = dxy.dot(ab0)
  let denom = dxy.dot(dxy)
  let t = numer / denom
  if t >= 0.0 && t <= 1.0 {
    let hit = Point::from_xy(line_start.x * (1.0 - t) + line_end.x * t, line_start.y * (1.0 - t) + line_end.y * t)
    hit.distance_to_sqd(pt)
  } else {
    pt.distance_to_sqd(line_start)
  }
}

///|
fn intersect_quad_ray(line0 : Point, line1 : Point, quad : Array[Point], roots : Array[Float]) -> Int {
  let vec = line1 - line0
  let r = Array::make(3, (0.0 : Float))
  for n in 0..<3 {
    r[n] = (quad[n].y - line0.y) * vec.x - (quad[n].x - line0.x) * vec.y
  }
  let mut a = r[2]
  let mut b = r[1]
  let c = r[0]
  a = a + (c - 2.0 * b)
  b = b - c
  find_unit_quad_roots(a, 2.0 * b, c, roots)
}

///|
fn points_within_dist(near_pt : Point, far_pt : Point, limit : Float) -> Bool {
  near_pt.distance_to_sqd(far_pt) <= limit * limit
}

///|
fn sharp_angle(quad : Array[Point]) -> Bool {
  let mut smaller = quad[1] - quad[0]
  let mut larger = quad[1] - quad[2]
  let smaller_len = smaller.length_sqd()
  let mut larger_len = larger.length_sqd()
  if smaller_len > larger_len {
    let t = smaller
    smaller = larger
    larger = t
    larger_len = smaller_len
  }
  match smaller.with_length(larger_len) {
    Some(s) => s.dot(larger) > 0.0
    None => false
  }
}

///|
fn pt_in_quad_bounds(quad : Array[Point], pt : Point, inv_res_scale : Float) -> Bool {
  let x_min = fmin(fmin(quad[0].x, quad[1].x), quad[2].x)
  if pt.x + inv_res_scale < x_min {
    return false
  }
  let x_max = fmax(fmax(quad[0].x, quad[1].x), quad[2].x)
  if pt.x - inv_res_scale > x_max {
    return false
  }
  let y_min = fmin(fmin(quad[0].y, quad[1].y), quad[2].y)
  if pt.y + inv_res_scale < y_min {
    return false
  }
  let y_max = fmax(fmax(quad[0].y, quad[1].y), quad[2].y)
  if pt.y - inv_res_scale > y_max {
    return false
  }
  true
}

///|
/// The cubic's kind, and its tangent point (check_cubic_linear's out-parameter: set for a quad only; zero else).
fn check_cubic_linear(cubic : Array[Point], reduction : Array[Point]) -> (ReductionType, Point) {
  let degenerate_ab = degenerate_vector(cubic[1] - cubic[0])
  let degenerate_bc = degenerate_vector(cubic[2] - cubic[1])
  let degenerate_cd = degenerate_vector(cubic[3] - cubic[2])
  if degenerate_ab && degenerate_bc && degenerate_cd {
    return (RPoint, Point::zero())
  }
  let b2i = fn(b : Bool) { if b { 1 } else { 0 } }
  if b2i(degenerate_ab) + b2i(degenerate_bc) + b2i(degenerate_cd) == 2 {
    return (RLine, Point::zero())
  }
  if !cubic_in_line(cubic) {
    return (RQuad, if degenerate_ab { cubic[2] } else { cubic[1] })
  }
  let t_values : Array[Float] = [0.0, 0.0, 0.0]
  let n = find_cubic_max_curvature(cubic, t_values)
  let mut r_count = 0
  for i in 0..<n {
    let t = t_values[i]
    if t <= 0.0 || t >= 1.0 {
      continue
    }
    reduction[r_count] = eval_cubic_pos_at(cubic, t)
    if reduction[r_count] != cubic[0] && reduction[r_count] != cubic[3] {
      r_count += 1
    }
  }
  let kind = match r_count {
    0 => RLine
    1 => RDegenerate
    2 => RDegenerate2
    _ => RDegenerate3
  }
  (kind, Point::zero())
}

///|
fn cubic_in_line(cubic : Array[Point]) -> Bool {
  let mut pt_max : Float = -1.0
  let mut outer1 = 0
  let mut outer2 = 0
  for index in 0..<3 {
    for inner in (index + 1)..<4 {
      let test_diff = cubic[inner] - cubic[index]
      let test_max = fmax(test_diff.x.abs(), test_diff.y.abs())
      if pt_max < test_max {
        outer1 = index
        outer2 = inner
        pt_max = test_max
      }
    }
  }
  let mid1 = (1 + (2 >> outer2)) >> outer1
  let mid2 = outer1 ^ outer2 ^ mid1
  let line_slop = pt_max * pt_max * 0.00001
  pt_to_line(cubic[mid1], cubic[outer1], cubic[outer2]) <= line_slop &&
  pt_to_line(cubic[mid2], cubic[outer1], cubic[outer2]) <= line_slop
}
