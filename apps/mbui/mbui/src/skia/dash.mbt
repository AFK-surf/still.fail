// tiny-skia's path dashing (path/src/dash.rs, after Skia's SkDashPath.cpp and SkContourMeasure.cpp).

///|
pub(all) struct StrokeDash {
  priv array : Array[Float]
  priv offset : Float
  priv interval_len : Float
  priv first_len : Float
  priv first_index : Int
}

///|
/// A dash of `dash_array`'s lengths (on, off, …: an even count of at least 2, none below 0, their sum above 0) from
/// `dash_offset`.
pub fn StrokeDash::new(dash_array : Array[Float], dash_offset : Float) -> StrokeDash? {
  if !fin(dash_offset) {
    return None
  }
  if dash_array.length() < 2 || dash_array.length() % 2 != 0 {
    return None
  }
  if dash_array.iter().any(fn(n) { n < 0.0 }) {
    return None
  }
  let mut interval_len : Float = 0.0
  for n in dash_array {
    interval_len = interval_len + n
  }
  if !(interval_len > 0.0 && fin(interval_len)) {
    return None
  }
  let dash_offset = adjust_dash_offset(dash_offset, interval_len)
  let (first_len, first_index) = find_first_interval(dash_array, dash_offset)
  Some({ array: dash_array, offset: dash_offset, interval_len, first_len, first_index })
}

///|
fn adjust_dash_offset(offset : Float, len : Float) -> Float {
  let mut offset = offset
  if offset < 0.0 {
    offset = -offset
    if offset > len {
      offset = offset % len
    }
    offset = len - offset
    if offset == len {
      offset = 0.0
    }
    offset
  } else if offset >= len {
    offset % len
  } else {
    offset
  }
}

///|
fn find_first_interval(dash_array : Array[Float], dash_offset : Float) -> (Float, Int) {
  let mut dash_offset = dash_offset
  for i, gap in dash_array {
    if dash_offset > gap || (dash_offset == gap && gap != 0.0) {
      dash_offset = dash_offset - gap
    } else {
      return (gap - dash_offset, i)
    }
  }
  (dash_array[0], 0)
}

///|
/// The path cut into `dash`'s dashes (Path::dash), None when there would be none or too many.
pub fn Path::dash(self : Path, dash : StrokeDash, resolution_scale : Float) -> Path? {
  let pb = PathBuilder::new()
  let mut dash_count : Float = 0.0
  let iter = ContourMeasureIter::new(self, resolution_scale)
  while iter.next() is Some(contour) {
    let mut skip_first_segment = contour.is_closed
    let mut added_segment = false
    let length = contour.length
    let mut index = dash.first_index
    dash_count = dash_count + length * fi(dash.array.length() >> 1) / dash.interval_len
    if dash_count > 1000000.0 {
      return None
    }
    let mut distance : Float = 0.0
    let mut d_len = dash.first_len
    while distance < length {
      added_segment = false
      if index % 2 == 0 && !skip_first_segment {
        added_segment = true
        contour.push_segment(distance, distance + d_len, true, pb)
      }
      distance = distance + d_len
      skip_first_segment = false
      index += 1
      if index == dash.array.length() {
        index = 0
      }
      d_len = dash.array[index]
    }
    if contour.is_closed && dash.first_index % 2 == 0 && dash.first_len >= 0.0 {
      contour.push_segment(0.0, dash.first_len, !added_segment, pb)
    }
  }
  pb.finish()
}

///|
let max_t_value : Int = 0x3FFFFFFF

///|
priv struct ContourMeasureIter {
  iter : PathSegmentsIter
  tolerance : Float
}

///|
fn ContourMeasureIter::new(path : Path, res_scale : Float) -> ContourMeasureIter {
  // (CHEAP_DIST_LIMIT: "just made this value up")
  { iter: path.segments(), tolerance: 0.5 * invert(res_scale) }
}

///|
fn ContourMeasureIter::next(self : ContourMeasureIter) -> ContourMeasure? {
  let contour = ContourMeasure::new()
  let mut point_index = 0
  let mut distance : Float = 0.0
  let mut have_seen_close = false
  let mut prev_p = Point::zero()
  while self.iter.next() is Some(seg) {
    match seg {
      MoveTo(p0) => {
        contour.points.push(p0)
        prev_p = p0
      }
      LineTo(p0) => {
        let prev_d = distance
        distance = contour.compute_line_seg(prev_p, p0, distance, point_index)
        if distance > prev_d {
          contour.points.push(p0)
          point_index += 1
        }
        prev_p = p0
      }
      QuadTo(p0, p1) => {
        let prev_d = distance
        distance = contour.compute_quad_segs(
          prev_p,
          p0,
          p1,
          distance,
          0,
          max_t_value,
          point_index,
          self.tolerance,
        )
        if distance > prev_d {
          contour.points.push(p0)
          contour.points.push(p1)
          point_index += 2
        }
        prev_p = p1
      }
      CubicTo(p0, p1, p2) => {
        let prev_d = distance
        distance = contour.compute_cubic_segs(
          prev_p,
          p0,
          p1,
          p2,
          distance,
          0,
          max_t_value,
          point_index,
          self.tolerance,
        )
        if distance > prev_d {
          contour.points.push(p0)
          contour.points.push(p1)
          contour.points.push(p2)
          point_index += 3
        }
        prev_p = p2
      }
      Close => have_seen_close = true
    }
    if self.iter.next_verb() is Some(Move) {
      break
    }
  }
  if !fin(distance) {
    return None
  }
  if have_seen_close {
    let prev_d = distance
    let first_pt = contour.points[0]
    distance = contour.compute_line_seg(contour.points[point_index], first_pt, distance, point_index)
    if distance > prev_d {
      contour.points.push(first_pt)
    }
  }
  contour.length = distance
  contour.is_closed = have_seen_close
  if contour.points.is_empty() {
    None
  } else {
    Some(contour)
  }
}

///|
priv enum SegmentType {
  SLine
  SQuad
  SCubic
} derive(Eq)

///|
priv struct Segment {
  /// total distance up to this point
  distance : Float
  /// into the contour's points
  point_index : Int
  t_value : Int
  kind : SegmentType
}

///|
fn Segment::scalar_t(self : Segment) -> Float {
  let max_t_reciprocal : Float = 1.0 / fi(max_t_value)
  fi(self.t_value) * max_t_reciprocal
}

///|
priv struct ContourMeasure {
  segments : Array[Segment]
  points : Array[Point]
  mut length : Float
  mut is_closed : Bool
}

///|
fn ContourMeasure::new() -> ContourMeasure {
  { segments: [], points: [], length: 0.0, is_closed: false }
}

///|
fn ContourMeasure::push_segment(
  self : ContourMeasure,
  start_d : Float,
  stop_d : Float,
  start_with_move_to : Bool,
  pb : PathBuilder,
) -> Unit {
  let start_d : Float = if start_d < 0.0 { 0.0 } else { start_d }
  let stop_d = if stop_d > self.length { self.length } else { stop_d }
  if !(start_d <= stop_d) {
    return
  }
  if self.segments.is_empty() {
    return
  }
  let (seg_index, start_t) = match self.distance_to_segment(start_d) {
    Some(v) => v
    None => return
  }
  let mut start_t = start_t
  let mut seg = self.segments[seg_index]
  let (stop_seg_index, stop_t) = match self.distance_to_segment(stop_d) {
    Some(v) => v
    None => return
  }
  let stop_seg = self.segments[stop_seg_index]
  if start_with_move_to {
    let p = compute_pos(self.points, seg.point_index, seg.kind, start_t)
    pb.move_to(p.x, p.y)
  }
  if seg.point_index == stop_seg.point_index {
    segment_to(self.points, seg.point_index, seg.kind, start_t, stop_t, pb)
  } else {
    let mut new_seg_index = seg_index
    while true {
      segment_to(self.points, seg.point_index, seg.kind, start_t, 1.0, pb)
      let old_point_index = seg.point_index
      while true {
        new_seg_index += 1
        if self.segments[new_seg_index].point_index != old_point_index {
          break
        }
      }
      seg = self.segments[new_seg_index]
      start_t = 0.0
      if seg.point_index >= stop_seg.point_index {
        break
      }
    }
    segment_to(self.points, seg.point_index, seg.kind, 0.0, stop_t, pb)
  }
}

///|
fn ContourMeasure::distance_to_segment(self : ContourMeasure, distance : Float) -> (Int, Float)? {
  let mut index = find_segment(self.segments, distance)
  index = index ^ (index >> 31)
  let seg = self.segments[index]
  let mut start_t : Float = 0.0
  let mut start_d : Float = 0.0
  if index > 0 {
    start_d = self.segments[index - 1].distance
    if self.segments[index - 1].point_index == seg.point_index {
      start_t = self.segments[index - 1].scalar_t()
    }
  }
  let t = start_t + (seg.scalar_t() - start_t) * (distance - start_d) / (seg.distance - start_d)
  // (NormalizedF32::new)
  if fin(t) && t >= 0.0 && t <= 1.0 {
    Some((index, t))
  } else {
    None
  }
}

///|
fn ContourMeasure::compute_line_seg(
  self : ContourMeasure,
  p0 : Point,
  p1 : Point,
  distance : Float,
  point_index : Int,
) -> Float {
  let d = p0.distance(p1)
  let prev_d = distance
  let distance = distance + d
  if distance > prev_d {
    self.segments.push({ distance, point_index, t_value: max_t_value, kind: SLine })
  }
  distance
}

///|
fn ContourMeasure::compute_quad_segs(
  self : ContourMeasure,
  p0 : Point,
  p1 : Point,
  p2 : Point,
  distance : Float,
  min_t : Int,
  max_t : Int,
  point_index : Int,
  tolerance : Float,
) -> Float {
  let mut distance = distance
  if t_span_big_enough(max_t - min_t) != 0 && quad_too_curvy(p0, p1, p2, tolerance) {
    let tmp = Array::make(5, Point::zero())
    let half_t = (min_t + max_t) >> 1
    chop_quad_at([p0, p1, p2], 0, 0.5, tmp, 0)
    distance = self.compute_quad_segs(tmp[0], tmp[1], tmp[2], distance, min_t, half_t, point_index, tolerance)
    distance = self.compute_quad_segs(tmp[2], tmp[3], tmp[4], distance, half_t, max_t, point_index, tolerance)
  } else {
    let d = p0.distance(p2)
    let prev_d = distance
    distance = distance + d
    if distance > prev_d {
      self.segments.push({ distance, point_index, t_value: max_t, kind: SQuad })
    }
  }
  distance
}

///|
fn ContourMeasure::compute_cubic_segs(
  self : ContourMeasure,
  p0 : Point,
  p1 : Point,
  p2 : Point,
  p3 : Point,
  distance : Float,
  min_t : Int,
  max_t : Int,
  point_index : Int,
  tolerance : Float,
) -> Float {
  let mut distance = distance
  if t_span_big_enough(max_t - min_t) != 0 && cubic_too_curvy(p0, p1, p2, p3, tolerance) {
    let tmp = Array::make(7, Point::zero())
    let half_t = (min_t + max_t) >> 1
    chop_cubic_at2([p0, p1, p2, p3], 0, 0.5, tmp, 0)
    distance = self.compute_cubic_segs(
      tmp[0],
      tmp[1],
      tmp[2],
      tmp[3],
      distance,
      min_t,
      half_t,
      point_index,
      tolerance,
    )
    distance = self.compute_cubic_segs(
      tmp[3],
      tmp[4],
      tmp[5],
      tmp[6],
      distance,
      half_t,
      max_t,
      point_index,
      tolerance,
    )
  } else {
    let d = p0.distance(p3)
    let prev_d = distance
    distance = distance + d
    if distance > prev_d {
      self.segments.push({ distance, point_index, t_value: max_t, kind: SCubic })
    }
  }
  distance
}

///|
/// The segment at `key` (binary search: its index, or the bitwise not of where it would go).
fn find_segment(base : Array[Segment], key : Float) -> Int {
  let mut lo = 0
  let mut hi = base.length() - 1
  while lo < hi {
    let mid = (hi + lo) >> 1
    if base[mid].distance < key {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if base[hi].distance < key {
    hi += 1
    hi = hi.lnot()
  } else if key < base[hi].distance {
    hi = hi.lnot()
  }
  hi
}

///|
fn compute_pos(points : Array[Point], at : Int, kind : SegmentType, t : Float) -> Point {
  match kind {
    SLine =>
      Point::from_xy(lerp(points[at].x, points[at + 1].x, t), lerp(points[at].y, points[at + 1].y, t))
    SQuad => eval_quad_at([points[at], points[at + 1], points[at + 2]], t)
    SCubic => eval_cubic_pos_at([points[at], points[at + 1], points[at + 2], points[at + 3]], t)
  }
}

///|
fn segment_to(
  points : Array[Point],
  at : Int,
  kind : SegmentType,
  start_t : Float,
  stop_t : Float,
  pb : PathBuilder,
) -> Unit {
  if start_t == stop_t {
    match pb.last_point() {
      Some(pt) => pb.line_to(pt.x, pt.y)
      None => ()
    }
    return
  }
  match kind {
    SLine =>
      if stop_t == 1.0 {
        pb.line_to(points[at + 1].x, points[at + 1].y)
      } else {
        pb.line_to(lerp(points[at].x, points[at + 1].x, stop_t), lerp(points[at].y, points[at + 1].y, stop_t))
      }
    SQuad => {
      let tmp0 = Array::make(5, Point::zero())
      let tmp1 = Array::make(5, Point::zero())
      if start_t == 0.0 {
        if stop_t == 1.0 {
          pb.quad_to_pt(points[at + 1], points[at + 2])
        } else {
          chop_quad_at(points, at, norm_excl_bounded(stop_t), tmp0, 0)
          pb.quad_to_pt(tmp0[1], tmp0[2])
        }
      } else {
        chop_quad_at(points, at, norm_excl_bounded(start_t), tmp0, 0)
        if stop_t == 1.0 {
          pb.quad_to_pt(tmp0[3], tmp0[4])
        } else {
          let new_t = (stop_t - start_t) / (1.0 - start_t)
          chop_quad_at(tmp0, 2, norm_excl_bounded(new_t), tmp1, 0)
          pb.quad_to_pt(tmp1[1], tmp1[2])
        }
      }
    }
    SCubic => {
      let tmp0 = Array::make(7, Point::zero())
      let tmp1 = Array::make(7, Point::zero())
      if start_t == 0.0 {
        if stop_t == 1.0 {
          pb.cubic_to_pt(points[at + 1], points[at + 2], points[at + 3])
        } else {
          chop_cubic_at2(points, at, norm_excl_bounded(stop_t), tmp0, 0)
          pb.cubic_to_pt(tmp0[1], tmp0[2], tmp0[3])
        }
      } else {
        chop_cubic_at2(points, at, norm_excl_bounded(start_t), tmp0, 0)
        if stop_t == 1.0 {
          pb.cubic_to_pt(tmp0[4], tmp0[5], tmp0[6])
        } else {
          let new_t = (stop_t - start_t) / (1.0 - start_t)
          chop_cubic_at2(tmp0, 3, norm_excl_bounded(new_t), tmp1, 0)
          pb.cubic_to_pt(tmp1[1], tmp1[2], tmp1[3])
        }
      }
    }
  }
}

///|
fn t_span_big_enough(t_span : Int) -> Int {
  t_span >> 10
}

///|
fn quad_too_curvy(p0 : Point, p1 : Point, p2 : Point, tolerance : Float) -> Bool {
  let dx = half(p1.x) - half(half(p0.x + p2.x))
  let dy = half(p1.y) - half(half(p0.y + p2.y))
  fmax(dx.abs(), dy.abs()) > tolerance
}

///|
fn cubic_too_curvy(p0 : Point, p1 : Point, p2 : Point, p3 : Point, tolerance : Float) -> Bool {
  let third : Float = 1.0 / 3.0
  let two_thirds : Float = 2.0 / 3.0
  let n0 = cheap_dist_exceeds_limit(p1, lerp(p0.x, p3.x, third), lerp(p0.y, p3.y, third), tolerance)
  let n1 = cheap_dist_exceeds_limit(p2, lerp(p0.x, p3.x, two_thirds), lerp(p0.y, p3.y, two_thirds), tolerance)
  n0 || n1
}

///|
fn cheap_dist_exceeds_limit(pt : Point, x : Float, y : Float, tolerance : Float) -> Bool {
  fmax((x - pt.x).abs(), (y - pt.y).abs()) > tolerance
}

///|
fn lerp(a : Float, b : Float, t : Float) -> Float {
  a + (b - a) * t
}
